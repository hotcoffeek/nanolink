import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hub.dart';
import 'models.dart';
import 'util.dart';

class _Tx {
  final RawDatagramSocket sock;
  final Nic nic;
  _Tx(this.sock, this.nic);
}

/// UDP-маяк: каждое устройство с NanoLink раз в 3 секунды сообщает «я здесь».
/// Маяки уходят с каждого реального сетевого интерфейса отдельно, чтобы VPN их не перехватывал.
class Discovery {
  final Hub hub;
  RawDatagramSocket? _rx;
  final List<_Tx> _tx = [];
  String _txKey = '';
  Timer? _timer;
  final Map<String, DateTime> _seen = {};

  Discovery(this.hub);

  DateTime? lastSeen(String id) => _seen[id];

  Future<void> start() async {
    try {
      _rx = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoPort, reuseAddress: true);
      _rx!.broadcastEnabled = true;
      _rx!.listen(_onEvent, onError: (Object e) {});
    } catch (_) {}
    await _tick();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _rx?.close();
    _rx = null;
    _closeTx();
  }

  void _closeTx() {
    for (final t in _tx) {
      try {
        t.sock.close();
      } catch (_) {}
    }
    _tx.clear();
    _txKey = '';
  }

  Future<void> _tick() async {
    try {
      final nics = await localNics(fresh: true);
      final key = (nics.map((e) => e.ip).toList()..sort()).join(',');
      if (key != _txKey) {
        _closeTx();
        for (final n in nics) {
          try {
            final s = await RawDatagramSocket.bind(InternetAddress(n.ip), 0);
            s.broadcastEnabled = true;
            _tx.add(_Tx(s, n));
          } catch (_) {}
        }
        _txKey = key;
      }
      announce();
    } catch (_) {}
  }

  List<int> _payload({bool reply = false}) => utf8.encode(jsonEncode({
        'nl': 1,
        'id': hub.myId,
        'name': hub.myName,
        'kind': hub.myKind.name,
        'port': kPeerPort,
        if (reply) 'r': 1,
      }));

  void announce() {
    final data = _payload();
    for (final t in _tx) {
      for (final target in ['255.255.255.255', t.nic.broadcast]) {
        try {
          t.sock.send(data, InternetAddress(target), kDiscoPort);
        } catch (_) {}
      }
    }
  }

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final rx = _rx;
    if (rx == null) return;
    var d = rx.receive();
    while (d != null) {
      _handle(d);
      d = rx.receive();
    }
  }

  void _handle(Datagram d) {
    try {
      final j = jsonDecode(utf8.decode(d.data, allowMalformed: true));
      if (j is! Map || j['nl'] != 1) return;
      final id = (j['id'] ?? '').toString();
      if (id.isEmpty || id == hub.myId) return;
      final ip = d.address.address;
      final name = (j['name'] ?? 'Устройство').toString();
      final kind = kindFromName(j['kind']?.toString());
      final port = (j['port'] as num?)?.toInt() ?? kPeerPort;

      final prev = _seen[id];
      _seen[id] = DateTime.now();
      hub.onBeacon(id, name, kind, ip, port);

      // Первое знакомство - сразу отвечаем напрямую, чтобы не ждать следующего маяка
      final fresh = prev == null || DateTime.now().difference(prev).inSeconds > 8;
      if (fresh && j['r'] != 1 && _tx.isNotEmpty) {
        _tx.first.sock.send(_payload(reply: true), d.address, kDiscoPort);
      }
    } catch (_) {}
  }
}

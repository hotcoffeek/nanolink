import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'frame_socket.dart';
import 'hub.dart';
import 'models.dart';
import 'util.dart';
import 'vfs.dart';

String hmacHex(String secret, String msg) {
  final h = Hmac(sha256, utf8.encode(secret));
  return h.convert(utf8.encode(msg)).toString();
}

class DeniedError extends FsError {
  DeniedError() : super('Доступ запрещён устройством', retry: false);
}

/// Спросить у IP, есть ли там NanoLink (без авторизации). Возвращает id/имя/тип.
Future<Map<String, dynamic>?> probeNano(String ip, {int port = kPeerPort}) async {
  try {
    final s = await lanConnect(ip, port, timeout: const Duration(milliseconds: 1500));
    final fs = FrameSocket(s);
    try {
      fs.sendJson({'t': 'hello', 'probe': true, 'id': 'probe'});
      final m = await fs.readJson(idle: const Duration(seconds: 2));
      if (m['t'] == 'info') return m;
    } finally {
      fs.destroy();
    }
  } catch (_) {}
  return null;
}

/// Открыть авторизованное соединение с NanoLink-устройством (управляющее или для передачи данных).
Future<FrameSocket> peerHandshake(Device dev, Hub hub) async {
  final host = dev.host;
  if (host == null || host.isEmpty) throw FsError('Адрес устройства неизвестен', retry: true);
  final sock = await lanConnect(host, dev.portOf('nano', kPeerPort), timeout: const Duration(seconds: 4));
  final fs = FrameSocket(sock);
  try {
    final secret = hub.trustedSecret(dev.id);
    fs.sendJson({
      't': 'hello',
      'id': hub.myId,
      'name': hub.myName,
      'kind': hub.myKind.name,
      'hs': secret != null,
      'v': 1,
    });
    var m = await fs.readJson(idle: const Duration(seconds: 8));
    if (m['t'] == 'challenge' && secret != null) {
      final nonce = (m['nonce'] ?? '').toString();
      fs.sendJson({'t': 'auth', 'mac': hmacHex(secret, nonce + hub.myId)});
      m = await fs.readJson(idle: const Duration(seconds: 8));
    } else if (m['t'] == 'pair') {
      fs.sendJson({'t': 'pair'});
      // человек на другой стороне должен нажать «Разрешить»
      m = await fs.readJson(idle: const Duration(seconds: 75));
      if (m['t'] == 'paired') {
        hub.trust(dev.id, (m['secret'] ?? '').toString(), name: dev.name, kind: dev.kind, ip: host);
        m = await fs.readJson(idle: const Duration(seconds: 8));
      }
    }
    if (m['t'] != 'ready') throw DeniedError();
    return fs;
  } catch (e) {
    fs.destroy();
    rethrow;
  }
}

class PeerVfs extends RemoteVfs {
  PeerVfs(Device dev, Hub hub) : super(dev, hub);

  FrameSocket? _fs;
  Future<void> _lock = Future<void>.value();
  Timer? _hb;
  bool _closed = false;
  bool _beating = false;
  Set<String> roots = {};

  @override
  String get title => dev.title;

  @override
  void resetConn() => _drop();

  void _drop() {
    _fs?.destroy();
    _fs = null;
  }

  Future<FrameSocket> _ensure() async {
    final f = _fs;
    if (f != null && !f.closed) return f;
    final n = await peerHandshake(dev, hub);
    _fs = n;
    return n;
  }

  /// Один запрос на управляющем соединении (запросы идут по очереди).
  Future<Map<String, dynamic>> call(String op, [Map<String, dynamic>? args, Duration idle = const Duration(seconds: 20)]) {
    final c = Completer<Map<String, dynamic>>();
    _lock = _lock.then((_) async {
      try {
        final fs = await _ensure();
        try {
          fs.sendJson({'op': op, ...?args});
          final r = await fs.readJson(idle: idle);
          if (r['ok'] != true) {
            c.completeError(FsError((r['err'] ?? 'Ошибка на устройстве').toString()));
            return;
          }
          c.complete(r);
        } catch (e) {
          _drop();
          rethrow;
        }
      } catch (e, s) {
        if (!c.isCompleted) c.completeError(e, s);
      }
    });
    return c.future;
  }

  void startMonitor() {
    _hb ??= Timer.periodic(const Duration(seconds: 5), (_) => _beat());
  }

  Future<void> _beat() async {
    if (_closed || _beating) return;
    _beating = true;
    try {
      await call('ping', null, const Duration(seconds: 6));
      dev.aliveAt = DateTime.now().millisecondsSinceEpoch;
      if (!dev.online) {
        dev.online = true;
        hub.deviceChanged();
      }
    } catch (e) {
      if (e is DeniedError) {
        _hb?.cancel();
        _hb = null;
      } else {
        if (dev.online) {
          dev.online = false;
          hub.deviceChanged();
        }
        try {
          await hub.heal(dev);
        } catch (_) {}
      }
    } finally {
      _beating = false;
    }
  }

  @override
  Future<String> start() async {
    final r = await guard(() => call('roots'));
    roots = ((r['roots'] as List?) ?? const []).map((e) => e.toString()).toSet();
    return '/';
  }

  @override
  Future<List<Place>> places() async {
    try {
      final r = await guard(() => call('places'));
      return ((r['places'] as List?) ?? const [])
          .map((e) => Place.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  String parent(String p) {
    if (roots.contains(p)) return '/';
    return super.parent(p);
  }

  @override
  Future<List<FsEntry>> list(String path) async {
    final r = await guard(() => call('list', {'p': path}));
    return ((r['e'] as List?) ?? const [])
        .map((x) => FsEntry.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList();
  }

  @override
  Future<void> mkdir(String path) async {
    await guard(() => call('mkdir', {'p': path}));
  }

  @override
  Future<void> rename(String from, String to) async {
    await guard(() => call('rename', {'p': from, 'to': to}));
  }

  @override
  Future<void> delete(String path) async {
    await guard(() => call('delete', {'p': path}));
  }

  @override
  Future<int> fileSize(String path) async {
    final r = await guard(() => call('size', {'p': path}));
    return (r['s'] as num?)?.toInt() ?? -1;
  }

  @override
  Stream<List<int>> read(String path, int offset) async* {
    final fs = await peerHandshake(dev, hub);
    try {
      fs.sendJson({'op': 'get', 'p': path, 'off': offset});
      final r = await fs.readJson(idle: const Duration(seconds: 20));
      if (r['ok'] != true) throw FsError((r['err'] ?? 'Не удалось прочитать файл').toString());
      var remaining = (r['len'] as num).toInt();
      while (remaining > 0) {
        final b = await fs.readSome(min(remaining, 1 << 20), idle: const Duration(seconds: 15));
        remaining -= b.length;
        yield b;
      }
    } finally {
      fs.destroy();
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false}) async {
    final fs = await peerHandshake(dev, hub);
    try {
      fs.sendJson({'op': 'put', 'p': path, 'append': append, 'len': len});
      final r = await fs.readJson(idle: const Duration(seconds: 20));
      if (r['ok'] != true) throw FsError((r['err'] ?? 'Не удалось записать файл').toString());
      await fs.socket.addStream(data);
      final d = await fs.readJson(idle: const Duration(seconds: 30));
      if (d['ok'] != true) throw FsError((d['err'] ?? 'Ошибка записи').toString(), retry: true);
    } finally {
      fs.destroy();
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _hb?.cancel();
    _hb = null;
    _drop();
  }
}

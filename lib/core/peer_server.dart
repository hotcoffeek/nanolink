import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'frame_socket.dart';
import 'hub.dart';
import 'local_vfs.dart';
import 'models.dart';
import 'peer.dart';
import 'util.dart';

class _PeerInfo {
  final String id;
  final String name;
  final DeviceKind kind;
  final String ip;
  _PeerInfo(this.id, this.name, this.kind, this.ip);
}

/// Сервер NanoLink: отдаёт файлы этого устройства сопряжённым устройствам.
class PeerServer {
  final Hub hub;
  final LocalVfs _lv = LocalVfs();
  ServerSocket? _srv;
  bool get running => _srv != null;

  PeerServer(this.hub);

  Future<void> start() async {
    if (_srv != null) return;
    _srv = await ServerSocket.bind(InternetAddress.anyIPv4, kPeerPort, shared: true);
    _srv!.listen(_onConn, onError: (Object e) {}, cancelOnError: false);
  }

  Future<void> stop() async {
    final s = _srv;
    _srv = null;
    try {
      await s?.close();
    } catch (_) {}
  }

  Future<void> _onConn(Socket s) async {
    final fs = FrameSocket(s);
    final ip = s.remoteAddress.address;
    var graceful = false;
    try {
      final peer = await _handshake(fs, ip);
      if (peer == null) {
        graceful = true;
        await fs.closeGraceful();
        return;
      }
      graceful = await _serve(fs, peer);
    } catch (_) {
      // клиент ушёл/сеть оборвалась - это нормально
    } finally {
      if (graceful) {
        await fs.closeGraceful();
      } else {
        fs.destroy();
      }
    }
  }

  Future<_PeerInfo?> _handshake(FrameSocket fs, String ip) async {
    final h = await fs.readJson(idle: const Duration(seconds: 10));
    if (h['t'] != 'hello') return null;
    if (h['probe'] == true) {
      fs.sendJson({'t': 'info', 'id': hub.myId, 'name': hub.myName, 'kind': hub.myKind.name});
      return null;
    }
    final id = (h['id'] ?? '').toString();
    final name = (h['name'] ?? 'Устройство').toString();
    final kind = kindFromName(h['kind']?.toString());
    if (id.isEmpty || id == hub.myId) return null;

    final secret = hub.trustedSecret(id);
    if (secret != null && h['hs'] == true) {
      final nonce = randomHex(16);
      fs.sendJson({'t': 'challenge', 'nonce': nonce, 'sid': hub.myId});
      final a = await fs.readJson(idle: const Duration(seconds: 10));
      if (a['t'] == 'auth' && a['mac'] == hmacHex(secret, nonce + id)) {
        fs.sendJson({'t': 'ready', 'sid': hub.myId});
        return _PeerInfo(id, name, kind, ip);
      }
      if (!hub.autoPairOn) {
        fs.sendJson({'t': 'denied'});
        return null;
      }
    }

    // Первое знакомство: спрашиваем разрешение у человека
    fs.sendJson({'t': 'pair', 'sid': hub.myId, 'sname': hub.myName, 'skind': hub.myKind.name});
    final p = await fs.readJson(idle: const Duration(seconds: 10));
    if (p['t'] != 'pair') return null;
    final ok = await hub.askPair(PairRequest(id: id, name: name, kind: kind, ip: ip));
    if (!ok) {
      fs.sendJson({'t': 'denied'});
      return null;
    }
    final newSecret = randomHex(24);
    hub.trust(id, newSecret, name: name, kind: kind, ip: ip);
    fs.sendJson({'t': 'paired', 'secret': newSecret});
    fs.sendJson({'t': 'ready', 'sid': hub.myId});
    return _PeerInfo(id, name, kind, ip);
  }

  void _err(FrameSocket fs, Object e) {
    fs.sendJson({'ok': false, 'err': e is FsError ? e.message : e.toString()});
  }

  /// Возвращает true, если соединение можно закрыть «мягко» (после передачи данных).
  Future<bool> _serve(FrameSocket fs, _PeerInfo peer) async {
    while (true) {
      final m = await fs.readJson(idle: const Duration(seconds: 30));
      final op = (m['op'] ?? '').toString();
      final p = (m['p'] ?? '/').toString();
      try {
        switch (op) {
          case 'ping':
            fs.sendJson({'ok': true});
            break;
          case 'roots':
            fs.sendJson({'ok': true, 'roots': await _roots()});
            break;
          case 'places':
            final pl = await _lv.places();
            fs.sendJson({'ok': true, 'places': pl.map((e) => Place(e.name, localToWire(e.path), e.icon).toJson()).toList()});
            break;
          case 'list':
            final l = await _lv.list(wireToLocal(p));
            fs.sendJson({
              'ok': true,
              'e': l
                  .map((e) => FsEntry(
                        name: e.name,
                        path: localToWire(e.path),
                        isDir: e.isDir,
                        size: e.size,
                        modified: e.modified,
                      ).toJson())
                  .toList(),
            });
            break;
          case 'size':
            fs.sendJson({'ok': true, 's': await _lv.fileSize(wireToLocal(p))});
            break;
          case 'mkdir':
            _needWrite();
            await _lv.mkdir(wireToLocal(p));
            fs.sendJson({'ok': true});
            break;
          case 'rename':
            _needWrite();
            final toLocal = wireToLocal((m['to'] ?? '').toString());
            await _lv.rename(wireToLocal(p), toLocal);
            if (p.endsWith('.nlpart') && !toLocal.endsWith('.nlpart')) hub.onReceived(peer.name, toLocal);
            fs.sendJson({'ok': true});
            break;
          case 'delete':
            _needWrite();
            await _lv.delete(wireToLocal(p));
            fs.sendJson({'ok': true});
            break;
          case 'get':
            await _get(fs, wireToLocal(p), (m['off'] as num?)?.toInt() ?? 0);
            return true;
          case 'put':
            await _put(fs, wireToLocal(p), (m['len'] as num).toInt(), m['append'] == true);
            return true;
          default:
            fs.sendJson({'ok': false, 'err': 'неизвестная команда'});
        }
      } catch (e) {
        if (e is SocketException || e is TimeoutException) rethrow;
        _err(fs, e);
        if (op == 'get' || op == 'put') return true;
      }
    }
  }

  void _needWrite() {
    if (!hub.allowWrite) throw FsError('На этом устройстве запрещена запись (см. настройки)');
  }

  Future<List<String>> _roots() async {
    final l = await _lv.list('');
    return l.map((e) => localToWire(e.path)).toList();
  }

  Future<void> _get(FrameSocket fs, String local, int off) async {
    final f = File(local);
    if (!await f.exists()) throw FsError('Файл не найден');
    final size = await f.length();
    final start = min(max(off, 0), size);
    fs.sendJson({'ok': true, 'len': size - start, 'size': size});
    if (size - start > 0) {
      await fs.socket.addStream(_lv.read(local, start));
    }
    await fs.socket.flush();
  }

  Future<void> _put(FrameSocket fs, String local, int len, bool append) async {
    _needWrite();
    final f = File(local);
    await f.parent.create(recursive: true);
    final raf = await f.open(mode: append ? FileMode.append : FileMode.write);
    try {
      fs.sendJson({'ok': true});
      var remaining = len;
      while (remaining > 0) {
        final b = await fs.readSome(min(remaining, 1 << 20), idle: const Duration(seconds: 20));
        await raf.writeFrom(b);
        remaining -= b.length;
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
    fs.sendJson({'ok': true, 'size': await f.length()});
  }
}

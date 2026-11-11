import 'dart:async';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';

import 'hub.dart';
import 'models.dart';
import 'util.dart';
import 'vfs.dart';

/// SMB (Samba / Windows-шары): ТВ-приставки, Steam Deck, NAS, ПК.
/// Корень '/' - список шар, дальше '/шара/папка/файл'.
class SmbVfs extends RemoteVfs {
  SmbVfs(Device dev, Hub hub) : super(dev, hub);

  SmbConnect? _c;
  String? _slot; // ключ занятого «места» на хосте (освобождается при закрытии соединения)

  void _freeSlot() {
    final k = _slot;
    _slot = null;
    if (k != null) HostSlots.release(k);
  }

  @override
  String get title => dev.title;

  @override
  void resetConn() {
    final c = _c;
    _c = null;
    if (c != null) {
      unawaited(c.close().catchError((Object _) {}));
    }
    _freeSlot();
  }

  @override
  String parent(String p) {
    if (p.isEmpty || p == '/') return '/';
    return super.parent(p);
  }

  Future<SmbConnect> _conn() async {
    final c = _c;
    if (c != null) return c;
    final user = dev.str('smb', 'user');
    final pass = dev.str('smb', 'pass') ?? '';
    SmbConnect n;
    final slotKey = 'smb|${hostOrThrow}';
    await HostSlots.acquire(slotKey);
    _slot = slotKey;
    try {
      n = await SmbConnect.connectAuth(
        host: hostOrThrow,
        domain: '',
        username: (user == null || user.isEmpty) ? 'guest' : user,
        password: pass,
        onDisconnect: (_) {
          _c = null;
          _freeSlot();
        },
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      _freeSlot();
      rethrow;
    } catch (e) {
      _freeSlot();
      final t = e.toString().toLowerCase();
      if (t.contains('logon') || t.contains('denied') || t.contains('password') || t.contains('auth')) {
        throw FsError('SMB: неверный логин или пароль');
      }
      rethrow;
    }
    _c = n;
    return n;
  }

  String _clean(String name) {
    var n = name;
    while (n.endsWith('/')) {
      n = n.substring(0, n.length - 1);
    }
    final i = n.lastIndexOf('/');
    return i >= 0 ? n.substring(i + 1) : n;
  }

  @override
  Future<String> start() async => '/';

  @override
  Future<List<FsEntry>> list(String path) => guard(() async {
        final c = await _conn();
        final out = <FsEntry>[];
        if (path.isEmpty || path == '/') {
          final shares = await c.listShares().timeout(const Duration(seconds: 20));
          for (final s in shares) {
            final n = _clean(s.path.isNotEmpty ? s.path : s.name);
            if (n.isEmpty || n.endsWith(r'$')) continue;
            out.add(FsEntry(name: n, path: '/$n', isDir: true));
          }
          return out;
        }
        final folder = await c.file(path).timeout(const Duration(seconds: 20));
        final files = await c.listFiles(folder).timeout(const Duration(seconds: 25));
        for (final f in files) {
          final n = _clean(f.name);
          if (n.isEmpty || n == '.' || n == '..') continue;
          final isDir = f.isDirectory();
          out.add(FsEntry(
            name: n,
            path: join(path, n),
            isDir: isDir,
            size: isDir ? 0 : f.size,
            modified: f.lastModified > 0 ? DateTime.fromMillisecondsSinceEpoch(f.lastModified) : null,
          ));
        }
        return out;
      });

  @override
  Future<void> mkdir(String path) => guard(() async {
        final c = await _conn();
        final f = await c.file(path);
        if (f.isExists) return;
        await c.createFolder(path);
      });

  @override
  Future<void> rename(String from, String to) => guard(() async {
        final c = await _conn();
        final f = await c.file(from);
        await c.rename(f, to);
      });

  @override
  Future<void> delete(String path) => guard(() async {
        final c = await _conn();
        await _deleteRec(c, path);
      });

  Future<void> _deleteRec(SmbConnect c, String path) async {
    final f = await c.file(path);
    if (!f.isExists) return;
    if (f.isDirectory()) {
      final kids = await c.listFiles(f);
      for (final k in kids) {
        final n = _clean(k.name);
        if (n.isEmpty || n == '.' || n == '..') continue;
        await _deleteRec(c, join(path, n));
      }
    }
    await c.delete(await c.file(path));
  }

  @override
  Future<int> fileSize(String path) => guard(() async {
        final c = await _conn();
        final f = await c.file(path);
        return f.isExists ? f.size : -1;
      });

  @override
  Stream<List<int>> read(String path, int offset) async* {
    final c = await guard(_conn);
    final f = await c.file(path);
    if (!f.isExists) throw FsError('SMB: файл не найден');
    final s = await c.openRead(f, offset > 0 ? offset : null);
    yield* s;
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false}) async {
    final c = await guard(_conn);
    var f = await c.file(path);
    if (!f.isExists) {
      f = await c.createFile(path);
    }
    final sink = await c.openWrite(f, append: append);
    try {
      await sink.addStream(data.map<Uint8List>((x) => x is Uint8List ? x : Uint8List.fromList(x)));
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> close() async => resetConn();
}

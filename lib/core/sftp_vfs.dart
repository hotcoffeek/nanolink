import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'hub.dart';
import 'models.dart';
import 'util.dart';
import 'vfs.dart';

/// SFTP (SSH) - например Steam Deck с включённым SSH.
class SftpVfs extends RemoteVfs {
  SftpVfs(Device dev, Hub hub) : super(dev, hub);

  SSHClient? _client;
  SftpClient? _sftp;
  String _home = '/';

  @override
  String get title => dev.title;

  @override
  void resetConn() {
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _sftp = null;
  }

  @override
  String parent(String p) {
    if (p.isEmpty || p == '/') return '/';
    return super.parent(p);
  }

  Future<SftpClient> _ensure() async {
    final s = _sftp;
    if (s != null) return s;
    final user = dev.str('sftp', 'user') ?? 'deck';
    final pass = dev.str('sftp', 'pass') ?? '';
    final socket = await SSHSocket.connect(hostOrThrow, dev.portOf('sftp', 22)).timeout(const Duration(seconds: 6));
    final client = SSHClient(
      socket,
      username: user,
      onPasswordRequest: () => pass,
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 12));
    } catch (e) {
      try {
        client.close();
      } catch (_) {}
      if (e is TimeoutException) rethrow;
      throw FsError('SFTP: не удалось войти (проверьте логин и пароль)');
    }
    final sftp = await client.sftp();
    _client = client;
    _sftp = sftp;
    client.done.then((_) {
      if (identical(_client, client)) {
        _client = null;
        _sftp = null;
      }
    }, onError: (Object _) {
      if (identical(_client, client)) {
        _client = null;
        _sftp = null;
      }
    });
    return sftp;
  }

  @override
  Future<String> start() async {
    return guard(() async {
      final s = await _ensure();
      try {
        _home = await s.absolute('.');
      } catch (_) {
        _home = '/';
      }
      return _home;
    });
  }

  Future<bool> _isDir(SftpName n, String path) async {
    final ln = n.longname;
    if (ln.isNotEmpty && RegExp(r'^[\-dlbcps]').hasMatch(ln)) {
      if (ln[0] == 'l') {
        try {
          final s = await _ensure();
          final st = await s.stat(path);
          final l2 = st.isDirectory;
          return l2;
        } catch (_) {
          return false;
        }
      }
      return ln[0] == 'd';
    }
    return n.attr.isDirectory;
  }

  @override
  Future<List<FsEntry>> list(String path) {
    final dir = path.isEmpty ? '/' : path;
    return guard(() async {
      final s = await _ensure();
      final names = await s.listdir(dir);
      final out = <FsEntry>[];
      for (final n in names) {
        if (n.filename == '.' || n.filename == '..') continue;
        final p = join(dir, n.filename);
        final isDir = await _isDir(n, p);
        final mt = n.attr.modifyTime;
        out.add(FsEntry(
          name: n.filename,
          path: p,
          isDir: isDir,
          size: n.attr.size ?? 0,
          modified: mt == null ? null : DateTime.fromMillisecondsSinceEpoch(mt * 1000),
        ));
      }
      return out;
    });
  }

  @override
  Future<void> mkdir(String path) => guard(() async {
        final s = await _ensure();
        try {
          await s.mkdir(path);
        } catch (e) {
          // уже существует - не страшно
          try {
            final st = await s.stat(path);
            if (st.isDirectory) return;
          } catch (_) {}
          rethrow;
        }
      });

  @override
  Future<void> rename(String from, String to) => guard(() async {
        final s = await _ensure();
        await s.rename(from, to);
      });

  @override
  Future<void> delete(String path) => guard(() async {
        final s = await _ensure();
        await _deleteRec(s, path);
      });

  Future<void> _deleteRec(SftpClient s, String path) async {
    SftpFileAttrs st;
    try {
      st = await s.stat(path, followLink: false);
    } catch (_) {
      return;
    }
    if (st.isDirectory) {
      final names = await s.listdir(path);
      for (final n in names) {
        if (n.filename == '.' || n.filename == '..') continue;
        await _deleteRec(s, join(path, n.filename));
      }
      await s.rmdir(path);
    } else {
      await s.remove(path);
    }
  }

  @override
  Future<int> fileSize(String path) => guard(() async {
        final s = await _ensure();
        try {
          final st = await s.stat(path);
          return st.size ?? 0;
        } catch (e) {
          final t = e.toString().toLowerCase();
          if (t.contains('no such') || t.contains('not found') || t.contains('code 2') || t.contains('nosuch')) return -1;
          rethrow;
        }
      });

  @override
  Stream<List<int>> read(String path, int offset) async* {
    final s = await guard(_ensure);
    final f = await s.open(path);
    try {
      await for (final c in f.read(offset: offset)) {
        yield c;
      }
    } finally {
      try {
        await f.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false}) async {
    final s = await guard(_ensure);
    final mode = append
        ? (SftpFileOpenMode.create | SftpFileOpenMode.write)
        : (SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    final f = await s.open(path, mode: mode);
    try {
      var off = 0;
      if (append) {
        final st = await f.stat();
        off = st.size ?? 0;
      }
      final stream = data.map<Uint8List>((c) => c is Uint8List ? c : Uint8List.fromList(c));
      final w = f.write(stream, offset: off);
      await w.done;
    } finally {
      try {
        await f.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async => resetConn();
}

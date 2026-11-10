import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'hub.dart';
import 'models.dart';
import 'util.dart';
import 'vfs.dart';

class _Reply {
  final int code;
  final String text;
  _Reply(this.code, this.text);
}

/// Минимальный, но устойчивый FTP-клиент (пассивный режим, MLSD/LIST, докачка REST/APPE).
class _FtpConn {
  final Socket sock;
  final String host;
  late final StreamIterator<String> _it;

  _FtpConn._(this.sock, this.host) {
    _it = StreamIterator<String>(
      sock.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()),
    );
  }

  static Future<_FtpConn> open(String host, int port, String user, String pass) async {
    final s = await lanConnect(host, port, timeout: const Duration(seconds: 5));
    final c = _FtpConn._(s, host);
    try {
      final hello = await c._read();
      if (hello.code >= 400) throw FsError('FTP: сервер отказал (${hello.code})', retry: true);
      var r = await c.cmd('USER $user');
      if (r.code == 331 || r.code == 332) r = await c.cmd('PASS $pass');
      if (r.code != 230 && r.code != 202) throw FsError('FTP: неверный логин или пароль');
      await c.cmd('TYPE I');
      return c;
    } catch (e) {
      c.close();
      rethrow;
    }
  }

  Future<_Reply> _read() async {
    String? first;
    final buf = <String>[];
    while (true) {
      final ok = await _it.moveNext().timeout(const Duration(seconds: 20));
      if (!ok) throw const SocketException('ftp: соединение закрыто');
      final line = _it.current;
      buf.add(line);
      if (line.length >= 4 && int.tryParse(line.substring(0, 3)) != null) {
        first ??= line.substring(0, 3);
        if (line[3] == ' ' && line.substring(0, 3) == first) {
          return _Reply(int.parse(first), buf.join('\n'));
        }
      }
    }
  }

  Future<_Reply> cmd(String c) {
    sock.write('$c\r\n');
    return _read();
  }

  Future<Socket> dataSocket() async {
    var r = await cmd('EPSV');
    int? port;
    if (r.code == 229) {
      final m = RegExp(r'\|\|\|(\d+)\|').firstMatch(r.text);
      if (m != null) port = int.parse(m.group(1)!);
    }
    if (port == null) {
      r = await cmd('PASV');
      if (r.code != 227) throw FsError('FTP: сервер не поддерживает пассивный режим');
      final m = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(r.text);
      if (m == null) throw FsError('FTP: странный ответ PASV');
      port = int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
    }
    // всегда подключаемся к адресу управляющего соединения (серверы за NAT врут в PASV)
    return lanConnect(host, port, timeout: const Duration(seconds: 6));
  }

  void close() {
    try {
      sock.write('QUIT\r\n');
    } catch (_) {}
    try {
      sock.destroy();
    } catch (_) {}
  }
}

class FtpVfs extends RemoteVfs {
  FtpVfs(Device dev, Hub hub) : super(dev, hub);

  @override
  String get title => dev.title;

  @override
  void resetConn() {}

  @override
  String parent(String p) {
    if (p.isEmpty || p == '/') return '/';
    return super.parent(p);
  }

  Future<_FtpConn> _open() {
    final user = dev.str('ftp', 'user');
    final pass = dev.str('ftp', 'pass');
    return _FtpConn.open(
      hostOrThrow,
      dev.portOf('ftp', 21),
      (user == null || user.isEmpty) ? 'anonymous' : user,
      pass ?? 'nanolink@local',
    );
  }

  Future<T> _with<T>(Future<T> Function(_FtpConn c) body) {
    return guard(() async {
      final c = await _open();
      try {
        return await body(c);
      } finally {
        c.close();
      }
    });
  }

  @override
  Future<String> start() async => '/';

  @override
  Future<List<FsEntry>> list(String path) {
    final dir = path.isEmpty ? '/' : path;
    return _with((c) async {
      final cw = await c.cmd('CWD $dir');
      if (cw.code >= 400) throw FsError('FTP: нет такой папки или нет доступа');
      var raw = await _listRaw(c, 'MLSD');
      var mlsd = true;
      if (raw == null) {
        raw = await _listRaw(c, 'LIST');
        mlsd = false;
      }
      if (raw == null) throw FsError('FTP: сервер не отдал список файлов', retry: true);
      final out = <FsEntry>[];
      for (final line in const LineSplitter().convert(raw)) {
        final e = mlsd ? _parseMlsd(line, dir) : _parseList(line, dir);
        if (e != null) out.add(e);
      }
      return out;
    });
  }

  Future<String?> _listRaw(_FtpConn c, String command) async {
    final ds = await c.dataSocket();
    try {
      final r = await c.cmd(command);
      if (r.code >= 400) return null;
      final text = await const Utf8Codec(allowMalformed: true).decodeStream(ds);
      try {
        await c._read();
      } catch (_) {}
      return text;
    } finally {
      ds.destroy();
    }
  }

  FsEntry? _parseMlsd(String line, String dir) {
    final sp = line.indexOf(' ');
    if (sp < 0) return null;
    final facts = line.substring(0, sp).split(';');
    final name = line.substring(sp + 1).trim();
    if (name.isEmpty || name == '.' || name == '..') return null;
    String type = '';
    int size = 0;
    DateTime? mod;
    for (final f in facts) {
      final i = f.indexOf('=');
      if (i < 0) continue;
      final k = f.substring(0, i).toLowerCase();
      final v = f.substring(i + 1);
      if (k == 'type') type = v.toLowerCase();
      if (k == 'size') size = int.tryParse(v) ?? 0;
      if (k == 'modify' && v.length >= 14) {
        mod = DateTime.tryParse('${v.substring(0, 8)}T${v.substring(8, 14)}Z')?.toLocal();
      }
    }
    if (type == 'cdir' || type == 'pdir') return null;
    return FsEntry(name: name, path: join(dir, name), isDir: type == 'dir', size: size, modified: mod);
  }

  static final RegExp _unix = RegExp(r'^([\-dlbcps])[rwxsStT\-]{9}[+@.]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w{3}\s+\d+\s+[\d:]+)\s+(.+)$');
  static final RegExp _dos = RegExp(r'^(\d\d-\d\d-\d\d)\s+(\d\d:\d\d[AP]M)\s+(<DIR>|\d+)\s+(.+)$');

  FsEntry? _parseList(String line, String dir) {
    final u = _unix.firstMatch(line);
    if (u != null) {
      var name = u.group(4)!.trim();
      final arrow = name.indexOf(' -> ');
      if (arrow > 0) name = name.substring(0, arrow);
      if (name == '.' || name == '..') return null;
      return FsEntry(name: name, path: join(dir, name), isDir: u.group(1) == 'd', size: int.tryParse(u.group(2)!) ?? 0);
    }
    final d = _dos.firstMatch(line);
    if (d != null) {
      final name = d.group(4)!.trim();
      final isDir = d.group(3) == '<DIR>';
      return FsEntry(name: name, path: join(dir, name), isDir: isDir, size: isDir ? 0 : int.tryParse(d.group(3)!) ?? 0);
    }
    return null;
  }

  @override
  Future<void> mkdir(String path) => _with((c) async {
        final r = await c.cmd('MKD $path');
        if (r.code >= 400 && r.code != 550) throw FsError('FTP: не удалось создать папку');
      });

  @override
  Future<void> rename(String from, String to) => _with((c) async {
        final a = await c.cmd('RNFR $from');
        if (a.code >= 400) throw FsError('FTP: не удалось переименовать');
        final b = await c.cmd('RNTO $to');
        if (b.code >= 400) throw FsError('FTP: не удалось переименовать');
      });

  @override
  Future<void> delete(String path) => _with((c) => _deleteRec(c, path));

  Future<void> _deleteRec(_FtpConn c, String path) async {
    final r = await c.cmd('DELE $path');
    if (r.code < 400) return;
    // возможно, это папка
    final cw = await c.cmd('CWD $path');
    if (cw.code < 400) {
      var raw = await _listRaw(c, 'MLSD');
      var mlsd = true;
      if (raw == null) {
        raw = await _listRaw(c, 'LIST');
        mlsd = false;
      }
      for (final line in const LineSplitter().convert(raw ?? '')) {
        final e = mlsd ? _parseMlsd(line, path) : _parseList(line, path);
        if (e != null) await _deleteRec(c, e.path);
      }
      await c.cmd('CWD /');
    }
    final rd = await c.cmd('RMD $path');
    if (rd.code >= 400) throw FsError('FTP: не удалось удалить $path');
  }

  @override
  Future<int> fileSize(String path) => _with((c) async {
        final r = await c.cmd('SIZE $path');
        if (r.code == 213) {
          final m = RegExp(r'213\s+(\d+)').firstMatch(r.text);
          if (m != null) return int.parse(m.group(1)!);
        }
        if (r.code == 550) return -1;
        // сервер не знает SIZE - ищем в списке родительской папки
        final dir = parent(path);
        final cw = await c.cmd('CWD ${dir.isEmpty ? '/' : dir}');
        if (cw.code >= 400) return -1;
        final raw = await _listRaw(c, 'LIST');
        final name = basename(path);
        for (final line in const LineSplitter().convert(raw ?? '')) {
          final e = _parseList(line, dir);
          if (e != null && e.name == name && !e.isDir) return e.size;
        }
        return -1;
      });

  @override
  Stream<List<int>> read(String path, int offset) async* {
    final c = await guard(_open);
    try {
      final ds = await c.dataSocket();
      try {
        if (offset > 0) {
          final r = await c.cmd('REST $offset');
          if (r.code != 350) throw FsError('FTP: сервер не поддерживает докачку');
        }
        final r = await c.cmd('RETR $path');
        if (r.code >= 400) throw FsError('FTP: не удалось скачать файл (${r.code})');
        await for (final chunk in ds) {
          yield chunk;
        }
        try {
          await c._read();
        } catch (_) {}
      } finally {
        ds.destroy();
      }
    } finally {
      c.close();
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false}) async {
    final c = await guard(_open);
    try {
      final ds = await c.dataSocket();
      try {
        final r = await c.cmd('${append ? 'APPE' : 'STOR'} $path');
        if (r.code >= 400) throw FsError('FTP: не удалось начать загрузку (${r.code})');
        await ds.addStream(data);
        await ds.flush();
        unawaited(ds.close().catchError((Object _) {}));
        final fin = await c._read();
        if (fin.code >= 400) throw FsError('FTP: загрузка не завершилась (${fin.code})', retry: true);
      } finally {
        ds.destroy();
      }
    } finally {
      c.close();
    }
  }
}

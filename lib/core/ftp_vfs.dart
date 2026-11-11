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

  String? _slot;

  static Future<_FtpConn> open(String host, int port, String user, String pass) async {
    final slot = 'ftp|$host';
    await HostSlots.acquire(slot);
    Socket s;
    try {
      s = await lanConnect(host, port, timeout: const Duration(seconds: 5));
    } catch (_) {
      HostSlots.release(slot);
      rethrow;
    }
    final c = _FtpConn._(s, host);
    c._slot = slot;
    try {
      var hello = await c._read();
      if (hello.code == 120) hello = await c._read(); // «сервер будет готов через N минут» - ждём настоящее приветствие
      if (hello.code >= 400) throw FsError('FTP: сервер отказал (${_short(hello.text)})', retry: true);
      var r = await c.cmd('USER $user');
      if (r.code == 331 || r.code == 332) r = await c.cmd('PASS $pass');
      if (r.code != 230 && r.code != 202) {
        throw FsError('FTP: неверный логин или пароль для «$user» (${_short(r.text)})');
      }
      // русские имена файлов: просим сервер работать в UTF-8 (если не умеет - не страшно)
      try {
        await c.cmd('OPTS UTF8 ON');
      } catch (_) {}
      await c.cmd('TYPE I');
      return c;
    } catch (e) {
      c.close();
      rethrow;
    }
  }

  static String _short(String t) {
    final one = t.replaceAll('\n', ' ').trim();
    return one.length > 90 ? '${one.substring(0, 90)}…' : one;
  }

  bool _noEpsv = false;

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

  /// Канал данных: сначала EPSV, если не вышло (роутеры часто с ним дружат хуже) - обычный PASV.
  Future<Socket> dataSocket() async {
    Object? lastErr;
    if (!_noEpsv) {
      try {
        final r = await cmd('EPSV');
        if (r.code == 229) {
          final m = RegExp(r'\|\|\|(\d+)\|').firstMatch(r.text);
          if (m != null) {
            // всегда подключаемся к адресу управляющего соединения (серверы за NAT врут в ответе)
            return await lanConnect(host, int.parse(m.group(1)!), timeout: const Duration(seconds: 6));
          }
        }
        _noEpsv = true;
      } catch (e) {
        lastErr = e;
        _noEpsv = true;
      }
    }
    final r = await cmd('PASV');
    if (r.code != 227) {
      throw FsError('FTP: сервер не поддерживает пассивный режим (${_short(r.text)})', retry: lastErr != null);
    }
    final m = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(r.text);
    if (m == null) throw FsError('FTP: странный ответ PASV (${_short(r.text)})');
    final port = int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
    try {
      return await lanConnect(host, port, timeout: const Duration(seconds: 6));
    } catch (e) {
      final ip = '${m.group(1)}.${m.group(2)}.${m.group(3)}.${m.group(4)}';
      if (ip != host && !ip.startsWith('0.')) {
        // некоторые серверы называют правильный адрес только здесь
        return await lanConnect(ip, port, timeout: const Duration(seconds: 6));
      }
      throw FsError('FTP: не удалось открыть канал данных (порт $port). Проверьте настройки FTP на роутере.', retry: true);
    }
  }

  void close() {
    try {
      sock.write('QUIT\r\n');
    } catch (_) {}
    try {
      sock.destroy();
    } catch (_) {}
    final k = _slot;
    _slot = null;
    if (k != null) HostSlots.release(k);
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
      if (cw.code >= 400) throw FsError('FTP: нет такой папки или нет доступа (${_FtpConn._short(cw.text)})');
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

/// Пошаговая проверка FTP для экрана «Диагностика»: что именно отвечает сервер на каждом шаге.
Future<List<String>> ftpDiagnose(Device d) async {
  final out = <String>[];
  final host = d.host ?? '';
  final port = d.portOf('ftp', 21);
  final u = d.str('ftp', 'user');
  final user = (u == null || u.isEmpty) ? 'anonymous' : u;
  final pass = d.str('ftp', 'pass') ?? 'nanolink@local';
  out.add('FTP  $host:$port, логин «$user»');
  _FtpConn? c;
  try {
    final s = await lanConnect(host, port, timeout: const Duration(seconds: 5));
    c = _FtpConn._(s, host);
    out.add('✓ соединение открыто');
    var r = await c._read();
    out.add('приветствие: ${_FtpConn._short(r.text)}');
    r = await c.cmd('USER $user');
    out.add('USER → ${_FtpConn._short(r.text)}');
    if (r.code == 331 || r.code == 332) {
      r = await c.cmd('PASS $pass');
      out.add('PASS •••• → ${_FtpConn._short(r.text)}');
    }
    if (r.code != 230 && r.code != 202) {
      out.add('✗ вход не удался: сервер не принял логин/пароль');
      return out;
    }
    out.add('✓ вход выполнен');
    final t = await c.cmd('TYPE I');
    out.add('TYPE I → ${_FtpConn._short(t.text)}');
    try {
      final ds = await c.dataSocket();
      out.add('✓ канал данных открыт (${c._noEpsv ? 'PASV' : 'EPSV'})');
      final l = await c.cmd('LIST');
      if (l.code >= 400) {
        out.add('✗ LIST → ${_FtpConn._short(l.text)}');
      } else {
        final text = await const Utf8Codec(allowMalformed: true).decodeStream(ds).timeout(const Duration(seconds: 10));
        try {
          await c._read();
        } catch (_) {}
        final lines = const LineSplitter().convert(text).where((x) => x.trim().isNotEmpty).toList();
        out.add('✓ список получен: ${lines.length} строк');
        for (final x in lines.take(4)) {
          out.add('   $x');
        }
      }
      ds.destroy();
    } catch (e) {
      out.add('✗ канал данных: $e');
    }
  } catch (e) {
    out.add('✗ ${e.runtimeType}: $e');
  } finally {
    c?.close();
  }
  return out;
}

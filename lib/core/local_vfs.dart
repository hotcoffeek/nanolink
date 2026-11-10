import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'util.dart';
import 'vfs.dart';

/// Пути «на проводе» всегда в стиле '/': Windows-диск выглядит как '/C:/Users/...'.
String wireToLocal(String w) {
  if (Platform.isWindows) {
    var s = w.replaceAll('\\', '/');
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    if (s.isEmpty) return '';
    if (RegExp(r'^[A-Za-z]:$').hasMatch(s)) return '$s\\';
    return s.replaceAll('/', '\\');
  }
  if (Platform.isAndroid) {
    if (w == '/' || w.isEmpty) return '';
    return w;
  }
  return w.isEmpty ? '/' : w;
}

String localToWire(String l) {
  if (Platform.isWindows) {
    var s = l.replaceAll('\\', '/');
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return '/';
    if (!s.startsWith('/')) s = '/$s';
    return s;
  }
  return l.isEmpty ? '/' : l;
}

class LocalVfs extends Vfs {
  static List<String> androidRoots = ['/storage/emulated/0'];
  static String deviceTitle = 'Это устройство';

  @override
  String get sep => Platform.isWindows ? '\\' : '/';

  @override
  String get title => deviceTitle;

  String get _home {
    final env = Platform.environment;
    if (Platform.isWindows) return env['USERPROFILE'] ?? '';
    if (Platform.isAndroid) return androidRoots.isNotEmpty ? androidRoots.first : '/storage/emulated/0';
    return env['HOME'] ?? '/';
  }

  @override
  Future<String> start() async {
    final h = _home;
    if (h.isNotEmpty && Directory(h).existsSync()) return h;
    return '';
  }

  @override
  Future<List<Place>> places() async {
    final out = <Place>[];
    void add(String name, String path, String icon) {
      try {
        if (Directory(path).existsSync()) out.add(Place(name, path, icon));
      } catch (_) {}
    }

    if (Platform.isWindows) {
      final h = _home;
      final od = Platform.environment['OneDrive'];
      String pick(String n) {
        final p = '$h\\$n';
        if (Directory(p).existsSync()) return p;
        if (od != null && Directory('$od\\$n').existsSync()) return '$od\\$n';
        return p;
      }

      add('Рабочий стол', pick('Desktop'), 'desktop');
      add('Загрузки', '$h\\Downloads', 'downloads');
      add('Документы', pick('Documents'), 'documents');
      add('Изображения', pick('Pictures'), 'pictures');
      add('Видео', '$h\\Videos', 'videos');
      add('Музыка', '$h\\Music', 'music');
    } else if (Platform.isAndroid) {
      final r = _home;
      add('Камера', '$r/DCIM', 'pictures');
      add('Загрузки', '$r/Download', 'downloads');
      add('Документы', '$r/Documents', 'documents');
      add('Картинки', '$r/Pictures', 'pictures');
      add('Видео', '$r/Movies', 'videos');
      add('Музыка', '$r/Music', 'music');
    } else {
      final h = _home;
      add('Рабочий стол', '$h/Desktop', 'desktop');
      add('Загрузки', '$h/Downloads', 'downloads');
      add('Документы', '$h/Documents', 'documents');
      add('Изображения', '$h/Pictures', 'pictures');
      add('Видео', '$h/Videos', 'videos');
      add('Музыка', '$h/Music', 'music');
    }
    return out;
  }

  @override
  String parent(String p) {
    if (Platform.isWindows) {
      if (p.isEmpty) return '';
      var q = p;
      while (q.length > 3 && q.endsWith('\\')) {
        q = q.substring(0, q.length - 1);
      }
      if (RegExp(r'^[A-Za-z]:\\?$').hasMatch(q)) return '';
      final i = q.lastIndexOf('\\');
      if (i < 0) return '';
      final r = q.substring(0, i);
      return r.length == 2 ? '$r\\' : r;
    }
    if (Platform.isAndroid && androidRoots.contains(p)) return '';
    return super.parent(p);
  }

  @override
  Future<List<FsEntry>> list(String path) async {
    final out = <FsEntry>[];
    if (path.isEmpty) {
      if (Platform.isWindows) {
        for (var c = 67; c <= 90; c++) {
          final l = String.fromCharCode(c);
          final p = '$l:\\';
          try {
            if (Directory(p).existsSync()) out.add(FsEntry(name: '$l:', path: p, isDir: true));
          } catch (_) {}
        }
        return out;
      }
      if (Platform.isAndroid) {
        for (final r in androidRoots) {
          final nm = r == '/storage/emulated/0' ? 'Память телефона' : basename(r);
          out.add(FsEntry(name: nm, path: r, isDir: true));
        }
        return out;
      }
      path = '/';
    }
    try {
      await for (final e in Directory(path).list(followLinks: false)) {
        try {
          final name = basename(e.path);
          if (e is Directory) {
            out.add(FsEntry(name: name, path: e.path, isDir: true, modified: e.statSync().modified));
          } else if (e is File) {
            final st = e.statSync();
            out.add(FsEntry(name: name, path: e.path, isDir: false, size: st.size, modified: st.modified));
          }
        } catch (_) {}
      }
    } on FileSystemException catch (e) {
      throw FsError('Нет доступа: ${e.osError?.message ?? e.message}');
    }
    return out;
  }

  @override
  Future<void> mkdir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> rename(String from, String to) async {
    try {
      if (await FileSystemEntity.isDirectory(from)) {
        await Directory(from).rename(to);
      } else {
        await File(from).rename(to);
      }
    } on FileSystemException catch (e) {
      // между разными дисками rename не работает - копируем и удаляем
      if (await FileSystemEntity.isDirectory(from)) {
        throw FsError('Не удалось переименовать: ${e.message}');
      }
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  @override
  Future<void> delete(String path) async {
    final t = await FileSystemEntity.type(path, followLinks: false);
    if (t == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (t != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  @override
  Future<int> fileSize(String path) async {
    final f = File(path);
    if (await f.exists()) return await f.length();
    return -1;
  }

  @override
  Stream<List<int>> read(String path, int offset) async* {
    final f = await File(path).open();
    try {
      if (offset > 0) await f.setPosition(offset);
      while (true) {
        final Uint8List b = await f.read(1 << 20);
        if (b.isEmpty) break;
        yield b;
      }
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false}) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final raf = await f.open(mode: append ? FileMode.append : FileMode.write);
    try {
      await for (final c in data) {
        await raf.writeFrom(c);
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
  }
}

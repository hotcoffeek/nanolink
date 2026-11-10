import 'dart:io';

import 'local_vfs.dart';
import 'models.dart';
import 'vfs.dart';

enum Cat { photos, videos, audio, docs }

const Map<Cat, Set<String>> catExt = {
  Cat.photos: {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'dng'},
  Cat.videos: {'mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'm4v', 'ts', 'wmv'},
  Cat.audio: {'mp3', 'flac', 'wav', 'm4a', 'ogg', 'aac', 'opus', 'wma', 'amr'},
  Cat.docs: {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'csv', 'epub', 'fb2', 'djvu'},
};

class Album {
  final String path;
  final String name;
  int count = 0;
  String? cover;
  Album(this.path, this.name);
}

Future<List<String>> _scanRoots() async {
  final out = <String>[];
  if (Platform.isAndroid) return List<String>.from(LocalVfs.androidRoots);
  final env = Platform.environment;
  final home = Platform.isWindows ? (env['USERPROFILE'] ?? '') : (env['HOME'] ?? '');
  if (home.isEmpty) return out;
  final sep = Platform.pathSeparator;
  final names = ['Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music'];
  final bases = <String>[home];
  final od = env['OneDrive'];
  if (od != null && od.isNotEmpty) bases.add(od);
  for (final b in bases) {
    for (final n in names) {
      final p = '$b$sep$n';
      try {
        if (Directory(p).existsSync() && !out.contains(p)) out.add(p);
      } catch (_) {}
    }
  }
  return out;
}

/// Находит папки («альбомы»), где лежат файлы нужной категории.
Future<List<Album>> scanCategory(Cat c, {void Function(int found)? onProgress}) async {
  final exts = catExt[c]!;
  final albums = <String, Album>{};
  final stack = <String>[...await _scanRoots()];
  final sep = Platform.pathSeparator;
  var n = 0;
  var found = 0;
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    try {
      await for (final e in Directory(dir).list(followLinks: false)) {
        final name = e.path.substring(e.path.lastIndexOf(sep) + 1);
        if (e is Directory) {
          if (name.startsWith('.') || name == 'Android' || name == 'node_modules' || name == 'AppData') continue;
          stack.add(e.path);
        } else if (e is File) {
          final dot = name.lastIndexOf('.');
          if (dot <= 0) continue;
          final ext = name.substring(dot + 1).toLowerCase();
          if (exts.contains(ext)) {
            final a = albums.putIfAbsent(dir, () => Album(dir, dir.substring(dir.lastIndexOf(sep) + 1)));
            a.count++;
            a.cover ??= e.path;
            found++;
          }
        }
      }
    } catch (_) {}
    if (++n % 15 == 0) {
      onProgress?.call(found);
      await Future<void>.delayed(Duration.zero);
    }
  }
  final list = albums.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  return list;
}

FsEntry? entryOfPath(String path) {
  try {
    final f = File(path);
    final sep = Platform.pathSeparator;
    final st = f.statSync();
    return FsEntry(name: path.substring(path.lastIndexOf(sep) + 1), path: path, isDir: false, size: st.size, modified: st.modified);
  } catch (_) {
    return null;
  }
}

const Map<Cat, Set<String>> _hiNames = {
  Cat.photos: {'dcim', 'pictures', 'camera', 'screenshots', 'whatsapp images', 'images', 'photos', 'фото', 'изображения'},
  Cat.videos: {'dcim', 'movies', 'videos', 'camera', 'video', 'whatsapp video', 'видео', 'фильмы'},
  Cat.audio: {'music', 'download', 'downloads', 'podcasts', 'audio', 'recordings', 'музыка'},
  Cat.docs: {'documents', 'download', 'downloads', 'books', 'документы', 'загрузки'},
};

const Set<String> _skipNames = {
  'android', 'node_modules', 'appdata', 'windows', 'program files', 'program files (x86)', 'programdata',
  r'$recycle.bin', 'system volume information', 'proc', 'sys', 'dev', 'usr', 'lib', 'etc', 'var', 'bin', 'sbin', 'run', 'boot', 'snap',
};

/// Быстрый поиск по удалённому устройству: сначала «говорящие» папки (DCIM, Pictures, Music...), потом верх дерева.
/// Результаты отдаются по мере нахождения, поиск останавливается через [cancelled].
Future<List<Album>> scanCategoryRemote(
  Vfs v,
  Cat c,
  List<String> starts, {
  required void Function(int found, List<Album> albums) onProgress,
  required bool Function() cancelled,
}) async {
  final exts = catExt[c]!;
  final hi = _hiNames[c]!;
  final hiQ = <List<dynamic>>[]; // [path, depth]
  final loQ = <List<dynamic>>[];
  final seen = <String>{};
  for (final s in starts) {
    if (seen.add(s)) loQ.add([s, 0]);
  }
  final albums = <String, Album>{};
  var found = 0;
  var calls = 0;
  var active = 0;
  var lastEmit = DateTime.now();

  void emit({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(lastEmit).inMilliseconds < 350) return;
    lastEmit = now;
    final l = albums.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    onProgress(found, l);
  }

  Future<void> worker() async {
    while (!cancelled()) {
      List<dynamic>? job;
      if (hiQ.isNotEmpty) {
        job = hiQ.removeLast();
      } else if (loQ.isNotEmpty) {
        job = loQ.removeAt(0);
      } else if (active == 0) {
        return;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        continue;
      }
      if (calls++ > 600) return;
      active++;
      final dir = job[0] as String;
      final depth = job[1] as int;
      final inHi = job.length > 2;
      try {
        final items = await v.list(dir);
        for (final e in items) {
          if (e.isDir) {
            final n = e.name.toLowerCase();
            if (n.startsWith('.') || _skipNames.contains(n)) continue;
            if (!seen.add(e.path)) continue;
            final isHi = hi.contains(n);
            if (isHi || inHi) {
              if (depth < 6) hiQ.add([e.path, depth + 1, 1]);
            } else if (depth < 2) {
              loQ.add([e.path, depth + 1]);
            }
          } else if (exts.contains(e.ext)) {
            final a = albums.putIfAbsent(dir, () => Album(dir, v.basename(dir).isEmpty ? dir : v.basename(dir)));
            a.count++;
            found++;
          }
        }
        emit();
      } catch (_) {
      } finally {
        active--;
      }
    }
  }

  await Future.wait(List.generate(4, (_) => worker()));
  emit(force: true);
  final l = albums.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  return l;
}

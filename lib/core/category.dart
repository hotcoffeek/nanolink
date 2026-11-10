import 'dart:io';

import 'local_vfs.dart';
import 'models.dart';

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

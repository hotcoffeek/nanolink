import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'vfs.dart';

/// Эскизы для удалённых картинок: качаем небольшие файлы во временную папку (не больше 3 одновременно).
class RemoteThumbs {
  static final Map<String, Future<File?>> _cache = {};
  static int _busy = 0;
  static final List<Completer<void>> _wait = [];

  static Future<void> _acquire() async {
    if (_busy < 3) {
      _busy++;
      return;
    }
    final c = Completer<void>();
    _wait.add(c);
    await c.future;
  }

  static void _release() {
    if (_wait.isNotEmpty) {
      _wait.removeAt(0).complete();
    } else {
      _busy--;
    }
  }

  static Future<File?> get(Vfs v, FsEntry e, String key) {
    return _cache.putIfAbsent('$key|${e.path}|${e.size}', () => _load(v, e, key));
  }

  static Future<File?> _load(Vfs v, FsEntry e, String key) async {
    await _acquire();
    try {
      final tmp = (await getTemporaryDirectory()).path;
      final dir = Directory('$tmp/nl_thumbs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final name = '${(key + e.path).hashCode.toUnsigned(31)}_${e.size}.${e.ext}';
      final f = File('${dir.path}/$name');
      if (f.existsSync() && f.lengthSync() == e.size) return f;
      final sink = f.openWrite();
      try {
        await for (final chunk in v.read(e.path, 0)) {
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return f;
    } catch (_) {
      return null;
    } finally {
      _release();
    }
  }
}

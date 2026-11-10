import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hub.dart';
import 'models.dart';
import 'util.dart';
import 'vfs.dart';

enum TState { queued, running, waiting, paused, done, failed, canceled }

class _Pause implements Exception {}

class _Cancel implements Exception {}

class _Item {
  final String srcPath;
  final String relPath;
  final int size;
  _Item(this.srcPath, this.relPath, this.size);
}

class TransferJob {
  final int id;
  final FsEntry entry;
  final String dstDir;
  final bool move;
  final Vfs Function() srcFactory;
  final Vfs Function() dstFactory;
  final Device? srcDev;
  final Device? dstDev;
  final String conflict; // rename | overwrite | skip

  TState state = TState.queued;
  int total = 0;
  int done = 0;
  int _base = 0;
  double speed = 0;
  int _lastDone = 0;
  String? error;
  String? note;
  String? targetName;
  bool _cancel = false;
  bool _pause = false;
  Completer<void>? _resume;
  int retries = 0;

  TransferJob({
    required this.id,
    required this.entry,
    required this.dstDir,
    required this.move,
    required this.srcFactory,
    required this.dstFactory,
    required this.srcDev,
    required this.dstDev,
    required this.conflict,
  });

  double get progress => total <= 0 ? (state == TState.done ? 1 : 0) : (done / total).clamp(0.0, 1.0);
  bool get active => state == TState.running || state == TState.waiting;
  bool get finished => state == TState.done || state == TState.failed || state == TState.canceled;
}

/// Очередь передач. Главное: не падать при обрыве сети - ждать, искать устройство и докачивать с того же места.
class TransferEngine extends ChangeNotifier {
  final Hub hub;
  TransferEngine(this.hub);

  final List<TransferJob> jobs = [];
  int _seq = 0;
  int maxParallel = 2;
  Timer? _ticker;

  void enqueue({
    required Vfs Function() srcFactory,
    required Vfs Function() dstFactory,
    required Device? srcDev,
    required Device? dstDev,
    required List<FsEntry> items,
    required String dstDir,
    required bool move,
    String conflict = 'rename',
  }) {
    for (final it in items) {
      jobs.add(TransferJob(
        id: ++_seq,
        entry: it,
        dstDir: dstDir,
        move: move,
        srcFactory: srcFactory,
        dstFactory: dstFactory,
        srcDev: srcDev,
        dstDev: dstDev,
        conflict: conflict,
      ));
    }
    _startTicker();
    _pump();
    notifyListeners();
  }

  int get activeCount => jobs.where((j) => j.active || j.state == TState.queued).length;

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      var any = false;
      for (final j in jobs) {
        if (j.active) {
          any = true;
          final d = j.done - j._lastDone;
          j._lastDone = j.done;
          j.speed = j.speed * 0.5 + (d * 2.0) * 0.5;
        } else {
          j.speed = 0;
        }
      }
      notifyListeners();
      if (!any && jobs.every((j) => !j.active && j.state != TState.queued)) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  void _pump() {
    var running = jobs.where((j) => j.active).length;
    for (final j in jobs) {
      if (running >= maxParallel) break;
      if (j.state == TState.queued) {
        running++;
        unawaited(_run(j));
      }
    }
  }

  void pause(TransferJob j) {
    if (!j.active) return;
    j._pause = true;
    notifyListeners();
  }

  void resume(TransferJob j) {
    if (j.state == TState.paused) {
      j._pause = false;
      j._resume?.complete();
      j._resume = null;
      j.state = TState.running;
      _startTicker();
      notifyListeners();
    } else if (j.state == TState.failed || j.state == TState.canceled) {
      j._cancel = false;
      j._pause = false;
      j.error = null;
      j.state = TState.queued;
      _startTicker();
      _pump();
      notifyListeners();
    }
  }

  void cancel(TransferJob j) {
    j._cancel = true;
    j._pause = false;
    j._resume?.complete();
    j._resume = null;
    if (j.state == TState.queued || j.state == TState.paused) j.state = TState.canceled;
    notifyListeners();
  }

  void clearFinished() {
    jobs.removeWhere((j) => j.finished);
    notifyListeners();
  }

  // ------------------------------------------------------------------

  Future<void> _run(TransferJob j) async {
    j.state = TState.running;
    j.error = null;
    notifyListeners();
    final src = j.srcFactory();
    final dst = j.dstFactory();
    try {
      await _prepare(j, src, dst);
      if (j.state == TState.done) return;
      await _execute(j, src, dst);
      if (j._cancel) throw _Cancel();
      if (j.move) {
        j.note = 'Удаляем исходник';
        notifyListeners();
        try {
          await src.delete(j.entry.path);
        } catch (_) {}
      }
      j.state = TState.done;
      j.done = j.total;
      j.note = null;
    } on _Cancel {
      j.state = TState.canceled;
    } catch (e) {
      j.state = TState.failed;
      j.error = e is FsError ? e.message : 'Ошибка: $e';
    } finally {
      try {
        await src.close();
      } catch (_) {}
      try {
        await dst.close();
      } catch (_) {}
      notifyListeners();
      _pump();
    }
  }

  final Map<int, List<_Item>> _plans = {};
  final Map<int, String> _dstTop = {};
  final Map<int, List<String>> _dstDirs = {};

  Future<void> _prepare(TransferJob j, Vfs src, Vfs dst) async {
    // Имя назначения (без конфликтов)
    var name = j.entry.name;
    final top0 = dst.join(j.dstDir, name);
    if (!j.entry.isDir) {
      final exists = await _retry(j, () => dst.fileSize(top0)) >= 0;
      if (exists) {
        if (j.conflict == 'skip') {
          j.state = TState.done;
          j.note = 'Пропущен (уже есть)';
          return;
        }
        if (j.conflict == 'rename') {
          // но если это недокачанный наш файл - продолжим его
          final part = await _retry(j, () => dst.fileSize('$top0.nlpart'));
          if (part < 0) {
            name = await _unique(j, dst, j.dstDir, name);
          }
        }
      }
    }
    final top = dst.join(j.dstDir, name);
    j.targetName = name;
    _dstTop[j.id] = top;

    final items = <_Item>[];
    final dirs = <String>[];
    if (j.entry.isDir) {
      dirs.add('');
      await _walk(j, src, j.entry.path, '', items, dirs);
    } else {
      items.add(_Item(j.entry.path, '', j.entry.size));
    }
    _plans[j.id] = items;
    _dstDirs[j.id] = dirs;
    j.total = items.fold<int>(0, (a, b) => a + b.size);
  }

  Future<void> _walk(TransferJob j, Vfs src, String dir, String rel, List<_Item> items, List<String> dirs) async {
    _check(j);
    final l = await _retry(j, () => src.list(dir));
    for (final e in l) {
      final r = rel.isEmpty ? e.name : '$rel/${e.name}';
      if (e.isDir) {
        dirs.add(r);
        await _walk(j, src, e.path, r, items, dirs);
      } else {
        items.add(_Item(e.path, r, e.size));
      }
    }
  }

  Future<String> _unique(TransferJob j, Vfs dst, String dir, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 500; i++) {
      final cand = '$stem ($i)$ext';
      if (await _retry(j, () => dst.fileSize(dst.join(dir, cand))) < 0) return cand;
    }
    return '$stem (${DateTime.now().millisecondsSinceEpoch})$ext';
  }

  Future<void> _execute(TransferJob j, Vfs src, Vfs dst) async {
    final top = _dstTop[j.id]!;
    final items = _plans[j.id]!;
    j.done = 0;
    j._base = 0;
    if (j.entry.isDir) {
      for (final d in _dstDirs[j.id]!) {
        final p = d.isEmpty ? top : _joinRel(dst, top, d);
        await _retry(j, () => dst.mkdir(p));
      }
    }
    for (final it in items) {
      _check(j);
      final dstPath = it.relPath.isEmpty ? top : _joinRel(dst, top, it.relPath);
      if (j.conflict == 'skip' && j.entry.isDir) {
        if (await _retry(j, () => dst.fileSize(dstPath)) == it.size && it.size > 0) {
          j._base += it.size;
          j.done = j._base;
          continue;
        }
      }
      await _copyFile(j, src, dst, it.srcPath, dstPath, it.size);
      j._base += it.size;
      j.done = j._base;
    }
  }

  String _joinRel(Vfs dst, String top, String rel) {
    var p = top;
    for (final seg in rel.split('/')) {
      p = dst.join(p, seg);
    }
    return p;
  }

  void _check(TransferJob j) {
    if (j._cancel) throw _Cancel();
  }

  Future<T> _retry<T>(TransferJob j, Future<T> Function() op) async {
    var n = 0;
    while (true) {
      _check(j);
      try {
        return await op();
      } catch (e) {
        if (e is _Cancel || isFatal(e) || ++n > 6) rethrow;
        await _recover(j, 'Нет связи, пробуем снова…', n);
      }
    }
  }

  Future<void> _recover(TransferJob j, String msg, int attempt) async {
    j.state = TState.waiting;
    j.note = msg;
    j.retries++;
    notifyListeners();
    final tasks = <Future<void>>[];
    final src = j.srcDev;
    final dst = j.dstDev;
    if (src != null) tasks.add(hub.heal(src).catchError((Object _) {}));
    if (dst != null && dst != src) tasks.add(hub.heal(dst).catchError((Object _) {}));
    if (tasks.isNotEmpty) await Future.wait(tasks);
    await delay((attempt * 1500).clamp(1000, 8000));
    if (!j._cancel) {
      j.state = TState.running;
      j.note = null;
      notifyListeners();
    }
  }

  Future<void> _copyFile(TransferJob j, Vfs src, Vfs dst, String srcPath, String dstPath, int size) async {
    final part = '$dstPath.nlpart';
    var attempt = 0;
    while (true) {
      _check(j);
      if (j._pause) await _waitResume(j);
      _check(j);
      try {
        var have = await dst.fileSize(part);
        if (have > size) {
          await dst.delete(part);
          have = 0;
        }
        if (have < 0) have = 0;
        j.done = j._base + have;
        if (have < size || size == 0) {
          final stream = _counting(j, src.read(srcPath, have), have);
          await dst.write(part, stream, len: size - have, append: have > 0);
        }
        final got = await dst.fileSize(part);
        if (got != size) {
          throw FsError('Размер не совпал ($got из $size)', retry: true);
        }
        if (await dst.fileSize(dstPath) >= 0) await dst.delete(dstPath);
        await dst.rename(part, dstPath);
        return;
      } on _Pause {
        j.state = TState.paused;
        j.note = null;
        notifyListeners();
        await _waitResume(j);
        _check(j);
        j.state = TState.running;
        notifyListeners();
      } catch (e) {
        if (e is _Cancel || j._cancel) throw _Cancel();
        if (isFatal(e)) rethrow;
        attempt++;
        if (attempt > 400) rethrow;
        await _recover(j, 'Связь потеряна. Ищем устройство и докачаем…', attempt > 6 ? 6 : attempt);
      }
    }
  }

  Future<void> _waitResume(TransferJob j) async {
    if (!j._pause) return;
    j.state = TState.paused;
    notifyListeners();
    j._resume = Completer<void>();
    await j._resume!.future;
  }

  Stream<List<int>> _counting(TransferJob j, Stream<List<int>> s, int start) async* {
    var n = start;
    await for (final c in s) {
      n += c.length;
      j.done = j._base + n;
      yield c;
      if (j._cancel) throw _Cancel();
      if (j._pause) throw _Pause();
    }
  }
}

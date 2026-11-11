import 'dart:async';

import 'hub.dart';
import 'models.dart';
import 'util.dart';

/// Единый интерфейс «файловой системы»: локальная, другой NanoLink, FTP, SFTP, SMB.
abstract class Vfs {
  String get sep => '/';
  String get title;
  Device? get device => null;
  bool get remote => false;

  /// Стартовая папка (может быть асинхронной, например домашняя папка по SFTP).
  Future<String> start() async => '/';

  Future<List<Place>> places() async => const [];

  Future<List<FsEntry>> list(String path);
  Future<void> mkdir(String path);
  Future<void> rename(String from, String to);
  Future<void> delete(String path);

  /// Размер файла или -1, если файла нет.
  Future<int> fileSize(String path);

  Stream<List<int>> read(String path, int offset);

  /// Записать поток [data] длиной [len]. При append == true дописывает в конец существующего файла.
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false});

  Future<void> close() async {}

  String join(String dir, String name) {
    if (dir.isEmpty) return name;
    return dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';
  }

  String parent(String path) {
    if (path.isEmpty || path == '/') return path.isEmpty ? '' : '/';
    var q = path;
    while (q.length > 1 && q.endsWith('/')) {
      q = q.substring(0, q.length - 1);
    }
    final i = q.lastIndexOf('/');
    if (i <= 0) return '/';
    return q.substring(0, i);
  }

  String basename(String path) {
    var q = path;
    while (q.length > 1 && q.endsWith(sep)) {
      q = q.substring(0, q.length - 1);
    }
    final i = q.lastIndexOf(sep);
    if (i < 0) return q;
    return q.substring(i + 1);
  }
}

/// База для сетевых ФС: повтор операций с «самолечением» при обрыве.
/// Ограничитель подключений к одному хосту. У роутеров и NAS обычно «не больше 5 одновременных подключений»;
/// если занять все места, остальные устройства (и ПК-версия) перестают подключаться. Лишние ждут очереди.
class HostSlots {
  static final Map<String, int> _used = {};
  static final Map<String, List<Completer<void>>> _wait = {};

  static Future<void> acquire(String key, {int max = 3, Duration timeout = const Duration(seconds: 30)}) async {
    if ((_used[key] ?? 0) < max) {
      _used[key] = (_used[key] ?? 0) + 1;
      return;
    }
    final c = Completer<void>();
    _wait.putIfAbsent(key, () => <Completer<void>>[]).add(c);
    try {
      await c.future.timeout(timeout);
    } on TimeoutException {
      // Долго ждали: либо идут большие передачи, либо где-то «потерялось» закрытие соединения.
      // Чтобы не блокироваться навсегда, берём место сверх лимита.
      _wait[key]?.remove(c);
      _used[key] = (_used[key] ?? 0) + 1;
    }
  }

  static void release(String key) {
    final q = _wait[key];
    if (q != null && q.isNotEmpty) {
      // место передаём первому в очереди, счётчик не меняется
      q.removeAt(0).complete();
      return;
    }
    final n = (_used[key] ?? 1) - 1;
    if (n <= 0) {
      _used.remove(key);
    } else {
      _used[key] = n;
    }
  }
}

abstract class RemoteVfs extends Vfs {
  final Device dev;
  final Hub hub;
  RemoteVfs(this.dev, this.hub);

  @override
  Device? get device => dev;

  @override
  bool get remote => true;

  /// Сбросить текущее соединение (следующая операция откроет новое).
  void resetConn();

  String get hostOrThrow {
    final h = dev.host;
    if (h == null || h.isEmpty) throw FsError('Адрес устройства неизвестен', retry: true);
    return h;
  }

  Future<T> guard<T>(Future<T> Function() op, {int tries = 3}) async {
    var attempt = 0;
    while (true) {
      try {
        return await op();
      } catch (e) {
        if (isFatal(e) || ++attempt >= tries) rethrow;
        resetConn();
        try {
          await hub.heal(dev).timeout(const Duration(seconds: 8));
        } catch (_) {}
        await delay(300 * attempt);
      }
    }
  }
}

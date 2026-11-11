import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'hub.dart';
import 'models.dart';
import 'smb_vfs.dart';
import 'util.dart';
import 'vfs.dart';

const MethodChannel _smbCh = MethodChannel('nanolink/smb');

Map<String, dynamic> _smbArgs(Device d, String domain) {
  final u = d.str('smb', 'user');
  return {
    'host': d.host ?? '',
    'port': d.portOf('smb', 445),
    'domain': domain,
    'user': (u == null || u.isEmpty) ? 'guest' : u,
    'pass': d.str('smb', 'pass') ?? '',
  };
}

/// SMB на Android через нативную библиотеку jcifs-ng (SMB1 + SMB2/3).
/// Нужна для роутеров и NAS, на которых Dart-клиент зависает при входе.
class NativeSmbVfs extends SmbVfs {
  NativeSmbVfs(Device dev, Hub hub) : super(dev, hub);

  String _domain = '';

  Future<T?> _call<T>(String m, [Map<String, dynamic>? extra, int seconds = 45]) async {
    hostOrThrow;
    final args = _smbArgs(dev, _domain);
    if (extra != null) args.addAll(extra);
    try {
      return await _smbCh.invokeMethod<T>(m, args).timeout(Duration(seconds: seconds));
    } on PlatformException catch (e) {
      if (e.code == 'auth') throw FsError('SMB: неверный логин или пароль');
      final msg = e.message ?? '';
      final low = msg.toLowerCase();
      if (low.contains('access is denied') || low.contains('access denied')) throw FsError('SMB: нет доступа к этой папке');
      if (low.contains('cannot find') || low.contains('not found') || low.contains('does not exist')) {
        throw FsError('SMB: не найдено');
      }
      throw Exception('SMB: $msg');
    } on MissingPluginException {
      throw FsError('SMB: нативный модуль недоступен в этой сборке');
    }
  }

  @override
  void resetConn() {
    final h = dev.host;
    if (h == null || h.isEmpty) return;
    unawaited(_smbCh.invokeMethod<bool>('reset', _smbArgs(dev, _domain)).then<void>((_) {}).catchError((Object _) {}));
  }

  @override
  Future<String> start() async => '/';

  @override
  Future<List<FsEntry>> list(String path) => guard(() async {
        final root = path.isEmpty || path == '/';
        List<dynamic>? raw;
        try {
          raw = await _call<List<dynamic>>('list', {'path': root ? '/' : path});
        } on FsError catch (e) {
          // учётка роутера/NAS иногда привязана к рабочей группе - пробуем WORKGROUP
          if (root && _domain.isEmpty && e.message.contains('логин')) {
            _domain = 'WORKGROUP';
            try {
              raw = await _call<List<dynamic>>('list', {'path': '/'});
            } catch (_) {
              _domain = '';
              throw e;
            }
          } else {
            rethrow;
          }
        }
        final out = <FsEntry>[];
        for (final x in raw ?? const <dynamic>[]) {
          final m = x as Map<dynamic, dynamic>;
          final n = (m['name'] ?? '').toString();
          if (n.isEmpty) continue;
          final isDir = m['dir'] == true;
          final mt = (m['mtime'] as num?)?.toInt() ?? 0;
          out.add(FsEntry(
            name: n,
            path: root ? '/$n' : join(path, n),
            isDir: isDir,
            size: isDir ? 0 : ((m['size'] as num?)?.toInt() ?? 0),
            modified: mt > 0 ? DateTime.fromMillisecondsSinceEpoch(mt) : null,
          ));
        }
        return out;
      });

  @override
  Future<void> mkdir(String path) => guard(() async {
        await _call<bool>('mkdir', {'path': path});
      });

  @override
  Future<void> rename(String from, String to) => guard(() async {
        await _call<bool>('rename', {'path': from, 'to': to});
      });

  @override
  Future<void> delete(String path) => guard(() async {
        await _call<bool>('delete', {'path': path}, 600);
      });

  @override
  Future<int> fileSize(String path) => guard(() async {
        final r = await _call<int>('size', {'path': path});
        return r ?? -1;
      });

  @override
  Stream<List<int>> read(String path, int offset) async* {
    final id = await guard(() => _call<int>('open', {'path': path, 'write': false, 'offset': offset}));
    if (id == null) throw FsError('SMB: не удалось открыть файл');
    try {
      while (true) {
        final chunk = await _call<Uint8List>('read', {'id': id, 'n': 524288});
        if (chunk == null || chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      unawaited(_smbCh.invokeMethod<bool>('close', {'id': id}).then<void>((_) {}).catchError((Object _) {}));
    }
  }

  @override
  Future<void> write(String path, Stream<List<int>> data, {required int len, bool append = false}) async {
    final id = await guard(() => _call<int>('open', {'path': path, 'write': true, 'append': append, 'offset': 0}));
    if (id == null) throw FsError('SMB: не удалось создать файл');
    try {
      var buf = BytesBuilder(copy: false);
      await for (final part in data) {
        buf.add(part is Uint8List ? part : Uint8List.fromList(part));
        if (buf.length >= 524288) {
          await _call<bool>('write', {'id': id, 'data': buf.takeBytes()});
          buf = BytesBuilder(copy: false);
        }
      }
      if (buf.length > 0) {
        await _call<bool>('write', {'id': id, 'data': buf.takeBytes()});
      }
    } finally {
      try {
        await _smbCh.invokeMethod<bool>('close', {'id': id}).timeout(const Duration(seconds: 30));
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async => resetConn();
}

/// Проверка входа через нативную библиотеку (для экрана «Диагностика»).
Future<List<String>> nativeSmbDiagnose(Device d) async {
  final out = <String>[];
  out.add('SMB через встроенную библиотеку jcifs (как в файловых менеджерах):');
  for (final domain in const ['', 'WORKGROUP']) {
    final args = _smbArgs(d, domain);
    args['path'] = '/';
    try {
      final raw = await _smbCh.invokeMethod<List<dynamic>>('list', args).timeout(const Duration(seconds: 40));
      final names = (raw ?? const <dynamic>[]).map((x) => (x as Map<dynamic, dynamic>)['name'].toString()).join(', ');
      out.add('✓ вход выполнен, общие ресурсы: $names');
      return out;
    } catch (e) {
      var t = e is PlatformException ? '${e.code}: ${e.message}' : '${e.runtimeType}: $e';
      if (t.length > 220) t = '${t.substring(0, 220)}…';
      out.add('✗ домен «${domain.isEmpty ? 'по умолчанию' : domain}»: $t');
      try {
        await _smbCh.invokeMethod<bool>('reset', args);
      } catch (_) {}
    }
  }
  return out;
}

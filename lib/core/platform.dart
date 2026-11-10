import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Мост к нативному Android-коду (привязка к Wi-Fi, фоновая служба, доступ к файлам).
class Native {
  static const MethodChannel _ch = MethodChannel('nanolink/native');

  static Future<T?> _call<T>(String m, [dynamic args]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<T>(m, args);
    } catch (_) {
      return null;
    }
  }

  static Future<void> startKeepAlive({bool bindWifi = true}) async {
    await _call<bool>('startKeepAlive', {'bind': bindWifi});
  }

  static Future<void> stopKeepAlive() async {
    await _call<bool>('stopKeepAlive');
  }

  static Future<bool> hasAllFiles() async => (await _call<bool>('hasAllFiles')) ?? true;
  static Future<void> requestAllFiles() async {
    await _call<bool>('requestAllFiles');
  }

  static Future<void> requestNotifications() async {
    await _call<bool>('requestNotifications');
  }

  static Future<void> requestBatteryExemption({bool once = false}) async {
    await _call<bool>('requestBatteryExemption', {'once': once});
  }

  /// Исключено ли приложение из экономии батареи (иначе при выключенном экране связь может рваться).
  static Future<bool> batteryExempt() async => (await _call<bool>('batteryExempt')) ?? true;

  static Future<List<String>> storageRoots() async {
    final r = await _call<List<dynamic>>('storageRoots');
    if (r == null || r.isEmpty) return ['/storage/emulated/0'];
    return r.map((e) => e.toString()).toList();
  }

  static Future<bool> openFile(String path, String mime) async => (await _call<bool>('openFile', {'path': path, 'mime': mime})) ?? false;

  static void listenShared(Future<void> Function() cb) {
    if (!Platform.isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'sharedReady') await cb();
      if (call.method == 'recvAnswer') {
        final a = call.arguments;
        onRecvAnswer?.call(a is Map && a['ok'] == true);
      }
      return null;
    });
  }

  /// Ответ из кнопок уведомления «Принять / Отклонить».
  static void Function(bool ok)? onRecvAnswer;

  /// Уведомление с кнопками «Принять» и «Отклонить» (видно при выключенном экране).
  static Future<void> notifyAsk(String title, String text, String yes, String no, {int id = 2}) async {
    await _call<bool>('notifyAsk', {'title': title, 'text': text, 'yes': yes, 'no': no, 'id': id});
  }

  static Future<void> cancelNotify({int id = 2}) async {
    await _call<bool>('cancelNotify', {'id': id});
  }

  static Future<void> notify(String title, String text, {int id = 1}) async {
    await _call<bool>('notify', {'title': title, 'text': text, 'id': id});
  }

  /// [всего, свободно] в байтах для общего хранилища или null.
  static Future<List<int>?> storageStats() async {
    final r = await _call<List<dynamic>>('storageStats');
    if (r == null || r.length < 2) return null;
    return [(r[0] as num).toInt(), (r[1] as num).toInt()];
  }

  /// Приложения, умеющие открывать папки: [{pkg, label}].
  static Future<List<Map<String, String>>> listFolderApps(String path) async {
    final r = await _call<List<dynamic>>('listFolderApps', {'path': path});
    if (r == null) return const [];
    return r.map((e) => Map<String, String>.from((e as Map).map((k, v) => MapEntry(k.toString(), v.toString())))).toList();
  }

  /// Открыть папку в стороннем файловом менеджере ([pkg] пусто - любой подходящий).
  static Future<bool> openFolder(String path, {String pkg = ''}) async => (await _call<bool>('openFolder', {'path': path, 'pkg': pkg})) ?? false;

  static Future<List<String>> takeShared() async {
    final r = await _call<List<dynamic>>('takeShared');
    return r == null ? <String>[] : r.map((e) => e.toString()).toList();
  }

  static Future<bool> hasMedia() async => (await _call<bool>('hasMedia')) ?? true;

  /// Системный запрос доступа к фото и видео. true - доступ получен.
  static Future<bool> ensureMedia() async {
    if (!Platform.isAndroid) return true;
    if (await hasMedia()) return true;
    await _call<bool>('requestMedia');
    for (var i = 0; i < 240; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await hasMedia()) return true;
    }
    return false;
  }

  static Future<void> openAppSettings() async {
    await _call<bool>('openAppSettings');
  }

  static Future<List<Map<String, dynamic>>?> queryMedia(String kind) async {
    final r = await _call<List<dynamic>>('queryMedia', {'kind': kind});
    if (r == null) return null;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static final Map<String, Future<Uint8List?>> _thumbs = {};

  static Future<Uint8List?> thumb(String path, {int size = 256}) {
    return _thumbs.putIfAbsent('$path|$size', () => _call<Uint8List>('thumb', {'path': path, 'size': size}));
  }

  static Future<String> deviceModel() async => (await _call<String>('deviceModel')) ?? 'Android';
  static Future<bool> isTv() async => (await _call<bool>('isTv')) ?? false;
  static Future<bool> isTablet() async => (await _call<bool>('isTablet')) ?? false;
}

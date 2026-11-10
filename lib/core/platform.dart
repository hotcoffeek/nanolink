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

  static Future<void> requestBatteryExemption() async {
    await _call<bool>('requestBatteryExemption');
  }

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
      return null;
    });
  }

  static Future<void> notify(String title, String text, {int id = 1}) async {
    await _call<bool>('notify', {'title': title, 'text': text, 'id': id});
  }

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

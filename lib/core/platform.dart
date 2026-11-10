import 'dart:io';

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

  static Future<String> deviceModel() async => (await _call<String>('deviceModel')) ?? 'Android';
  static Future<bool> isTv() async => (await _call<bool>('isTv')) ?? false;
  static Future<bool> isTablet() async => (await _call<bool>('isTablet')) ?? false;
}

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Store {
  File? _file;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    try {
      await dir.create(recursive: true);
    } catch (_) {}
    _file = File('${dir.path}${Platform.pathSeparator}nanolink.json');
  }

  Future<Map<String, dynamic>> load() async {
    try {
      final f = _file;
      if (f != null && await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) return j;
      }
    } catch (_) {}
    return {};
  }

  Future<void> save(Map<String, dynamic> data) async {
    final f = _file;
    if (f == null) return;
    try {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

class Settings {
  String theme = 'oled';
  String lang = 'ru';
  String deviceName = '';
  bool allowWrite = true;
  String conflict = 'rename'; // rename | overwrite | skip
  bool bindWifi = true;
  bool serverOn = true;
  bool autoPair = true;
  bool askReceive = false;

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'lang': lang,
        'deviceName': deviceName,
        'allowWrite': allowWrite,
        'conflict': conflict,
        'bindWifi': bindWifi,
        'serverOn': serverOn,
        'autoPair': autoPair,
        'askReceive': askReceive,
      };

  void apply(Map<String, dynamic> j) {
    theme = (j['theme'] ?? theme).toString();
    lang = (j['lang'] ?? lang).toString();
    deviceName = (j['deviceName'] ?? deviceName).toString();
    allowWrite = (j['allowWrite'] ?? allowWrite) as bool;
    conflict = (j['conflict'] ?? conflict).toString();
    bindWifi = (j['bindWifi'] ?? bindWifi) as bool;
    serverOn = (j['serverOn'] ?? serverOn) as bool;
    autoPair = (j['autoPair'] ?? autoPair) as bool;
    askReceive = (j['askReceive'] ?? askReceive) as bool;
  }
}

import 'models.dart';

/// То, что нужно сетевому слою от приложения (чтобы не было циклических импортов).
abstract class Hub {
  String get myId;
  String get myName;
  DeviceKind get myKind;
  bool get allowWrite;
  bool get autoPairOn;

  /// Самолечение: найти устройство заново (после смены IP, обрыва сети, VPN и т.п.).
  Future<void> heal(Device d);

  /// Адреса сохранённых устройств, которые не лежат в обычной локалке (Tailscale, ZeroTier, вручную).
  List<String> remoteTargets();

  void saveSoon();
  void deviceChanged();

  Future<bool> askPair(PairRequest r);
  String? trustedSecret(String id);
  void trust(String id, String secret, {String? name, DeviceKind? kind, String? ip});
  /// Файл полностью получен от другого устройства.
  void onReceived(String from, String path);

  /// Спросить человека, принять ли входящий файл (true - принять).
  Future<bool> askReceive(String from, String id, String file);

  /// Ход входящей передачи.
  void onIncoming(String from, String file, int done, int total, bool finished);
  void onBeacon(String id, String name, DeviceKind kind, String ip, int port);
}

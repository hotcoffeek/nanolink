import 'models.dart';

/// То, что нужно сетевому слою от приложения (чтобы не было циклических импортов).
abstract class Hub {
  String get myId;
  String get myName;
  DeviceKind get myKind;
  bool get allowWrite;

  /// Самолечение: найти устройство заново (после смены IP, обрыва сети, VPN и т.п.).
  Future<void> heal(Device d);

  void saveSoon();
  void deviceChanged();

  Future<bool> askPair(PairRequest r);
  String? trustedSecret(String id);
  void trust(String id, String secret, {String? name, DeviceKind? kind, String? ip});
  void onBeacon(String id, String name, DeviceKind kind, String ip, int port);
}

import 'dart:async';
import 'dart:io';
import 'dart:math';

const int kPeerPort = 47322;
const int kDiscoPort = 47321;

/// Логическая ошибка файловой операции. Если retry == false, повторять бессмысленно.
class FsError implements Exception {
  final String message;
  final bool retry;
  FsError(this.message, {this.retry = false});
  @override
  String toString() => message;
}

bool isFatal(Object e) => e is FsError && !e.retry;

String fmtSize(num b) {
  if (b < 1024) return '${b.toInt()} B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024.0;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : (v >= 10 ? 1 : 2))} ${u[i]}';
}

String fmtSpeed(double bps) => '${fmtSize(bps)}/s';

String fmtEta(double secs) {
  if (secs.isNaN || secs.isInfinite || secs < 0) return '--';
  final s = secs.round();
  if (s < 60) return '$s c';
  if (s < 3600) return '${s ~/ 60} м ${s % 60} c';
  return '${s ~/ 3600} ч ${(s % 3600) ~/ 60} м';
}

String fmtDate(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

String randomHex(int bytes) {
  final r = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    sb.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Future<void> delay(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

// ---------------------------------------------------------------------------
// Сетевые интерфейсы. VPN-адаптеры и виртуалки исключаем: нам нужен реальный
// Wi-Fi / Ethernet, чтобы соединения шли именно по локалке.
// ---------------------------------------------------------------------------

class Nic {
  final String name;
  final String ip;
  const Nic(this.name, this.ip);
  String get prefix => ip.substring(0, ip.lastIndexOf('.'));
  String get broadcast => '$prefix.255';
}

final RegExp _skipNic = RegExp(
  r'(^|[^a-z])(tun|tap|wg|ppp|utun|ham)[0-9]*([^a-z]|$)|vpn|wintun|wireguard|tailscale|zerotier|nord|proton|ipsec|openvpn|anyconnect|hamachi|radmin|vethernet|vmware|virtualbox|vbox|docker|wsl|hyper-v|loopback|bluetooth',
);

bool isPrivateIp(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return false;
  final a = int.tryParse(p[0]) ?? 0;
  final b = int.tryParse(p[1]) ?? 0;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

/// Адреса «оверлейных» сетей (Tailscale 100.64.0.0/10, ZeroTier), доступные из любой точки мира.
bool isOverlayIp(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return false;
  final a = int.tryParse(p[0]) ?? 0;
  final b = int.tryParse(p[1]) ?? 0;
  return a == 100 && b >= 64 && b <= 127;
}

Future<List<Nic>> overlayNics() async {
  final res = <Nic>[];
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: false);
    for (final i in list) {
      final n = i.name.toLowerCase();
      for (final a in i.addresses) {
        if (isOverlayIp(a.address) || n.startsWith('zt') || n.contains('zerotier') || n.contains('tailscale')) {
          res.add(Nic(i.name, a.address));
        }
      }
    }
  } catch (_) {}
  return res;
}

List<Nic> _nicCache = const [];
DateTime _nicAt = DateTime.fromMillisecondsSinceEpoch(0);

Future<List<Nic>> localNics({bool fresh = false}) async {
  if (!fresh && DateTime.now().difference(_nicAt).inSeconds < 3) return _nicCache;
  final res = <Nic>[];
  try {
    final list = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final i in list) {
      if (_skipNic.hasMatch(i.name.toLowerCase())) continue;
      for (final a in i.addresses) {
        if (!isPrivateIp(a.address)) continue;
        res.add(Nic(i.name, a.address));
      }
    }
  } catch (_) {}
  _nicCache = res;
  _nicAt = DateTime.now();
  return res;
}

Nic? nicFor(String targetIp) {
  final p = targetIp.lastIndexOf('.');
  if (p < 0) return null;
  final prefix = targetIp.substring(0, p);
  for (final n in _nicCache) {
    if (n.prefix == prefix) return n;
  }
  return null;
}

/// TCP-подключение с привязкой к LAN-интерфейсу (в обход VPN-маршрута), если возможно.
Future<Socket> lanConnect(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
  await localNics();
  final nic = nicFor(host);
  if (nic != null) {
    try {
      return await Socket.connect(host, port, sourceAddress: InternetAddress(nic.ip), timeout: timeout);
    } catch (_) {
      // упадём на обычное подключение ниже
    }
  }
  return Socket.connect(host, port, timeout: timeout);
}

Future<bool> portOpen(String host, int port, {int ms = 900}) async {
  try {
    final s = await lanConnect(host, port, timeout: Duration(milliseconds: ms));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

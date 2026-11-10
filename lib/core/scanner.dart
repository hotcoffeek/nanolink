import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'peer.dart';
import 'util.dart';

class SsdpInfo {
  String? friendlyName;
  String? manufacturer;
  String? modelName;
  String? deviceType;
  String? server;
  String? location;
}

class ScanHit {
  final String ip;
  final Set<int> ports;
  String? hostname;
  String? mac;
  SsdpInfo? ssdp;
  Map<String, dynamic>? nano; // ответ NanoLink: id, name, kind
  ScanHit(this.ip, this.ports);

  String get bestName {
    final n = nano?['name']?.toString();
    if (n != null && n.isNotEmpty) return n;
    final f = ssdp?.friendlyName;
    if (f != null && f.isNotEmpty) return f;
    if (hostname != null && hostname!.isNotEmpty) return hostname!;
    return ip;
  }
}

/// Сканер локальной сети: открытые порты (SMB/FTP/SSH/ADB/…), SSDP, имя хоста, MAC.
class Scanner {
  static const List<int> probePorts = [445, 139, 21, 2121, 2020, 3780, 5021, 22, kPeerPort, 5555, 8008, 8009, 53317];

  bool _running = false;
  bool get running => _running;

  Future<List<ScanHit>> scan({void Function(double p)? onProgress}) async {
    if (_running) return const [];
    _running = true;
    try {
      final nics = await localNics(fresh: true);
      if (nics.isEmpty) return const [];
      final mine = nics.map((e) => e.ip).toSet();
      final targets = <String>[];
      final seenPrefix = <String>{};
      for (final n in nics) {
        if (!seenPrefix.add(n.prefix)) continue;
        for (var i = 1; i <= 254; i++) {
          final ip = '${n.prefix}.$i';
          if (!mine.contains(ip)) targets.add(ip);
        }
      }
      final hits = <String, ScanHit>{};
      var idx = 0;
      var doneCount = 0;
      final total = targets.length;

      Future<void> worker() async {
        while (true) {
          final i = idx++;
          if (i >= total) return;
          final ip = targets[i];
          final open = await _probe(ip);
          if (open.isNotEmpty) hits[ip] = ScanHit(ip, open);
          doneCount++;
          if (onProgress != null && doneCount % 8 == 0) onProgress(0.75 * doneCount / total);
        }
      }

      await Future.wait(List.generate(40, (_) => worker()));
      onProgress?.call(0.78);

      // Параллельно: ARP-таблица, SSDP, имена, NanoLink-проба
      final arp = arpTable();
      final ssdpF = ssdp();
      await Future.wait(hits.values.map((h) async {
        if (h.ports.contains(kPeerPort)) h.nano = await probeNano(h.ip);
        try {
          final r = await InternetAddress(h.ip).reverse().timeout(const Duration(milliseconds: 1500));
          if (r.host.isNotEmpty && r.host != h.ip) {
            var n = r.host;
            final dot = n.indexOf('.');
            if (dot > 0) n = n.substring(0, dot);
            h.hostname = n;
          }
        } catch (_) {}
      }));
      onProgress?.call(0.9);
      final arpMap = await arp;
      final ssdpMap = await ssdpF;
      for (final h in hits.values) {
        h.mac = arpMap[h.ip];
        h.ssdp = ssdpMap[h.ip];
      }
      onProgress?.call(1.0);
      return hits.values.toList();
    } finally {
      _running = false;
    }
  }

  /// Проверить один адрес (для добавления по IP и для «самолечения»).
  Future<ScanHit?> probeHost(String ip) async {
    final open = await _probe(ip);
    if (open.isEmpty) return null;
    final h = ScanHit(ip, open);
    if (open.contains(kPeerPort)) h.nano = await probeNano(ip);
    try {
      final r = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 1500));
      if (r.host.isNotEmpty && r.host != ip) {
        final dot = r.host.indexOf('.');
        h.hostname = dot > 0 ? r.host.substring(0, dot) : r.host;
      }
    } catch (_) {}
    h.mac = (await arpTable())[ip];
    return h;
  }

  Future<Set<int>> _probe(String ip) async {
    final open = <int>{};
    await Future.wait(probePorts.map((p) async {
      if (await portOpen(ip, p, ms: 600)) open.add(p);
    }));
    return open;
  }

  Future<Map<String, String>> arpTable() async {
    final m = <String, String>{};
    try {
      String text;
      if (Platform.isWindows) {
        final r = await Process.run('arp', ['-a']);
        text = r.stdout.toString();
      } else {
        text = await File('/proc/net/arp').readAsString();
      }
      final re = RegExp(r'(\d+\.\d+\.\d+\.\d+)\s+(?:0x\d+\s+0x\d+\s+)?([0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5})');
      for (final x in re.allMatches(text)) {
        final mac = x.group(2)!.toLowerCase().replaceAll('-', ':');
        if (mac == '00:00:00:00:00:00' || mac.startsWith('ff:ff')) continue;
        m[x.group(1)!] = mac;
      }
    } catch (_) {}
    return m;
  }

  Future<Map<String, SsdpInfo>> ssdp() async {
    final out = <String, SsdpInfo>{};
    final socks = <RawDatagramSocket>[];
    try {
      final nics = await localNics();
      final msg = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n',
      );
      for (final n in nics) {
        try {
          final s = await RawDatagramSocket.bind(InternetAddress(n.ip), 0);
          s.broadcastEnabled = true;
          s.listen((e) {
            if (e != RawSocketEvent.read) return;
            var d = s.receive();
            while (d != null) {
              _parseSsdp(utf8.decode(d.data, allowMalformed: true), d.address.address, out);
              d = s.receive();
            }
          });
          s.send(msg, InternetAddress('239.255.255.250'), 1900);
          s.send(msg, InternetAddress('239.255.255.250'), 1900);
          socks.add(s);
        } catch (_) {}
      }
      await delay(2300);
    } finally {
      for (final s in socks) {
        try {
          s.close();
        } catch (_) {}
      }
    }
    // Описания устройств (имя, производитель, модель)
    await Future.wait(out.entries.map((e) => _describe(e.key, e.value)));
    return out;
  }

  void _parseSsdp(String text, String ip, Map<String, SsdpInfo> out) {
    final info = out.putIfAbsent(ip, () => SsdpInfo());
    for (final line in const LineSplitter().convert(text)) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim().toLowerCase();
      final v = line.substring(i + 1).trim();
      if (k == 'location') info.location ??= v;
      if (k == 'server') info.server ??= v;
      if (k == 'st' && (info.deviceType == null || v.contains('device'))) info.deviceType = v;
    }
  }

  Future<void> _describe(String ip, SsdpInfo info) async {
    final loc = info.location;
    if (loc == null) return;
    try {
      final uri = Uri.parse(loc);
      if (uri.host != ip) return; // не ходим на чужие адреса
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      try {
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 2));
        final res = await req.close().timeout(const Duration(seconds: 2));
        final body = await utf8.decodeStream(res).timeout(const Duration(seconds: 2));
        String? tag(String t) {
          final m = RegExp('<$t>(.*?)</$t>', dotAll: true).firstMatch(body);
          return m?.group(1)?.trim();
        }

        info.friendlyName = tag('friendlyName');
        info.manufacturer = tag('manufacturer');
        info.modelName = tag('modelName');
        final dt = tag('deviceType');
        if (dt != null) info.deviceType = dt;
      } finally {
        client.close(force: true);
      }
    } catch (_) {}
  }

  static DeviceKind classify(ScanHit h) {
    if (h.nano != null) return kindFromName(h.nano!['kind']?.toString());
    final host = (h.hostname ?? '').toLowerCase();
    final s = h.ssdp;
    final txt = '${s?.friendlyName ?? ''} ${s?.manufacturer ?? ''} ${s?.modelName ?? ''} ${s?.deviceType ?? ''} ${s?.server ?? ''}'.toLowerCase();
    final all = '$host $txt';
    if (host.contains('steamdeck') || txt.contains('steam deck') || txt.contains('steamdeck')) return DeviceKind.steamDeck;
    if (txt.contains('internetgatewaydevice') || RegExp(r'router|gateway').hasMatch(txt)) return DeviceKind.router;
    if (txt.contains('printer')) return DeviceKind.printer;
    if (RegExp(r'synology|qnap|\bnas\b|diskstation|truenas|unraid').hasMatch(all)) return DeviceKind.nas;
    if (RegExp(r'\btv\b|bravia|chromecast|roku|android tv|google tv|mibox|mi box|shield|fire ?tv|rocket|g2 next|tvbox|tv-box').hasMatch(all) ||
        h.ports.contains(8008) ||
        h.ports.contains(8009) ||
        h.ports.contains(5555)) {
      return DeviceKind.tv;
    }
    if (RegExp(r'iphone|galaxy|pixel|redmi|xiaomi|oneplus|huawei|android-|poco|realme|oppo|vivo|honor').hasMatch(all)) return DeviceKind.phone;
    if (RegExp(r'ipad|tablet|\btab\b').hasMatch(all)) return DeviceKind.tablet;
    if (RegExp(r'laptop|notebook').hasMatch(all)) return DeviceKind.laptop;
    if (host.startsWith('desktop-') || host.startsWith('win-') || txt.contains('windows') || (h.ports.contains(445) && !h.ports.contains(22))) {
      return DeviceKind.pc;
    }
    if (h.ports.contains(22) && !h.ports.contains(445)) return DeviceKind.server;
    return DeviceKind.unknown;
  }
}

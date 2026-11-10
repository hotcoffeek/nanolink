enum DeviceKind { thisDevice, pc, laptop, phone, tablet, tv, steamDeck, nas, router, printer, server, unknown }

DeviceKind kindFromName(String? s) {
  for (final k in DeviceKind.values) {
    if (k.name == s) return k;
  }
  return DeviceKind.unknown;
}

class FsEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modified;

  const FsEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.modified,
  });

  String get ext {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  Map<String, dynamic> toJson() => {
        'n': name,
        'p': path,
        'd': isDir,
        's': size,
        'm': modified?.millisecondsSinceEpoch,
      };

  factory FsEntry.fromJson(Map<String, dynamic> j) => FsEntry(
        name: j['n'] as String,
        path: j['p'] as String,
        isDir: j['d'] as bool,
        size: (j['s'] as num?)?.toInt() ?? 0,
        modified: j['m'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['m'] as num).toInt()),
      );
}

class Place {
  final String name;
  final String path;
  final String icon; // desktop, downloads, documents, pictures, videos, music, home, storage
  const Place(this.name, this.path, this.icon);

  Map<String, dynamic> toJson() => {'n': name, 'p': path, 'i': icon};
  factory Place.fromJson(Map<String, dynamic> j) => Place(j['n'] as String, j['p'] as String, (j['i'] ?? 'storage') as String);
}

class Device {
  String id;
  String name;
  String? alias;
  bool favorite;
  DeviceKind kind;
  String? host;
  String? mac;
  String? hostname;
  Map<String, Map<String, dynamic>> services;
  int lastSeen;

  // runtime
  bool online = false;
  bool isSelf = false;
  int aliveAt = 0; // когда в последний раз видели признаки жизни (мс)

  Device({
    required this.id,
    required this.name,
    this.alias,
    this.favorite = false,
    this.kind = DeviceKind.unknown,
    this.host,
    this.mac,
    this.hostname,
    Map<String, Map<String, dynamic>>? services,
    this.lastSeen = 0,
  }) : services = services ?? {};

  String get title => (alias != null && alias!.trim().isNotEmpty) ? alias!.trim() : name;

  bool has(String proto) => services.containsKey(proto);

  int portOf(String proto, int def) {
    final s = services[proto];
    if (s == null) return def;
    final p = s['port'];
    if (p is num) return p.toInt();
    return def;
  }

  String? str(String proto, String key) {
    final v = services[proto]?[key];
    return v?.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'alias': alias,
        'fav': favorite,
        'kind': kind.name,
        'host': host,
        'mac': mac,
        'hostname': hostname,
        'services': services,
        'seen': lastSeen,
      };

  factory Device.fromJson(Map<String, dynamic> j) {
    final sv = <String, Map<String, dynamic>>{};
    final raw = j['services'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) sv[k.toString()] = Map<String, dynamic>.from(v);
      });
    }
    return Device(
      id: j['id'] as String,
      name: (j['name'] ?? 'Device') as String,
      alias: j['alias'] as String?,
      favorite: (j['fav'] ?? false) as bool,
      kind: kindFromName(j['kind'] as String?),
      host: j['host'] as String?,
      mac: j['mac'] as String?,
      hostname: j['hostname'] as String?,
      services: sv,
      lastSeen: (j['seen'] as num?)?.toInt() ?? 0,
    );
  }
}

class PairRequest {
  final String id;
  final String name;
  final String ip;
  final DeviceKind kind;
  PairRequest({required this.id, required this.name, required this.ip, required this.kind});
}

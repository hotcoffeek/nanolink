import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ui/theme.dart';
import 'category.dart' show entryOfPath;
import 'discovery.dart';
import 'ftp_vfs.dart';
import 'hub.dart';
import 'i18n.dart';
import 'local_vfs.dart';
import 'models.dart';
import 'pane.dart';
import 'peer.dart';
import 'peer_server.dart';
import 'platform.dart';
import 'scanner.dart';
import 'sftp_vfs.dart';
import 'smb_native_vfs.dart';
import 'smb_vfs.dart';
import 'store.dart';
import 'transfer.dart';
import 'util.dart';
import 'vfs.dart';

class _PairWait {
  final PairRequest req;
  final Completer<bool> done = Completer<bool>();
  _PairWait(this.req);
}

class RecvRequest {
  final String id;
  final String from;
  final String file;
  RecvRequest(this.id, this.from, this.file);
}

class _RecvWait {
  final RecvRequest req;
  final Completer<bool> done = Completer<bool>();
  _RecvWait(this.req);
}

class Incoming {
  final String from;
  final String name;
  int done;
  int total;
  Incoming(this.from, this.name, this.done, this.total);
}

/// Запись в истории принятых файлов.
class HistItem {
  final String name;
  final String path;
  final String from;
  final int size;
  final int at;
  HistItem(this.name, this.path, this.from, this.size, this.at);

  Map<String, dynamic> toJson() => {'n': name, 'p': path, 'f': from, 's': size, 't': at};

  factory HistItem.fromJson(Map<String, dynamic> j) => HistItem(
        (j['n'] ?? '').toString(),
        (j['p'] ?? '').toString(),
        (j['f'] ?? '').toString(),
        (j['s'] as num?)?.toInt() ?? 0,
        (j['t'] as num?)?.toInt() ?? 0,
      );
}

/// Результат ручного добавления устройства по адресу.
class ManualResult {
  final String? error;
  final String? note;
  final Device? device;
  ManualResult({this.error, this.note, this.device});
}

const List<String> kProtoPriority = ['nano', 'smb', 'sftp', 'ftp'];

String protoLabel(String p) {
  switch (p) {
    case 'nano':
      return 'NanoLink';
    case 'smb':
      return 'SMB';
    case 'sftp':
      return 'SFTP';
    case 'ftp':
      return 'FTP';
  }
  return p;
}

class AppState extends ChangeNotifier implements Hub {
  final Store _store = Store();
  Settings settings = Settings();
  final List<Device> devices = [];
  final Map<String, String> _trusted = {};
  final List<HistItem> history = [];

  String _myId = '';
  DeviceKind _myKind = DeviceKind.pc;
  String _model = '';
  bool isTvUi = false;

  PaneController left = PaneController('L');
  PaneController right = PaneController('R');

  late final TransferEngine transfers = TransferEngine(this);
  late final Discovery discovery = Discovery(this);
  final Scanner scanner = Scanner();
  late final PeerServer server = PeerServer(this);

  late Device self = Device(id: 'self', name: tr('Это устройство', 'This device'), kind: DeviceKind.thisDevice)..isSelf = true;

  int page = 0; // 0 устройства, 1 проводник, 2 передачи, 3 настройки
  bool moveMode = false;

  void setPage(int p) {
    if (page == p) return;
    page = p;
    notifyListeners();
  }

  void setMoveMode(bool v) {
    moveMode = v;
    notifyListeners();
  }

  bool scanning = false;
  double scanProgress = 0;
  bool netOnline = false;
  List<Nic> nics = const [];
  String? serverError;
  bool allFilesOk = true;
  bool ready = false;

  String _nicKey = '';
  Timer? _netTimer;
  Timer? _liveTimer;
  Timer? _saveTimer;
  final List<_PairWait> _pairQ = [];

  // --- Hub ------------------------------------------------------------

  @override
  String get myId => _myId;
  @override
  String get myName => settings.deviceName;
  @override
  DeviceKind get myKind => _myKind;
  @override
  bool get allowWrite => settings.allowWrite;

  NlTheme get theme => themeById(settings.theme);

  // --- Инициализация --------------------------------------------------

  Future<void> init() async {
    await _store.init();
    final d = await _store.load();
    final st = d['settings'];
    if (st is Map) settings.apply(Map<String, dynamic>.from(st));
    L.ru = settings.lang != 'en';
    _myId = (d['myId'] ?? '').toString();
    if (_myId.isEmpty) _myId = randomHex(8);
    final tr0 = d['trusted'];
    if (tr0 is Map) {
      tr0.forEach((k, v) => _trusted[k.toString()] = v.toString());
    }
    final hl = d['history'];
    if (hl is List) {
      for (final x in hl) {
        try {
          history.add(HistItem.fromJson(Map<String, dynamic>.from(x as Map)));
        } catch (_) {}
      }
    }
    final dl = d['devices'];
    if (dl is List) {
      for (final x in dl) {
        try {
          devices.add(Device.fromJson(Map<String, dynamic>.from(x as Map)));
        } catch (_) {}
      }
    }

    if (Platform.isAndroid) {
      LocalVfs.androidRoots = await Native.storageRoots();
      _model = await Native.deviceModel();
      if (await Native.isTv()) {
        _myKind = DeviceKind.tv;
        isTvUi = true;
      } else if (await Native.isTablet()) {
        _myKind = DeviceKind.tablet;
      } else {
        _myKind = DeviceKind.phone;
      }
      allFilesOk = await Native.hasAllFiles();
    } else {
      final host = Platform.localHostname;
      _model = host;
      if (host.toLowerCase().contains('steamdeck')) {
        _myKind = DeviceKind.steamDeck;
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        _myKind = DeviceKind.pc;
      }
    }
    if (settings.deviceName.trim().isEmpty) settings.deviceName = _model.isEmpty ? 'NanoLink' : _model;
    LocalVfs.deviceTitle = settings.deviceName;
    _refreshSelf();

    if (Platform.isAndroid) {
      _lastBind = settings.bindWifi;
      Native.listenShared(pullShared);
      Native.onRecvAnswer = answerRecv;
      TransferEngine.onJobDone = () => PaneController.fsChanged.value++;
      unawaited(Native.startKeepAlive(bindWifi: settings.bindWifi));
      unawaited(applyBind());
      unawaited(Native.requestNotifications());
      // Один раз просим не усыплять приложение: иначе при выключенном экране телефон пропадает из сети.
      unawaited(Future<void>.delayed(const Duration(seconds: 8), () => Native.requestBatteryExemption(once: true)));
    }

    nics = await localNics(fresh: true);
    _nicKey = nics.map((e) => e.ip).join(',');
    netOnline = nics.isNotEmpty;

    if (settings.serverOn) {
      try {
        await server.start();
      } catch (e) {
        serverError = e.toString();
      }
    }
    await discovery.start();

    _netTimer = Timer.periodic(const Duration(seconds: 2), (_) => _netTick());
    _liveTimer = Timer.periodic(const Duration(seconds: 6), (_) => _liveTick());

    ready = true;
    notifyListeners();
    await openLocal(left);
    unawaited(scan());
    saveSoon();
  }

  void _refreshSelf() {
    self.name = settings.deviceName;
    self.kind = DeviceKind.thisDevice;
    self.id = _myId;
    self.isSelf = true;
    self.online = true;
  }

  Future<void> checkAllFiles() async {
    if (!Platform.isAndroid) return;
    allFilesOk = await Native.hasAllFiles();
    notifyListeners();
  }

  // --- Сохранение -----------------------------------------------------

  @override
  void saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      _store.save({
        'myId': _myId,
        'settings': settings.toJson(),
        'trusted': _trusted,
        'devices': devices.map((e) => e.toJson()).toList(),
        'history': history.take(200).map((e) => e.toJson()).toList(),
      });
    });
  }

  @override
  void deviceChanged() => notifyListeners();

  // --- Настройки ------------------------------------------------------

  void setTheme(String id) {
    settings.theme = id;
    saveSoon();
    notifyListeners();
  }

  void setLang(String lang) {
    settings.lang = lang;
    L.ru = lang != 'en';
    _refreshSelf();
    saveSoon();
    notifyListeners();
  }

  void setDeviceName(String n) {
    final t = n.trim();
    if (t.isEmpty) return;
    settings.deviceName = t;
    LocalVfs.deviceTitle = t;
    _refreshSelf();
    saveSoon();
    notifyListeners();
  }

  void setAllowWrite(bool v) {
    settings.allowWrite = v;
    saveSoon();
    notifyListeners();
  }

  void setConflict(String v) {
    settings.conflict = v;
    saveSoon();
    notifyListeners();
  }

  void setAutoPair(bool v) {
    settings.autoPair = v;
    saveSoon();
    notifyListeners();
  }

  Future<void> setBindWifi(bool v) async {
    settings.bindWifi = v;
    saveSoon();
    _lastBind = !v;
    await applyBind();
    notifyListeners();
  }

  Future<void> setServerOn(bool v) async {
    settings.serverOn = v;
    saveSoon();
    if (v) {
      try {
        await server.start();
        serverError = null;
      } catch (e) {
        serverError = e.toString();
      }
    } else {
      await server.stop();
    }
    notifyListeners();
  }

  // --- Устройства -----------------------------------------------------

  Device? deviceById(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<Device> get sortedDevices {
    final l = List<Device>.from(devices);
    l.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return l;
  }

  /// Это наше же устройство (по id или по одному из наших адресов).
  bool isOwn(Device d) {
    if (d.isSelf || d.id == _myId) return true;
    final h = d.host;
    if (h == null) return false;
    return nics.any((n) => n.ip == h);
  }

  /// Все устройства кроме нашего собственного, в стабильном порядке.
  List<Device> get others => sortedDevices.where((d) => !isOwn(d)).toList();

  /// Повторный поиск: сигналы NanoLink + сканирование сети (по нажатию на пульсирующий круг).
  Future<void> rescan() async {
    try {
      discovery.announce();
    } catch (_) {}
    await scan();
  }

  List<String> protosOf(Device d) => kProtoPriority.where(d.services.containsKey).toList();

  void updateDevice(Device d) {
    saveSoon();
    notifyListeners();
  }

  void removeDevice(Device d) {
    devices.remove(d);
    _trusted.remove(d.id);
    unawaited(applyBind());
    saveSoon();
    notifyListeners();
  }

  Vfs makeVfs(Device d, String proto) {
    switch (proto) {
      case 'nano':
        return PeerVfs(d, this);
      case 'smb':
        return Platform.isAndroid ? NativeSmbVfs(d, this) : SmbVfs(d, this);
      case 'sftp':
        return SftpVfs(d, this);
      case 'ftp':
        return FtpVfs(d, this);
    }
    throw FsError('Неизвестный протокол $proto');
  }

  Future<void> openLocal(PaneController p) async {
    await p.attach(LocalVfs(), () => LocalVfs(), null);
  }

  Future<void> connect(PaneController p, Device d, String proto) async {
    if (d.isSelf) {
      await openLocal(p);
      return;
    }
    Vfs mk() => makeVfs(d, proto);
    await p.attach(mk(), mk, d);
  }

  /// Папка, куда складываются принятые/скачанные файлы на этом устройстве.
  Future<String> localInbox() async {
    final v = LocalVfs();
    if (settings.inboxDir.isNotEmpty) {
      try {
        await v.mkdir(settings.inboxDir);
      } catch (_) {}
      return settings.inboxDir;
    }
    String base = '';
    try {
      for (final p in await v.places()) {
        if (p.icon == 'downloads') {
          base = p.path;
          break;
        }
      }
      if (base.isEmpty) base = await v.start();
    } catch (_) {}
    final dir = v.join(base, 'NanoLink');
    try {
      await v.mkdir(dir);
    } catch (_) {}
    return dir;
  }

  /// Куда ушла последняя быстрая отправка (для подсказки).
  String lastSendDest = '';

  /// Отправить файлы на устройство одним нажатием: в запомненную папку, а если её нет -
  /// на «Рабочий стол» (или «Загрузки/NanoLink», когда рабочего стола нет).
  /// Возвращает текст ошибки или null; 'pick' - нужно выбрать папку вручную.
  Future<String?> sendFiles(Device d, List<FsEntry> items) async {
    if (items.isEmpty) return tr('Ничего не выбрано', 'Nothing selected');
    if (!d.has('nano')) return 'pick';
    Vfs mk() => makeVfs(d, 'nano');
    final v = mk();
    var dir = settings.dests[d.id] ?? '';
    try {
      if (dir.isEmpty) {
        final pl = await v.places();
        for (final p in pl) {
          if (p.icon == 'desktop') {
            dir = p.path;
            break;
          }
        }
        if (dir.isEmpty) {
          for (final p in pl) {
            if (p.icon == 'downloads') {
              dir = v.join(p.path, 'NanoLink');
              try {
                await v.mkdir(dir);
              } catch (_) {}
              break;
            }
          }
        }
        if (dir.isEmpty) {
          final st = await v.start();
          if (st.isNotEmpty && st != '/') dir = st;
        }
      }
    } catch (_) {}
    await v.close();
    if (dir.isEmpty || dir == '/') return 'pick';
    lastSendDest = dir;
    transfers.enqueue(
      srcFactory: () => LocalVfs(),
      dstFactory: mk,
      srcDev: null,
      dstDev: d,
      items: items,
      dstDir: dir,
      move: false,
      conflict: settings.conflict,
    );
    return null;
  }

  void swapPanes() {
    final t = left;
    left = right;
    right = t;
    notifyListeners();
  }

  /// Копирование/перемещение выбранного из одной панели в другую.
  String? transferBetween(PaneController from, PaneController to, {required bool move, List<FsEntry>? items}) {
    if (!from.attached || !to.attached) {
      return tr('Сначала выберите устройство в обеих панелях', 'Pick a device in both panes first');
    }
    final sel = items ?? from.selectedEntries;
    if (sel.isEmpty) return tr('Ничего не выбрано', 'Nothing selected');
    if (to.isVirtualRoot) return tr('Откройте папку назначения (не корень)', 'Open a destination folder first');
    transfers.enqueue(
      srcFactory: from.factory!,
      dstFactory: to.factory!,
      srcDev: from.dev,
      dstDev: to.dev,
      items: sel,
      dstDir: to.path,
      move: move,
      conflict: settings.conflict,
    );
    from.clearSelection();
    return null;
  }

  // --- Приём маяков и сопряжение --------------------------------------

  @override
  void onBeacon(String id, String name, DeviceKind kind, String ip, int port) {
    var d = deviceById(id);
    var changed = false;
    if (d == null) {
      d = Device(id: id, name: name, kind: kind, host: ip, services: {'nano': {'port': port}});
      devices.add(d);
      _mergeByHost(d);
      changed = true;
    } else {
      if (d.host != ip) {
        d.host = ip;
        changed = true;
      }
      if (d.name != name) {
        d.name = name;
        changed = true;
      }
      if (kind != DeviceKind.unknown && d.kind != kind) {
        d.kind = kind;
        changed = true;
      }
      if (!d.has('nano') || d.portOf('nano', kPeerPort) != port) {
        d.services['nano'] = {'port': port};
        changed = true;
      }
    }
    d.aliveAt = DateTime.now().millisecondsSinceEpoch;
    if (!d.online) {
      d.online = true;
      changed = true;
    }
    if (changed) {
      saveSoon();
      notifyListeners();
    }
  }

  void _mergeByHost(Device nd) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dup = devices.where((o) {
      if (identical(o, nd) || o.host != nd.host || o.has('nano')) return false;
      if (o.mac != null && nd.mac != null && o.mac != nd.mac) return false;
      return now - o.aliveAt < 10 * 60 * 1000 || o.aliveAt == 0;
    }).toList();
    for (final o in dup) {
      o.services.forEach((k, v) => nd.services.putIfAbsent(k, () => v));
      nd.mac ??= o.mac;
      nd.hostname ??= o.hostname;
      if (o.alias != null && nd.alias == null) nd.alias = o.alias;
      if (o.favorite) nd.favorite = true;
      devices.remove(o);
    }
  }

  @override
  String? trustedSecret(String id) => _trusted[id];

  @override
  void trust(String id, String secret, {String? name, DeviceKind? kind, String? ip}) {
    _trusted[id] = secret;
    var d = deviceById(id);
    if (d == null) {
      d = Device(
        id: id,
        name: name ?? tr('Устройство', 'Device'),
        kind: kind ?? DeviceKind.unknown,
        host: ip,
        services: {'nano': {'port': kPeerPort}},
      );
      devices.add(d);
      _mergeByHost(d);
    } else {
      if (ip != null) d.host = ip;
      d.services.putIfAbsent('nano', () => {'port': kPeerPort});
    }
    d.aliveAt = DateTime.now().millisecondsSinceEpoch;
    d.online = true;
    saveSoon();
    notifyListeners();
  }

  @override
  bool get autoPairOn => settings.autoPair;

  @override
  List<String> remoteTargets() {
    final out = <String>[];
    for (final d in devices) {
      final h = d.host;
      if (d.isSelf || h == null || h.isEmpty) continue;
      if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h)) continue;
      if (nicFor(h) != null) continue;
      out.add(h);
    }
    return out;
  }

  bool _lastBind = true;

  /// Привязка к Wi-Fi помогает против VPN, но ломает Tailscale/ZeroTier и мобильный интернет,
  /// поэтому при наличии оверлейных устройств она автоматически выключается.
  Future<void> applyBind() async {
    if (!Platform.isAndroid) return;
    var want = settings.bindWifi;
    for (final d in devices) {
      final h = d.host;
      if (h != null && isOverlayIp(h)) want = false;
    }
    if (want == _lastBind) return;
    _lastBind = want;
    await Native.startKeepAlive(bindWifi: want);
  }

  // --- Принятые файлы и «Поделиться» ---------------------------------

  int receivedTick = 0;
  String? lastFrom;
  String? lastFile;
  final List<FsEntry> pendingShare = [];
  int shareTick = 0;

  bool foreground = true;
  final Map<String, Incoming> incoming = {};
  DateTime _incAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<_RecvWait> _recvQ = [];
  final Map<String, DateTime> _recvOk = {};

  RecvRequest? get pendingRecv => _recvQ.isEmpty ? null : _recvQ.first.req;

  @override
  void onReceived(String from, String path) {
    PaneController.fsChanged.value++;
    lastFrom = from;
    lastFile = path;
    receivedTick++;
    var size = 0;
    try {
      size = File(path).lengthSync();
    } catch (_) {}
    history.removeWhere((h) => h.path == path);
    history.insert(0, HistItem(path.substring(path.lastIndexOf('/') + 1), path, from, size, DateTime.now().millisecondsSinceEpoch));
    if (history.length > 200) history.removeRange(200, history.length);
    saveSoon();
    if (!foreground) {
      Native.notify(tr('Получено от $from', 'Received from $from'), path.substring(path.lastIndexOf('/') + 1), id: 1);
    }
    notifyListeners();
  }

  @override
  void onIncoming(String from, String file, int done, int total, bool finished) {
    final key = '$from|$file';
    if (finished) {
      if (incoming.remove(key) != null) notifyListeners();
      return;
    }
    var fresh = false;
    final i = incoming.putIfAbsent(key, () {
      fresh = true;
      return Incoming(from, file, 0, total);
    });
    i.done = done;
    i.total = total;
    final now = DateTime.now();
    if (fresh || now.difference(_incAt).inMilliseconds > 300) {
      _incAt = now;
      notifyListeners();
    }
  }

  @override
  Future<bool> askReceive(String from, String id, String file) {
    if (!settings.askReceive) return Future<bool>.value(true);
    // «Принять» действует только на файлы одной отправки: пока идёт приём от этого устройства
    // и ещё несколько секунд после. Повторная отправка спросит снова.
    final ok = _recvOk[id];
    final busy = incoming.values.any((i) => i.from == from);
    if (ok != null && (busy || DateTime.now().difference(ok).inSeconds < 10)) {
      _recvOk[id] = DateTime.now();
      return Future<bool>.value(true);
    }
    for (final w in _recvQ) {
      if (w.req.id == id) return w.done.future;
    }
    final w = _RecvWait(RecvRequest(id, from, file));
    _recvQ.add(w);
    if (!foreground) Native.notifyAsk(tr('$from хочет отправить файл', '$from wants to send a file'), file, tr('Принять', 'Accept'), tr('Отклонить', 'Decline'), id: 2);
    notifyListeners();
    // Отправитель ждёт ответ около 20 секунд, поэтому отвечаем чуть раньше.
    Timer(const Duration(seconds: 18), () {
      if (!w.done.isCompleted) {
        _recvQ.remove(w);
        w.done.complete(false);
        if (!foreground) Native.cancelNotify(id: 2);
        notifyListeners();
      }
    });
    return w.done.future;
  }

  void answerRecv(bool ok) {
    if (_recvQ.isEmpty) return;
    final w = _recvQ.removeAt(0);
    Native.cancelNotify(id: 2);
    if (ok) _recvOk[w.req.id] = DateTime.now();
    if (!w.done.isCompleted) w.done.complete(ok);
    notifyListeners();
  }

  void removeHistory(HistItem h) {
    history.remove(h);
    saveSoon();
    notifyListeners();
  }

  void forgetPaths(Set<String> paths) {
    history.removeWhere((h) => paths.contains(h.path));
    saveSoon();
    notifyListeners();
  }

  void clearHistory() {
    history.clear();
    saveSoon();
    notifyListeners();
  }

  /// Запомненная папка назначения на устройстве [d] (пусто - по умолчанию: Рабочий стол).
  String destFor(Device d) => settings.dests[d.id] ?? '';

  void setDest(Device d, String path) {
    settings.dests[d.id] = path;
    saveSoon();
    notifyListeners();
  }

  void clearDest(String deviceId) {
    settings.dests.remove(deviceId);
    saveSoon();
    notifyListeners();
  }

  void clearAllDests() {
    settings.dests.clear();
    saveSoon();
    notifyListeners();
  }

  void setFolderApp(String pkg, String label) {
    settings.folderApp = pkg;
    settings.folderAppLabel = label;
    saveSoon();
    notifyListeners();
  }

  void setInboxDir(String d) {
    settings.inboxDir = d;
    saveSoon();
    notifyListeners();
  }

  void setPickList(bool v) {
    settings.pickList = v;
    saveSoon();
    notifyListeners();
  }

  void setAskReceive(bool v) {
    settings.askReceive = v;
    saveSoon();
    notifyListeners();
  }

  Future<void> pullShared() async {
    if (!Platform.isAndroid) return;
    final paths = await Native.takeShared();
    var any = false;
    for (final p in paths) {
      final e = entryOfPath(p);
      if (e != null) {
        pendingShare.add(e);
        any = true;
      }
    }
    if (any) {
      shareTick++;
      notifyListeners();
    }
  }

  PairRequest? get pendingPair => _pairQ.isEmpty ? null : _pairQ.first.req;

  @override
  Future<bool> askPair(PairRequest r) {
    if (settings.autoPair) return Future<bool>.value(true);
    for (final w in _pairQ) {
      if (w.req.id == r.id) return w.done.future;
    }
    final w = _PairWait(r);
    _pairQ.add(w);
    notifyListeners();
    Timer(const Duration(seconds: 60), () {
      if (!w.done.isCompleted) {
        _pairQ.remove(w);
        w.done.complete(false);
        notifyListeners();
      }
    });
    return w.done.future;
  }

  void answerPair(bool ok) {
    if (_pairQ.isEmpty) return;
    final w = _pairQ.removeAt(0);
    if (!w.done.isCompleted) w.done.complete(ok);
    notifyListeners();
  }

  // --- Сеть: следим за интерфейсами, сканируем, лечим ------------------

  Future<void> _netTick() async {
    final n = await localNics(fresh: true);
    final key = n.map((e) => e.ip).join(',');
    if (key != _nicKey) {
      _nicKey = key;
      nics = n;
      netOnline = n.isNotEmpty;
      notifyListeners();
      if (n.isNotEmpty) {
        discovery.announce();
        await delay(1200);
        unawaited(scan());
      }
    }
  }

  Future<void> _liveTick() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final d in devices) {
      if (d.isSelf) continue;
      bool alive;
      if (d.has('nano')) {
        alive = now - d.aliveAt < 12000;
      } else {
        if (now - d.aliveAt >= 15000 && netOnline) {
          if (await _alive(d)) d.aliveAt = now;
        }
        alive = now - d.aliveAt < 45000;
      }
      if (alive != d.online) {
        d.online = alive;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> scan() async {
    if (scanning || !netOnline) return;
    scanning = true;
    scanProgress = 0;
    notifyListeners();
    try {
      final hits = await scanner.scan(onProgress: (p) {
        scanProgress = p;
        notifyListeners();
      });
      _mergeScan(hits);
    } catch (_) {}
    scanning = false;
    scanProgress = 1;
    saveSoon();
    notifyListeners();
  }

  void _addPortServices(Device d, Set<int> ports) {
    if (ports.contains(445)) d.services.putIfAbsent('smb', () => {'port': 445});
    if (ports.contains(21)) {
      d.services.putIfAbsent('ftp', () => {'port': 21});
    } else if (ports.contains(2121)) {
      d.services.putIfAbsent('ftp', () => {'port': 2121});
    }
    if (ports.contains(22)) d.services.putIfAbsent('sftp', () => {'port': 22});
  }

  void _mergeScan(List<ScanHit> hits) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <Device>{};
    final mine = nics.map((e) => e.ip).toSet();
    for (final h in hits) {
      if (mine.contains(h.ip)) continue;
      final kind = Scanner.classify(h);
      Device? d;
      final nid = h.nano?['id']?.toString();
      if (nid != null && nid.isNotEmpty && nid != _myId) {
        d = deviceById(nid);
        if (d == null) {
          d = Device(
            id: nid,
            name: (h.nano!['name'] ?? h.bestName).toString(),
            kind: kind,
            host: h.ip,
            services: {'nano': {'port': kPeerPort}},
          );
          devices.add(d);
          _mergeByHost(d);
        }
        d.host = h.ip;
        d.services.putIfAbsent('nano', () => {'port': kPeerPort});
      } else {
        for (final o in devices) {
          if (o.isSelf) continue;
          if ((h.mac != null && o.mac == h.mac) || o.host == h.ip) {
            d = o;
            break;
          }
        }
        if (d == null) {
          final id = h.mac != null ? 'mac:${h.mac}' : (h.hostname != null ? 'host:${h.hostname}' : 'ip:${h.ip}');
          d = deviceById(id);
          if (d == null) {
            d = Device(id: id, name: h.bestName, kind: kind, host: h.ip);
            devices.add(d);
          }
        }
        d.host = h.ip;
        if (d.kind == DeviceKind.unknown && kind != DeviceKind.unknown) d.kind = kind;
        // служебные имена вроде «WPS Access Point» заменяем настоящим (имя хоста / модель)
        if (d.name == d.host || d.name.startsWith('ip:') || (isGenericDeviceName(d.name) && h.bestName != h.ip && !isGenericDeviceName(h.bestName))) {
          d.name = h.bestName;
        }
      }
      d.mac ??= h.mac;
      if (h.hostname != null) d.hostname = h.hostname;
      if (d.kind == DeviceKind.unknown && kind != DeviceKind.unknown) d.kind = kind;
      _addPortServices(d, h.ports);
      d.aliveAt = now;
      d.online = true;
      d.lastSeen = now;
      seen.add(d);
    }
    for (final d in devices) {
      if (d.isSelf || seen.contains(d) || d.has('nano')) continue;
      d.online = false;
      d.aliveAt = 0;
    }
  }

  Future<String?> addManual(String ip) async {
    final t = ip.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(t)) {
      return tr('Введите IP (192.168.1.50 или 100.x от Tailscale) или имя', 'Enter an IP (192.168.1.50 or Tailscale 100.x) or a name');
    }
    await localNics(fresh: true);
    final hit = await scanner.probeHost(t);
    if (hit == null) {
      Device? d;
      for (final e in devices) {
        if (e.host == t) {
          d = e;
          break;
        }
      }
      if (d == null) {
        d = Device(id: 'ip:$t', name: t, host: t);
        devices.add(d);
      }
      saveSoon();
      unawaited(applyBind());
      notifyListeners();
      return tr('Устройство не ответило, но добавлено - настройте протокол вручную', 'No answer, added anyway - configure the protocol manually');
    }
    _mergeScan([hit]);
    saveSoon();
    unawaited(applyBind());
    notifyListeners();
    return null;
  }

  Device? _byHost(String h) {
    for (final e in devices) {
      if (!e.isSelf && e.host == h) return e;
    }
    return null;
  }

  /// Ручное подключение: адрес, протокол (auto/nano/ftp/sftp/smb), порт, логин и пароль.
  Future<ManualResult> addManualEx(String host, String proto, {int port = 0, String user = '', String pass = ''}) async {
    final t = host.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(t)) {
      return ManualResult(error: tr('Введите IP (192.168.1.50 или 100.x от Tailscale) или имя', 'Enter an IP (192.168.1.50 or Tailscale 100.x) or a name'));
    }
    if (proto == 'auto' || proto == 'nano') {
      final r = await addManual(t);
      return ManualResult(note: r, device: _byHost(t));
    }
    await localNics(fresh: true);
    final defPort = proto == 'ftp' ? 21 : (proto == 'sftp' ? 22 : 445);
    final use = port > 0 ? port : defPort;
    final open = await portOpen(t, use, ms: 3000);
    var d = _byHost(t);
    if (d == null) {
      d = Device(id: 'ip:$t', name: t, host: t);
      devices.add(d);
    }
    final defUser = proto == 'ftp' ? 'anonymous' : (proto == 'sftp' ? 'deck' : 'guest');
    d.services[proto] = {'port': use, 'user': user.trim().isEmpty ? defUser : user.trim(), 'pass': pass, 'configured': true};
    if (open) {
      d.online = true;
      d.aliveAt = DateTime.now().millisecondsSinceEpoch;
    }
    saveSoon();
    unawaited(applyBind());
    notifyListeners();
    return ManualResult(
      device: d,
      note: open ? null : tr('Порт $use не отвечает - устройство добавлено, но подключиться может не получиться. Проверьте адрес, порт и что сервис включён.', 'Port $use is not answering - the device is added but connecting may fail. Check the address, the port and that the service is on.'),
    );
  }

  // --- Самолечение ----------------------------------------------------

  final Map<String, Future<void>> _healing = {};

  @override
  Future<void> heal(Device d) {
    final cur = _healing[d.id];
    if (cur != null) return cur;
    final f = _doHeal(d).whenComplete(() => _healing.remove(d.id));
    _healing[d.id] = f;
    return f;
  }

  Future<bool> _alive(Device d) async {
    final h = d.host;
    if (h == null) return false;
    for (final e in d.services.entries) {
      final port = (e.value['port'] as num?)?.toInt();
      if (port != null && await portOpen(h, port, ms: 1200)) return true;
    }
    return false;
  }

  ScanHit? _match(Device d, List<ScanHit> hits) {
    if (d.mac != null) {
      for (final h in hits) {
        if (h.mac == d.mac) return h;
      }
    }
    for (final h in hits) {
      if (h.nano != null && h.nano!['id'] == d.id) return h;
    }
    if (d.hostname != null) {
      for (final h in hits) {
        if (h.hostname != null && h.hostname!.toLowerCase() == d.hostname!.toLowerCase()) return h;
      }
    }
    final ports = d.services.values.map((v) => (v['port'] as num?)?.toInt()).whereType<int>().toList();
    if (ports.isNotEmpty) {
      final cand = hits.where((h) => ports.every(h.ports.contains)).toList();
      if (cand.length == 1) return cand.first;
    }
    return null;
  }

  Future<void> _doHeal(Device d) async {
    // 1. Ждём, пока вернётся сеть (Wi-Fi переподключается, VPN переключается и т.п.)
    var waited = 0;
    while ((await localNics(fresh: true)).isEmpty) {
      await delay(1500);
      if (++waited > 60) return;
    }
    // 2. Устройство на прежнем адресе?
    if (await _alive(d)) {
      d.aliveAt = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    // 3. NanoLink-устройства сами откликаются маяком (адрес обновится в onBeacon)
    if (d.has('nano')) {
      discovery.announce();
      await delay(1500);
      if (await _alive(d)) return;
    }
    // 4. Сканируем сеть и ищем по MAC / имени / набору портов
    final hits = await scanner.scan();
    final m = _match(d, hits);
    if (m != null) {
      d.host = m.ip;
      d.mac ??= m.mac;
      if (m.hostname != null) d.hostname = m.hostname;
      d.aliveAt = DateTime.now().millisecondsSinceEpoch;
      saveSoon();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _netTimer?.cancel();
    _liveTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}

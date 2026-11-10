import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'category.dart';
import 'i18n.dart';
import 'local_vfs.dart';
import 'models.dart';
import 'peer.dart';
import 'smb_vfs.dart';
import 'util.dart';
import 'vfs.dart';

String friendlyError(Object e) {
  if (e is FsError) return e.message;
  if (e is TimeoutException) return 'Устройство не отвечает';
  if (e is SocketException) return 'Нет связи с устройством';
  final t = e.toString();
  return t.length > 160 ? '${t.substring(0, 160)}…' : t;
}

/// Одна из двух панелей проводника.
class PaneController extends ChangeNotifier {
  final String id;
  PaneController(this.id);

  Vfs? vfs;
  Device? dev;
  Vfs Function()? factory;

  String path = '';
  List<FsEntry> entries = const [];
  final Set<String> selected = <String>{};
  bool loading = false;
  String? error;
  bool grid = false;
  String sort = 'name';
  bool asc = true;
  List<Place> places = const [];

  // Категории (фото/видео/музыка/документы)
  Cat? cat;
  List<Album> albums = const [];
  bool catLoading = false;
  int catFound = 0;
  Set<String>? filter;

  int _gen = 0;

  bool get attached => vfs != null;
  String get title => dev?.title ?? vfs?.title ?? '—';
  bool get isLocal => dev == null && vfs != null;

  bool get isVirtualRoot => path.isEmpty || ((vfs is PeerVfs || vfs is SmbVfs) && path == '/');

  void poke() => notifyListeners();

  Future<void> attach(Vfs v, Vfs Function() f, Device? d) async {
    final old = vfs;
    vfs = v;
    factory = f;
    dev = d;
    cat = null;
    filter = null;
    albums = const [];
    entries = const [];
    places = const [];
    selected.clear();
    error = null;
    loading = true;
    notifyListeners();
    try {
      await old?.close();
    } catch (_) {}
    final gen = ++_gen;
    try {
      path = await v.start();
      if (gen != _gen) return;
      if (v is PeerVfs) v.startMonitor();
      unawaited(v.places().then((p) {
        if (gen == _gen) {
          places = p;
          notifyListeners();
        }
      }));
      await _load(gen);
    } catch (e) {
      if (gen != _gen) return;
      error = friendlyError(e);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> detach() async {
    final old = vfs;
    vfs = null;
    dev = null;
    factory = null;
    entries = const [];
    selected.clear();
    _gen++;
    notifyListeners();
    try {
      await old?.close();
    } catch (_) {}
  }

  Future<void> _load(int gen) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final l = await vfs!.list(path);
      if (gen != _gen) return;
      entries = l;
      selected.clear();
    } catch (e) {
      if (gen != _gen) return;
      error = friendlyError(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() => _load(++_gen);

  Future<void> cd(String p, {bool keepFilter = false}) async {
    if (vfs == null) return;
    path = p;
    if (!keepFilter) filter = null;
    cat = keepFilter ? cat : null;
    await _load(++_gen);
  }

  Future<void> up() async {
    final v = vfs;
    if (v == null) return;
    final p = v.parent(path);
    if (p == path) return;
    await cd(p, keepFilter: filter != null);
  }

  bool get canGoUp {
    final v = vfs;
    if (v == null) return false;
    return v.parent(path) != path;
  }

  // --- Категории -----------------------------------------------------

  final Map<Cat, List<Album>> _catCache = {};

  Future<void> openCategory(Cat c, {bool force = false}) async {
    cat = c;
    filter = catExt[c];
    selected.clear();
    albums = _catCache[c] ?? const [];
    catFound = 0;
    catLoading = force || !_catCache.containsKey(c);
    notifyListeners();
    if (!catLoading) return;
    try {
      final l = await scanCategory(c, onProgress: (n) {
        catFound = n;
        notifyListeners();
      });
      _catCache[c] = l;
      if (cat == c) albums = l;
    } catch (_) {}
    catLoading = false;
    notifyListeners();
  }

  void closeCategory() {
    cat = null;
    filter = null;
    notifyListeners();
  }

  Future<void> openAlbum(Album a) async {
    final c = cat;
    cat = null; // показываем обычный список, но с фильтром по расширению
    filter = c == null ? null : catExt[c];
    path = a.path;
    await _load(++_gen);
  }

  // --- Просмотр -------------------------------------------------------

  List<FsEntry> get view {
    final f = filter;
    final l = entries.where((e) => f == null || e.isDir || f.contains(e.ext)).toList();
    l.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int c;
      switch (sort) {
        case 'size':
          c = a.size.compareTo(b.size);
          break;
        case 'date':
          c = (a.modified?.millisecondsSinceEpoch ?? 0).compareTo(b.modified?.millisecondsSinceEpoch ?? 0);
          break;
        default:
          c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return asc ? c : -c;
    });
    return l;
  }

  List<FsEntry> get selectedEntries => entries.where((e) => selected.contains(e.path)).toList();

  void toggle(FsEntry e) {
    if (!selected.remove(e.path)) selected.add(e.path);
    notifyListeners();
  }

  void selectAll() {
    final v = view;
    if (selected.length >= v.length) {
      selected.clear();
    } else {
      selected
        ..clear()
        ..addAll(v.map((e) => e.path));
    }
    notifyListeners();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    notifyListeners();
  }

  void setSort(String s) {
    if (sort == s) {
      asc = !asc;
    } else {
      sort = s;
      asc = true;
    }
    notifyListeners();
  }

  void toggleGrid() {
    grid = !grid;
    notifyListeners();
  }

  // --- Операции -------------------------------------------------------

  Future<void> mkdir(String name) async {
    final v = vfs!;
    await v.mkdir(v.join(path, name));
    await refresh();
  }

  Future<void> renameSelected(String newName) async {
    final v = vfs!;
    final sel = selectedEntries;
    if (sel.length != 1) return;
    await v.rename(sel.first.path, v.join(v.parent(sel.first.path), newName));
    await refresh();
  }

  Future<void> deleteSelected() async {
    final v = vfs!;
    for (final e in selectedEntries) {
      await v.delete(e.path);
    }
    await refresh();
  }

  /// Кусочки пути для «хлебных крошек».
  List<MapEntry<String, String>> get crumbs {
    final v = vfs;
    if (v == null) return const [];
    final out = <MapEntry<String, String>>[];
    String root;
    if (v.remote) {
      root = '/';
    } else if (Platform.isWindows || Platform.isAndroid) {
      root = '';
    } else {
      root = '/';
    }
    out.add(MapEntry(title, root));
    if (path.isEmpty) return out;
    final sep = v.sep;
    var rest = path;
    var acc = '';
    if (!v.remote && Platform.isAndroid) {
      for (final r in LocalVfs.androidRoots) {
        if (path == r || path.startsWith('$r/')) {
          out.add(MapEntry(r == '/storage/emulated/0' ? tr('Память', 'Storage') : r.substring(r.lastIndexOf('/') + 1), r));
          rest = path.substring(r.length);
          acc = r;
          break;
        }
      }
    }
    final parts = rest.split(sep).where((x) => x.isNotEmpty).toList();
    for (var i = 0; i < parts.length; i++) {
      if (sep == '\\') {
        acc = i == 0 ? '${parts[0]}\\' : (acc.endsWith('\\') ? '$acc${parts[i]}' : '$acc\\${parts[i]}');
      } else {
        acc = '$acc/${parts[i]}';
      }
      out.add(MapEntry(parts[i], acc));
    }
    return out;
  }
}

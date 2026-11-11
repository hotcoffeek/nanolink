import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/category.dart';
import '../core/ftp_vfs.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/pane.dart';
import '../core/platform.dart';
import '../core/peer.dart';
import '../core/sftp_vfs.dart';
import '../core/smb_vfs.dart';
import '../core/state.dart';
import '../core/thumbs.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'explorer_home.dart';
import 'theme.dart';
import 'widgets.dart';

class DragData {
  final PaneController from;
  final List<FsEntry> items;
  DragData(this.from, this.items);
}

String? protoOfPane(PaneController p) {
  final v = p.vfs;
  if (v is PeerVfs) return 'nano';
  if (v is FtpVfs) return 'ftp';
  if (v is SftpVfs) return 'sftp';
  if (v is SmbVfs) return 'smb';
  return null;
}

const Set<String> _imgExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

class PaneView extends StatelessWidget {
  final PaneController pane;
  final bool hideHeader;
  final bool hideSelBar;
  final bool hideCats;
  const PaneView({super.key, required this.pane, this.hideHeader = false, this.hideSelBar = false, this.hideCats = false});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    return DragTarget<DragData>(
      onWillAcceptWithDetails: (d) => d.data.from != pane && pane.attached,
      onAcceptWithDetails: (d) {
        final err = s.transferBetween(d.data.from, pane, move: s.moveMode, items: d.data.items);
        if (err != null) toast(context, err);
      },
      builder: (context, cand, rej) {
        return Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cand.isNotEmpty ? t.accent : t.border, width: cand.isNotEmpty ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListenableBuilder(
            listenable: pane,
            builder: (context, _) => Column(children: [
              if (!hideHeader) _Header(pane: pane),
              _PathBar(pane: pane),
              _Strip(pane: pane, hideCats: hideCats),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: _Body(pane: pane)),
                  if (pane.loading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
                ]),
              ),
              if (pane.selected.isNotEmpty && !hideSelBar) _SelectionBar(pane: pane),
            ]),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final PaneController pane;
  const _Header({required this.pane});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final dev = pane.dev ?? s.self;
    final online = pane.attached && pane.error == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 2),
      child: Row(children: [
        Flexible(
          child: PopupMenuButton<Device>(
            tooltip: tr('Выбрать устройство', 'Choose device'),
            onSelected: (d) async {
              await connectFlow(context, s, pane, d);
              if (pane.error != null && context.mounted) toast(context, pane.error!);
            },
            itemBuilder: (_) => [
              for (final d in [s.self, ...s.sortedDevices])
                PopupMenuItem<Device>(
                  value: d,
                  child: Row(children: [
                    Icon(kindIcon(d.kind), size: 20, color: d.online ? t.accent2 : t.muted),
                    const SizedBox(width: 10),
                    Flexible(child: Text(d.isSelf ? '${tr('Это устройство', 'This device')} · ${s.myName}' : d.title, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(pane.attached ? kindIcon(dev.isSelf ? s.myKind : dev.kind) : Icons.add_link_rounded, size: 19, color: t.accent2),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    pane.attached ? (pane.dev?.title ?? s.myName) : tr('Выбрать устройство', 'Choose device'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (pane.attached) ...[
                  const SizedBox(width: 8),
                  PulseDot(color: online ? const Color(0xFF3DDC84) : const Color(0xFFFF4D5E), size: 8),
                  if (online && !pane.isLocal && pane.entries.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(tr('Подключено', 'Connected'), style: const TextStyle(color: Color(0xFF3DDC84), fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ],
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: 18, color: t.muted),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (pane.attached) ...[
          IconBtn(icon: pane.gridNow ? Icons.view_list_rounded : Icons.grid_view_rounded, tip: tr('Вид', 'View'), onTap: pane.toggleView),
          PopupMenuButton<String>(
            tooltip: tr('Сортировка', 'Sort'),
            icon: Icon(Icons.sort_rounded, size: 20, color: t.muted),
            onSelected: pane.setSort,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'name', child: Text(tr('По имени', 'By name'))),
              PopupMenuItem(value: 'date', child: Text(tr('По дате', 'By date'))),
              PopupMenuItem(value: 'size', child: Text(tr('По размеру', 'By size'))),
            ],
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, size: 20, color: t.muted),
            onSelected: (v) => _more(context, s, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'mkdir', child: Text(tr('Создать папку', 'New folder'))),
              PopupMenuItem(value: 'goto', child: Text(tr('Перейти по пути…', 'Go to path…'))),
              PopupMenuItem(value: 'all', child: Text(tr('Выбрать всё', 'Select all'))),
              PopupMenuItem(value: 'refresh', child: Text(tr('Обновить', 'Refresh'))),
              PopupMenuItem(value: 'off', child: Text(tr('Отключить', 'Disconnect'))),
            ],
          ),
        ],
      ]),
    );
  }

  Future<void> _more(BuildContext context, AppState s, String v) async {
    try {
      switch (v) {
        case 'mkdir':
          if (pane.isVirtualRoot) {
            toast(context, tr('Сначала откройте папку', 'Open a folder first'));
            return;
          }
          final n = await promptText(context, title: tr('Новая папка', 'New folder'), hint: tr('Имя папки', 'Folder name'));
          if (n != null && n.trim().isNotEmpty) await pane.mkdir(n.trim());
          break;
        case 'goto':
          final p = await promptText(context, title: tr('Перейти по пути', 'Go to path'), initial: pane.path);
          if (p != null) await pane.cd(p.trim());
          break;
        case 'all':
          pane.selectAll();
          break;
        case 'refresh':
          await pane.refresh();
          break;
        case 'off':
          await pane.detach();
          break;
      }
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }
}

class _PathBar extends StatelessWidget {
  final PaneController pane;
  const _PathBar({required this.pane});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    if (!pane.attached) return const SizedBox(height: 6);
    final crumbs = pane.crumbs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      child: Row(children: [
        if (pane.homeEnabled) IconBtn(icon: Icons.home_rounded, tip: tr('Главная', 'Home'), active: pane.home, onTap: pane.goHome),
        IconBtn(icon: Icons.arrow_upward_rounded, tip: tr('Вверх', 'Up'), onTap: pane.canGoUp && !pane.home ? pane.up : null),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: Row(children: [
                  if (pane.home) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text(tr('Главная', 'Home'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                  if (!pane.home)
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: t.muted),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => pane.cd(crumbs[i].value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                        child: Text(
                          crumbs[i].key,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: i == crumbs.length - 1 ? FontWeight.w800 : FontWeight.w500,
                            color: i == crumbs.length - 1 ? t.text : t.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
        IconBtn(icon: Icons.refresh_rounded, tip: tr('Обновить', 'Refresh'), onTap: pane.refresh),
      ]),
    );
  }
}

class _Strip extends StatelessWidget {
  final PaneController pane;
  final bool hideCats;
  const _Strip({required this.pane, this.hideCats = false});

  @override
  Widget build(BuildContext context) {
    if (!pane.attached || pane.home) return const SizedBox.shrink();
    final chips = <Widget>[];
    if (!hideCats) {
      chips.add(_StripChip(
        label: tr('Файлы', 'Files'),
        icon: Icons.folder_open_rounded,
        selected: pane.filter == null && pane.cat == null,
        onTap: () async {
          pane.closeCategory();
          final p = await pane.vfs!.start();
          await pane.cd(p);
        },
      ));
      final defs = <MapEntry<Cat, MapEntry<String, IconData>>>[
        MapEntry(Cat.photos, MapEntry(tr('Фото', 'Photos'), Icons.photo_library_rounded)),
        MapEntry(Cat.videos, MapEntry(tr('Видео', 'Videos'), Icons.video_library_rounded)),
        MapEntry(Cat.audio, MapEntry(tr('Музыка', 'Music'), Icons.library_music_rounded)),
        MapEntry(Cat.docs, MapEntry(tr('Документы', 'Docs'), Icons.article_rounded)),
      ];
      for (final d in defs) {
        chips.add(_StripChip(
          label: d.value.key,
          icon: d.value.value,
          selected: pane.filter != null && identical(pane.filter, catExt[d.key]),
          onTap: () => pane.openCategory(d.key),
        ));
      }
    }
    for (final pl in pane.places) {
      chips.add(_StripChip(
        label: pl.name,
        icon: placeIcon(pl.icon),
        onTap: () {
          pane.closeCategory();
          pane.cd(pl.path);
        },
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final PaneController pane;
  const _Body({required this.pane});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final s = AppScope.of(context);
    if (!pane.attached) return _Placeholder(pane: pane);
    if (pane.error != null && pane.entries.isEmpty) return _ErrorView(pane: pane);
    if (pane.home && pane.cat == null) return ExplorerHome(pane: pane);
    if (pane.cat != null) return _Albums(pane: pane);
    final list = pane.view;
    if (list.isEmpty && pane.loading) return _Connecting(pane: pane);
    if (list.isEmpty && !pane.loading) {
      return Center(child: Text(tr('Здесь пусто', 'Empty here'), style: TextStyle(color: t.muted)));
    }
    return LayoutBuilder(builder: (context, c) {
      if (pane.grid) {
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 128, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.86),
          itemCount: list.length,
          itemBuilder: (_, i) => _wrapDrag(context, s, t, pane, list[i], _GridTile(pane: pane, e: list[i])),
        );
      }
      final cols = c.maxWidth > 460;
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: list.length,
        itemExtent: 64,
        itemBuilder: (_, i) => _wrapDrag(context, s, t, pane, list[i], _RowTile(pane: pane, e: list[i], cols: cols)),
      );
    });
  }
}

Widget _wrapDrag(BuildContext context, AppState s, NlTheme t, PaneController pane, FsEntry e, Widget child) {
  final sel = pane.selected.contains(e.path);
  final items = sel ? pane.selectedEntries : [e];
  final data = DragData(pane, items);
  final feedback = Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(gradient: t.gradient, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.file_copy_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(items.length == 1 ? e.name : tr('${items.length} объектов', '${items.length} items'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
  if (Platform.isAndroid || Platform.isIOS) {
    return LongPressDraggable<DragData>(data: data, feedback: feedback, child: child);
  }
  return Draggable<DragData>(data: data, feedback: feedback, child: child);
}

Widget _thumb(PaneController pane, FsEntry e, double size, FileStyle st) {
  if (pane.isLocal && !e.isDir && _imgExt.contains(e.ext) && e.size < 40 * 1024 * 1024) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: _LocalThumb(path: e.path, width: size, height: size, st: st, iconSize: size * 0.7),
    );
  }
  if (!pane.isLocal && pane.vfs != null && !e.isDir && _imgExt.contains(e.ext) && e.size > 0 && e.size < 8 * 1024 * 1024) {
    return _RemoteImg(pane: pane, e: e, w: size, h: size, st: st, radius: 8);
  }
  return Icon(st.icon, color: st.color, size: size * 0.7);
}

class _RemoteImg extends StatelessWidget {
  final PaneController pane;
  final FsEntry e;
  final double w;
  final double h;
  final FileStyle st;
  final double radius;
  const _RemoteImg({required this.pane, required this.e, required this.w, required this.h, required this.st, required this.radius});

  @override
  Widget build(BuildContext context) {
    final v = pane.vfs!;
    return FutureBuilder<File?>(
      future: RemoteThumbs.get(v, e, pane.dev?.id ?? 'x'),
      builder: (_, snap) {
        final f = snap.data;
        if (f == null) return Icon(st.icon, color: st.color, size: w.isFinite ? w * 0.7 : 46);
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(f, width: w.isFinite ? w : null, height: h.isFinite ? h : null, fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true, errorBuilder: (_, __, ___) => Icon(st.icon, color: st.color, size: 46)),
        );
      },
    );
  }
}

Future<void> _tapEntry(BuildContext context, PaneController pane, FsEntry e) async {
  if (e.isDir) {
    await pane.cd(e.path, keepFilter: pane.filter != null);
    return;
  }
  if (pane.selected.isNotEmpty || pane.pickMode) {
    pane.toggle(e);
    return;
  }
  if (!pane.isLocal) toast(context, tr('Открываю «${e.name}»…', 'Opening "${e.name}"…'));
  final r = await pane.openFile(e);
  if (r != null && context.mounted) {
    toast(context, r == 'no-app' ? tr('Нет приложения для этого файла', 'No app can open this file') : r);
  }
}

class _RowTile extends StatelessWidget {
  final PaneController pane;
  final FsEntry e;
  final bool cols;
  const _RowTile({required this.pane, required this.e, required this.cols});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final sel = pane.selected.contains(e.path);
    final st = fileStyle(e);
    final big = e.isDir;
    return InkWell(
      onTap: () => _tapEntry(context, pane, e),
      onLongPress: () => pane.toggle(e),
      onSecondaryTap: () => pane.toggle(e),
      child: Container(
        color: sel ? t.accent.withValues(alpha: 0.14) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          SizedBox(
            width: 50,
            height: 50,
            child: Stack(clipBehavior: Clip.none, children: [
              Center(
                child: big
                    ? Icon(Icons.folder_rounded, size: 46, color: st.color, shadows: [Shadow(color: st.color.withValues(alpha: 0.5), blurRadius: 10)])
                    : _thumb(pane, e, 42, st),
              ),
              if (sel) Positioned(right: -2, bottom: -2, child: Icon(Icons.check_circle_rounded, size: 20, color: t.accent2)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.15)),
              const SizedBox(height: 2),
              e.isDir
                  ? _FolderSub(pane: pane, e: e)
                  : Text(fmtSize(e.size), maxLines: 1, style: TextStyle(fontSize: 12.5, color: t.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 84, child: Text(fmtDate(e.modified), textAlign: TextAlign.right, maxLines: 2, style: TextStyle(fontSize: 12, color: t.muted))),
        ]),
      ),
    );
  }
}

String _objects(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return tr('$n объект', '$n item');
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return tr('$n объекта', '$n items');
  return tr('$n объектов', '$n items');
}

final Map<String, int> _countCache = {};

/// Подпись папки: число объектов (считаем только на этом устройстве, лениво).
class _FolderSub extends StatelessWidget {
  final PaneController pane;
  final FsEntry e;
  const _FolderSub({required this.pane, required this.e});

  Future<int> _count() async {
    final c = _countCache[e.path];
    if (c != null) return c;
    var n = 0;
    try {
      await for (final _ in Directory(e.path).list(followLinks: false)) {
        if (++n >= 9999) break;
      }
    } catch (_) {
      n = -1;
    }
    _countCache[e.path] = n;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final style = TextStyle(fontSize: 12.5, color: t.muted);
    if (!pane.isLocal) return Text(tr('Папка', 'Folder'), style: style);
    return FutureBuilder<int>(
      future: _count(),
      builder: (_, snap) {
        final n = snap.data;
        return Text(n == null || n < 0 ? ' ' : _objects(n), maxLines: 1, style: style);
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  final PaneController pane;
  final FsEntry e;
  const _GridTile({required this.pane, required this.e});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final sel = pane.selected.contains(e.path);
    final st = fileStyle(e);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _tapEntry(context, pane, e),
      onLongPress: () => pane.toggle(e),
      onSecondaryTap: () => pane.toggle(e),
      child: Container(
        decoration: BoxDecoration(
          color: sel ? t.accent.withValues(alpha: 0.18) : t.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? t.accent : t.border),
        ),
        child: Stack(children: [
          Column(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(builder: (context, c) => Center(child: _thumbFill(pane, e, c.biggest, st))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(e.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ]),
          if (sel) Positioned(left: 6, top: 6, child: Icon(Icons.check_circle_rounded, size: 22, color: t.accent2)),
        ]),
      ),
    );
  }
}

/// Эскиз локальной картинки: берём готовый системный (быстро, мало памяти), а не декодируем всё фото.
class _LocalThumb extends StatefulWidget {
  final String path;
  final double width;
  final double height;
  final FileStyle st;
  final double iconSize;
  const _LocalThumb({required this.path, required this.width, required this.height, required this.st, required this.iconSize});

  @override
  State<_LocalThumb> createState() => _LocalThumbState();
}

class _LocalThumbState extends State<_LocalThumb> {
  late Future<Uint8List?> _f = Native.thumb(widget.path, size: 256);

  @override
  void didUpdateWidget(covariant _LocalThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _f = Native.thumb(widget.path, size: 256);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (_, snap) {
        final b = snap.data;
        if (b != null) return Image.memory(b, width: widget.width, height: widget.height, fit: BoxFit.cover, gaplessPlayback: true);
        if (snap.connectionState != ConnectionState.done) return SizedBox(width: widget.width, height: widget.height);
        return Image.file(File(widget.path),
            width: widget.width, height: widget.height, fit: BoxFit.cover, cacheWidth: 240, gaplessPlayback: true, errorBuilder: (_, __, ___) => Icon(st.icon, color: st.color, size: widget.iconSize));
      },
    );
  }
}

Widget _thumbFill(PaneController pane, FsEntry e, Size box, FileStyle st) {
  if (pane.isLocal && !e.isDir && _imgExt.contains(e.ext) && e.size < 40 * 1024 * 1024) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: _LocalThumb(path: e.path, width: box.width, height: box.height, st: st, iconSize: 46),
    );
  }
  if (!pane.isLocal && pane.vfs != null && !e.isDir && _imgExt.contains(e.ext) && e.size > 0 && e.size < 8 * 1024 * 1024) {
    return _RemoteImg(pane: pane, e: e, w: box.width, h: box.height, st: st, radius: 10);
  }
  return Icon(st.icon, color: st.color, size: 46);
}

class _StripChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  const _StripChip({required this.label, this.icon, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.accent.withValues(alpha: 0.2) : t.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? t.accent.withValues(alpha: 0.75) : t.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 17, color: selected ? t.accent2 : t.muted), const SizedBox(width: 7)],
            Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? t.text : t.text.withValues(alpha: 0.85))),
          ]),
        ),
      ),
    );
  }
}

class _Albums extends StatelessWidget {
  final PaneController pane;
  const _Albums({required this.pane});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final c = pane.cat!;
    final albums = pane.albums;
    if (pane.catLoading && albums.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(tr('Ищем файлы… найдено ${pane.catFound}', 'Scanning… found ${pane.catFound}'), style: TextStyle(color: t.muted)),
        ]),
      );
    }
    if (albums.isEmpty) {
      return Center(child: Text(tr('Ничего не найдено', 'Nothing found'), style: TextStyle(color: t.muted)));
    }
    return Column(children: [
      if (pane.catLoading)
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(tr('Обновляем… найдено ${pane.catFound}', 'Updating… found ${pane.catFound}'), style: TextStyle(color: t.muted, fontSize: 12)),
        ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.0),
          itemCount: albums.length,
          itemBuilder: (_, i) {
            final a = albums[i];
            final cover = a.cover;
            final isPhoto = c == Cat.photos && cover != null && _imgExt.contains(cover.split('.').last.toLowerCase());
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => pane.openAlbum(a),
              child: Container(
                decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.border)),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  if (isPhoto)
                    Image.file(File(cover!), fit: BoxFit.cover, cacheWidth: 360, errorBuilder: (_, __, ___) => const SizedBox.shrink())
                  else
                    Center(child: Icon(_catIcon(c), size: 54, color: t.accent2.withValues(alpha: 0.8))),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)])),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        Text('${a.count}', style: TextStyle(color: t.muted, fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  IconData _catIcon(Cat c) {
    switch (c) {
      case Cat.photos:
        return Icons.photo_library_rounded;
      case Cat.videos:
        return Icons.video_library_rounded;
      case Cat.audio:
        return Icons.library_music_rounded;
      case Cat.docs:
        return Icons.article_rounded;
    }
  }
}

class _Placeholder extends StatelessWidget {
  final PaneController pane;
  const _Placeholder({required this.pane});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final list = [s.self, ...s.sortedDevices];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.devices_rounded, size: 44, color: t.muted),
          const SizedBox(height: 10),
          Text(tr('Выберите устройство для этого окна', 'Pick a device for this window'), textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 14)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final d in list)
              SoftButton(
                label: d.isSelf ? tr('Это устройство', 'This device') : d.title,
                icon: kindIcon(d.kind),
                onTap: () async {
                  await connectFlow(context, s, pane, d);
                  if (pane.error != null && context.mounted) toast(context, pane.error!);
                },
              ),
          ]),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final PaneController pane;
  const _ErrorView({required this.pane});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final proto = protoOfPane(pane);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 44, color: t.muted),
          const SizedBox(height: 10),
          Text(pane.error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5)),
          const SizedBox(height: 6),
          Text(tr('NanoLink сам ищет устройство и переподключится, когда оно появится.', 'NanoLink keeps looking for the device and reconnects when it appears.'), textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 12.5)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            GradientButton(
              compact: true,
              label: tr('Повторить', 'Retry'),
              icon: Icons.refresh_rounded,
              onTap: () async {
                final f = pane.factory;
                if (f == null) return;
                final d = pane.dev;
                if (d != null) await s.heal(d);
                await pane.attach(f(), f, d);
              },
            ),
            if (pane.dev != null)
              for (final alt in s.protosOf(pane.dev!).where((x) => x != proto))
                SoftButton(
                  label: tr('Открыть по ${protoLabel(alt)}', 'Open via ${protoLabel(alt)}'),
                  icon: Icons.swap_horiz_rounded,
                  onTap: () => connectFlow(context, s, pane, pane.dev!, proto: alt),
                ),
            if (pane.dev != null)
              SoftButton(
                label: tr('Диагностика', 'Diagnostics'),
                icon: Icons.troubleshoot_rounded,
                onTap: () => showDiagnose(context, pane.dev!),
              ),
            if (proto != null && proto != 'nano' && pane.dev != null)
              SoftButton(
                label: tr('Логин и пароль', 'Login & password'),
                icon: Icons.key_rounded,
                onTap: () async {
                  final ok = await credsDialog(context, s, pane.dev!, proto);
                  final f = pane.factory;
                  if (ok && f != null) await pane.attach(f(), f, pane.dev);
                },
              ),
          ]),
        ]),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final PaneController pane;
  const _SelectionBar({required this.pane});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final n = pane.selected.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: t.surface2, border: Border(top: BorderSide(color: t.border))),
      child: Row(children: [
        Text(tr('Выбрано: $n', 'Selected: $n'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const Spacer(),
        IconBtn(icon: Icons.select_all_rounded, tip: tr('Выбрать всё', 'Select all'), onTap: pane.selectAll),
        IconBtn(
          icon: Icons.drive_file_rename_outline_rounded,
          tip: tr('Переименовать', 'Rename'),
          onTap: n == 1
              ? () async {
                  final e = pane.selectedEntries.first;
                  final name = await promptText(context, title: tr('Переименовать', 'Rename'), initial: e.name);
                  if (name == null || name.trim().isEmpty || name.trim() == e.name) return;
                  try {
                    await pane.renameSelected(name.trim());
                  } catch (err) {
                    if (context.mounted) toast(context, friendlyError(err));
                  }
                }
              : null,
        ),
        IconBtn(
          icon: Icons.delete_outline_rounded,
          tip: tr('Удалить', 'Delete'),
          onTap: () async {
            final ok = await confirmDialog(
              context,
              tr('Удалить выбранное?', 'Delete selected?'),
              tr('Будет удалено объектов: $n. Это нельзя отменить.', 'Items to delete: $n. This cannot be undone.'),
              okLabel: tr('Удалить', 'Delete'),
            );
            if (!ok) return;
            try {
              await pane.deleteSelected();
            } catch (err) {
              if (context.mounted) toast(context, friendlyError(err));
            }
          },
        ),
        IconBtn(icon: Icons.close_rounded, tip: tr('Снять выбор', 'Clear'), onTap: pane.clearSelection),
      ]),
    );
  }
}


/// Пока устройство отвечает: крутилка, секунды ожидания и подсказка, если долго.
class _Connecting extends StatefulWidget {
  final PaneController pane;
  const _Connecting({required this.pane});

  @override
  State<_Connecting> createState() => _ConnectingState();
}

class _ConnectingState extends State<_Connecting> {
  Timer? _tm;
  int _sec = 0;

  @override
  void initState() {
    super.initState();
    _tm = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _sec++);
    });
  }

  @override
  void dispose() {
    _tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final p = widget.pane;
    final proto = protoOfPane(p);
    final who = p.dev?.title ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text(
            tr('Подключаемся${who.isEmpty ? '' : ' к «$who»'}${proto == null ? '' : ' · ${protoLabel(proto)}'}…', 'Connecting${who.isEmpty ? '' : ' to "$who"'}${proto == null ? '' : ' · ${protoLabel(proto)}'}…'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(tr('$_sec с', '$_sec s'), style: TextStyle(color: t.muted)),
          if (_sec >= 10) ...[
            const SizedBox(height: 10),
            Text(
              tr('Отвечает долго. Роутеры и приставки бывают медленными - подождите ещё немного или нажмите «Назад» и выберите другой протокол.',
                  'Slow to answer. Routers and boxes can be slow - wait a little or go back and pick another protocol.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12.5),
            ),
          ],
        ]),
      ),
    );
  }
}

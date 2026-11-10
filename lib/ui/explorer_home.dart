import 'package:flutter/material.dart';

import '../core/category.dart';
import '../core/i18n.dart';
import '../core/pane.dart';
import '../core/platform.dart';
import '../core/util.dart';
import 'theme.dart';
import 'widgets.dart';

class _Tile {
  final IconData icon;
  final String label;
  final String sub;
  final List<Color> colors;
  final VoidCallback onTap;
  _Tile(this.icon, this.label, this.sub, this.colors, this.onTap);
}

/// Стартовый экран проводника: плитки разделов, как в файловых менеджерах.
class ExplorerHome extends StatefulWidget {
  final PaneController pane;
  const ExplorerHome({super.key, required this.pane});

  @override
  State<ExplorerHome> createState() => _ExplorerHomeState();
}

class _ExplorerHomeState extends State<ExplorerHome> {
  List<int>? _stats;

  @override
  void initState() {
    super.initState();
    if (widget.pane.isLocal) {
      Native.storageStats().then((v) {
        if (mounted) setState(() => _stats = v);
      });
    }
  }

  Future<void> _storage() async {
    final p = widget.pane;
    final path = await p.vfs!.start();
    await p.cd(path);
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final pane = widget.pane;
    final tiles = <_Tile>[];
    String? downloads;
    final others = <_Tile>[];
    for (final pl in pane.places) {
      if (pl.icon == 'downloads') {
        downloads = pl.path;
        continue;
      }
      others.add(_Tile(_placeIcon(pl.icon), pl.name, '', _placeColors(pl.icon), () => pane.cd(pl.path)));
    }
    if (downloads != null) {
      final d = downloads;
      tiles.add(_Tile(Icons.download_rounded, tr('Загрузки', 'Downloads'), '', const [Color(0xFF43A047), Color(0xFF1B5E20)], () => pane.cd(d)));
    }
    tiles.add(_Tile(Icons.photo_library_rounded, tr('Фото', 'Photos'), '', const [Color(0xFFEC407A), Color(0xFF880E4F)], () => pane.openCategory(Cat.photos)));
    tiles.add(_Tile(Icons.video_library_rounded, tr('Видео', 'Videos'), '', const [Color(0xFF8E24AA), Color(0xFF4A148C)], () => pane.openCategory(Cat.videos)));
    tiles.add(_Tile(Icons.library_music_rounded, tr('Аудио', 'Audio'), '', const [Color(0xFF00ACC1), Color(0xFF006064)], () => pane.openCategory(Cat.audio)));
    tiles.add(_Tile(Icons.article_rounded, tr('Документы', 'Documents'), '', const [Color(0xFF1E88E5), Color(0xFF0D47A1)], () => pane.openCategory(Cat.docs)));
    tiles.addAll(others);

    final st = _stats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        GlassCard(
          onTap: _storage,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE53935), Color(0xFF7F1D1D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.sd_storage_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Хранилище', 'Storage'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                if (st != null) ...[
                  Text('${fmtSize(st[0] - st[1])} / ${fmtSize(st[0])}', style: TextStyle(color: t.muted, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: st[0] > 0 ? (st[0] - st[1]) / st[0] : 0, minHeight: 6)),
                ] else
                  Text(tr('Открыть все папки', 'Open all folders'), style: TextStyle(color: t.muted, fontSize: 12.5)),
              ]),
            ),
            if (st != null)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('${((st[0] - st[1]) * 100 ~/ st[0])}%', style: TextStyle(color: t.accent2, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [for (final x in tiles) _HomeTile(tile: x)],
        ),
      ],
    );
  }

  IconData _placeIcon(String k) {
    switch (k) {
      case 'desktop':
        return Icons.desktop_windows_rounded;
      case 'documents':
        return Icons.description_rounded;
      case 'pictures':
        return Icons.image_rounded;
      case 'videos':
        return Icons.movie_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'storage':
        return Icons.storage_rounded;
    }
    return Icons.folder_rounded;
  }

  List<Color> _placeColors(String k) {
    switch (k) {
      case 'desktop':
        return const [Color(0xFF5C6BC0), Color(0xFF283593)];
      case 'documents':
        return const [Color(0xFF1E88E5), Color(0xFF0D47A1)];
      case 'pictures':
        return const [Color(0xFFEC407A), Color(0xFF880E4F)];
      case 'videos':
        return const [Color(0xFF8E24AA), Color(0xFF4A148C)];
      case 'music':
        return const [Color(0xFF00ACC1), Color(0xFF006064)];
    }
    return const [Color(0xFFFFB300), Color(0xFFE65100)];
  }
}

class _HomeTile extends StatelessWidget {
  final _Tile tile;
  const _HomeTile({required this.tile});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: tile.onTap,
        child: Ink(
          decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.border)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: tile.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: tile.colors.last.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Icon(tile.icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(tile.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

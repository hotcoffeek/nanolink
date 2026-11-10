import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/platform.dart';
import '../core/state.dart';
import '../core/transfer.dart';
import '../core/util.dart';
import 'pane_view.dart';
import 'widgets.dart';

class ExplorerPage extends StatelessWidget {
  const ExplorerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = NlScope.of(context);
        return LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 860;
          final pad = wide ? 18.0 : 8.0;
          final leftView = PaneView(key: ValueKey(s.left.id), pane: s.left);
          final rightView = PaneView(key: ValueKey(s.right.id), pane: s.right);
          final center = _CenterBar(s: s, vertical: wide);
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
            child: Column(children: [
              if (!s.allFilesOk) _PermissionBanner(s: s, t: t),
              Expanded(
                child: wide
                    ? Row(children: [
                        Expanded(child: leftView),
                        const SizedBox(width: 10),
                        center,
                        const SizedBox(width: 10),
                        Expanded(child: rightView),
                      ])
                    : Column(children: [
                        Expanded(child: leftView),
                        const SizedBox(height: 6),
                        center,
                        const SizedBox(height: 6),
                        Expanded(child: rightView),
                      ]),
              ),
              _TransferStrip(s: s),
            ]),
          );
        });
      },
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final AppState s;
  final dynamic t;
  const _PermissionBanner({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.folder_open_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('Чтобы видеть все файлы телефона, дайте доступ к памяти.', 'Grant storage access to see all files on the phone.'), style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 8),
          GradientButton(
            compact: true,
            label: tr('Разрешить', 'Allow'),
            onTap: () async {
              await Native.requestAllFiles();
              await delay(600);
              await s.checkAllFiles();
            },
          ),
        ]),
      ),
    );
  }
}

class _CenterBar extends StatelessWidget {
  final AppState s;
  final bool vertical;
  const _CenterBar({required this.s, required this.vertical});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final lc = s.left.selected.length;
    final rc = s.right.selected.length;

    Widget copyBtn(bool toRight) {
      final n = toRight ? lc : rc;
      final icon = vertical ? (toRight ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded) : (toRight ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);
      return Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              final err = toRight ? s.transferBetween(s.left, s.right, move: s.moveMode) : s.transferBetween(s.right, s.left, move: s.moveMode);
              if (err != null) toast(context, err);
            },
            child: Ink(
              width: 48,
              height: 44,
              decoration: BoxDecoration(
                gradient: n > 0 ? t.gradient : null,
                color: n > 0 ? null : t.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: n > 0 ? Colors.transparent : t.border),
                boxShadow: n > 0 ? [BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 14)] : null,
              ),
              child: Icon(icon, color: n > 0 ? Colors.white : t.muted),
            ),
          ),
        ),
      );
    }

    final swap = IconBtn(
      icon: vertical ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded,
      tip: tr('Поменять окна местами', 'Swap windows'),
      size: 24,
      onTap: s.swapPanes,
    );
    final move = Tooltip(
      message: tr('Режим: копировать / переместить', 'Mode: copy / move'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => s.setMoveMode(!s.moveMode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: s.moveMode ? t.accent.withValues(alpha: 0.2) : t.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: s.moveMode ? t.accent : t.border),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.moveMode ? Icons.drive_file_move_rounded : Icons.content_copy_rounded, size: 18, color: s.moveMode ? t.accent2 : t.muted),
            Text(s.moveMode ? tr('Перенос', 'Move') : tr('Копия', 'Copy'), style: TextStyle(fontSize: 10.5, color: t.muted, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );

    if (vertical) {
      return SizedBox(
        width: 64,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          copyBtn(true),
          const SizedBox(height: 10),
          copyBtn(false),
          const SizedBox(height: 14),
          swap,
          const SizedBox(height: 10),
          move,
        ]),
      );
    }
    return SizedBox(
      height: 52,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        copyBtn(true),
        const SizedBox(width: 12),
        copyBtn(false),
        const SizedBox(width: 12),
        swap,
        const SizedBox(width: 12),
        move,
      ]),
    );
  }
}

class _TransferStrip extends StatelessWidget {
  final AppState s;
  const _TransferStrip({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s.transfers,
      builder: (context, _) {
        final t = NlScope.of(context);
        final active = s.transfers.jobs.where((j) => j.active || j.state == TState.queued).toList();
        if (active.isEmpty) return const SizedBox.shrink();
        var total = 0;
        var done = 0;
        var speed = 0.0;
        var waiting = false;
        for (final j in active) {
          total += j.total;
          done += j.done;
          speed += j.speed;
          if (j.state == TState.waiting) waiting = true;
        }
        final p = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            radius: 16,
            onTap: () => s.setPage(2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Icon(waiting ? Icons.sync_problem_rounded : Icons.swap_vert_rounded, size: 18, color: waiting ? const Color(0xFFFFB020) : t.accent2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    waiting
                        ? tr('Связь потеряна - восстанавливаем и докачаем…', 'Connection lost - recovering and resuming…')
                        : tr('Передача: ${active.length} шт. · ${fmtSpeed(speed)}', 'Transferring: ${active.length} · ${fmtSpeed(speed)}'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(p == null ? '' : '${(p * 100).round()}%', style: TextStyle(color: t.muted, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: p, minHeight: 5)),
            ]),
          ),
        );
      },
    );
  }
}

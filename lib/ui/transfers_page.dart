import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/transfer.dart';
import '../core/util.dart';
import 'theme.dart';
import 'widgets.dart';

class TransfersPage extends StatelessWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final eng = s.transfers;
    return ListenableBuilder(
      listenable: eng,
      builder: (context, _) {
        final t = NlScope.of(context);
        final jobs = eng.jobs.reversed.toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(children: [
              Expanded(child: Text(tr('Передачи', 'Transfers'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              SoftButton(label: tr('Очистить завершённые', 'Clear finished'), icon: Icons.cleaning_services_rounded, onTap: jobs.any((j) => j.finished) ? eng.clearFinished : null),
            ]),
            const SizedBox(height: 14),
            if (jobs.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  Icon(Icons.swap_vert_circle_outlined, size: 46, color: t.muted),
                  const SizedBox(height: 10),
                  Text(
                    tr('Передач пока нет. В проводнике отметьте файлы и нажмите стрелку между окнами - или просто перетащите файлы в другое окно.',
                        'No transfers yet. Select files in the explorer and press the arrow between the windows - or just drag them to the other window.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted),
                  ),
                ]),
              ),
            for (final j in jobs) Padding(padding: const EdgeInsets.only(bottom: 10), child: _JobCard(j: j, eng: eng, t: t)),
          ],
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  final TransferJob j;
  final TransferEngine eng;
  final NlTheme t;
  const _JobCard({required this.j, required this.eng, required this.t});

  String _state() {
    switch (j.state) {
      case TState.queued:
        return tr('В очереди', 'Queued');
      case TState.running:
        return tr('Идёт передача', 'Transferring');
      case TState.waiting:
        return j.note ?? tr('Ждём связь…', 'Waiting for connection…');
      case TState.paused:
        return tr('Пауза', 'Paused');
      case TState.done:
        return j.note ?? tr('Готово', 'Done');
      case TState.failed:
        return j.error ?? tr('Ошибка', 'Failed');
      case TState.canceled:
        return tr('Отменено', 'Canceled');
    }
  }

  Color _color() {
    switch (j.state) {
      case TState.done:
        return const Color(0xFF3DDC84);
      case TState.failed:
        return const Color(0xFFFF4D5E);
      case TState.waiting:
        return const Color(0xFFFFB020);
      case TState.canceled:
      case TState.paused:
      case TState.queued:
        return t.muted;
      case TState.running:
        return t.accent2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fs = fileStyle0(j);
    final remaining = j.total - j.done;
    final eta = j.speed > 1 ? remaining / j.speed : double.nan;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(fs.icon, color: fs.color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j.targetName ?? j.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(_state(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _color(), fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (j.active) IconBtn(icon: Icons.pause_rounded, tip: tr('Пауза', 'Pause'), onTap: () => eng.pause(j)),
          if (j.state == TState.paused || j.state == TState.failed || j.state == TState.canceled)
            IconBtn(icon: Icons.play_arrow_rounded, tip: tr('Продолжить', 'Resume'), onTap: () => eng.resume(j)),
          if (!j.finished || j.state == TState.failed) IconBtn(icon: Icons.close_rounded, tip: tr('Отмена', 'Cancel'), onTap: () => eng.cancel(j)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: j.state == TState.queued ? 0 : (j.total > 0 ? j.progress : (j.state == TState.done ? 1 : null)),
            minHeight: 6,
            color: _color(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('${fmtSize(j.done)} / ${fmtSize(j.total)}', style: TextStyle(color: t.muted, fontSize: 12.5)),
          const Spacer(),
          if (j.state == TState.running && j.speed > 1)
            Text('${fmtSpeed(j.speed)} · ${fmtEta(eta)}', style: TextStyle(color: t.muted, fontSize: 12.5)),
          if (j.move) Padding(padding: const EdgeInsets.only(left: 8), child: Text(tr('перенос', 'move'), style: TextStyle(color: t.muted, fontSize: 12.5))),
        ]),
      ]),
    );
  }
}

FileStyle fileStyle0(TransferJob j) => fileStyle(j.entry);

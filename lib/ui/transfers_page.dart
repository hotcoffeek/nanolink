import 'dart:io';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/transfer.dart';
import '../core/util.dart';
import 'folder_pick.dart';
import 'phone.dart';
import 'theme.dart';
import 'widgets.dart';

class TransfersPage extends StatelessWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final eng = s.transfers;
    return ListenableBuilder(
      listenable: Listenable.merge([s, eng]),
      builder: (context, _) {
        final t = NlScope.of(context);
        final jobs = eng.jobs.reversed.toList();
        final incoming = s.incoming.values.toList();
        final hist = s.history.take(60).toList();
        Widget head(String text, {Widget? trailing}) => Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Row(children: [
                Expanded(child: Text(text, style: TextStyle(color: t.muted, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.9))),
                if (trailing != null) trailing,
              ]),
            );
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(children: [
              Expanded(child: Text(tr('Передачи', 'Transfers'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              SoftButton(label: tr('Очистить', 'Clear'), icon: Icons.cleaning_services_rounded, onTap: jobs.any((j) => j.finished) ? eng.clearFinished : null),
            ]),
            const SizedBox(height: 14),
            if (jobs.isEmpty && incoming.isEmpty && hist.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  Icon(Icons.swap_vert_circle_outlined, size: 46, color: t.muted),
                  const SizedBox(height: 10),
                  Text(
                    tr('Передач пока нет. Отправленное и полученное появится здесь.', 'No transfers yet. Everything sent and received shows up here.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted),
                  ),
                ]),
              ),
            if (incoming.isNotEmpty) ...[
              head(tr('ПОЛУЧАЮ', 'RECEIVING')),
              for (final i in incoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    borderColor: t.accent.withValues(alpha: 0.5),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.download_rounded, color: t.accent2, size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(i.total > 0 ? '${(i.done * 100 ~/ i.total).clamp(0, 100)}%' : '', style: TextStyle(color: t.accent2, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 2),
                      Text('${tr('от', 'from')} ${i.from} · ${fmtSize(i.done)} / ${fmtSize(i.total)}', style: TextStyle(color: t.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: i.total > 0 ? i.done / i.total : null, minHeight: 5)),
                    ]),
                  ),
                ),
            ],
            if (jobs.isNotEmpty) ...[
              head(tr('ОТПРАВКА И СКАЧИВАНИЕ', 'SENDING AND DOWNLOADING')),
              for (final j in jobs) Padding(padding: const EdgeInsets.only(bottom: 10), child: _JobCard(j: j, eng: eng, t: t)),
            ],
            if (hist.isNotEmpty) ...[
              head(
                tr('ИСТОРИЯ ПОЛУЧЕНИЯ', 'RECEIVED HISTORY'),
                trailing: IconBtn(icon: Icons.delete_sweep_rounded, tip: tr('Очистить историю', 'Clear history'), onTap: s.clearHistory),
              ),
              for (final h in hist) Padding(padding: const EdgeInsets.only(bottom: 8), child: _HistTile(h: h, s: s)),
            ],
          ],
        );
      },
    );
  }
}

class _HistTile extends StatelessWidget {
  final HistItem h;
  final AppState s;
  const _HistTile({required this.h, required this.s});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final exists = File(h.path).existsSync();
    final e = FsEntry(name: h.name, path: h.path, isDir: false, size: h.size);
    final st = fileStyle(e);
    final when = DateTime.fromMillisecondsSinceEpoch(h.at);
    final dir = h.path.contains('/') ? h.path.substring(0, h.path.lastIndexOf('/')) : h.path;
    return Opacity(
      opacity: exists ? 1 : 0.5,
      child: GlassCard(
        onTap: () {
          if (exists) {
            openReceived(context, h.path);
          } else {
            toast(context, tr('Файл удалён или перемещён', 'The file was deleted or moved'));
          }
        },
        padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: st.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(st.icon, color: st.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '${tr('от', 'from')} ${h.from} · ${fmtSize(h.size)} · ${fmtDate(when)}${exists ? '' : ' · ${tr('удалён', 'deleted')}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.muted, fontSize: 12),
              ),
            ]),
          ),
          if (exists) IconBtn(icon: Icons.folder_open_rounded, tip: tr('Показать в папке', 'Show in folder'), onTap: () => openFolderFlow(context, s, dir)),
          IconBtn(icon: Icons.close_rounded, tip: tr('Убрать из истории', 'Remove from history'), onTap: () => s.removeHistory(h)),
        ]),
      ),
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

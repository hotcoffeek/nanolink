import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'painters.dart';
import 'theme.dart';
import 'widgets.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = NlScope.of(context);
        final all = s.sortedDevices;
        final favs = all.where((d) => d.favorite).toList();
        final rest = all.where((d) => !d.favorite).toList();
        return LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 760;
          final pad = wide ? 28.0 : 14.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, wide ? 24 : 12, pad, 28),
            children: [
              _Banner(s: s, t: t, compact: !wide),
              const SizedBox(height: 16),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _ThisDevice(s: s, t: t)),
                  const SizedBox(width: 16),
                  Expanded(child: _AddDevice(s: s, t: t)),
                ])
              else ...[
                _ThisDevice(s: s, t: t),
                const SizedBox(height: 12),
                _AddDevice(s: s, t: t),
              ],
              if (favs.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionTitle(tr('Избранные', 'Favorites'), Icons.star_rounded, t),
                const SizedBox(height: 10),
                _Cards(devices: favs, width: c.maxWidth - pad * 2),
              ],
              const SizedBox(height: 22),
              _SectionTitle(tr('Устройства в сети', 'Devices on the network'), Icons.lan_rounded, t),
              const SizedBox(height: 10),
              if (rest.isEmpty && favs.isEmpty)
                GlassCard(
                  padding: const EdgeInsets.all(26),
                  child: Column(children: [
                    Icon(Icons.radar_rounded, size: 42, color: t.muted),
                    const SizedBox(height: 10),
                    Text(
                      s.netOnline
                          ? tr('Пока ничего не найдено. Откройте NanoLink на втором устройстве, или добавьте устройство по IP.', 'Nothing found yet. Open NanoLink on another device or add one by IP.')
                          : tr('Нет подключения к сети. Подключитесь к Wi-Fi - поиск запустится сам.', 'No network. Connect to Wi-Fi - the search starts automatically.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.muted),
                    ),
                  ]),
                )
              else
                _Cards(devices: rest, width: c.maxWidth - pad * 2),
            ],
          );
        });
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final IconData icon;
  final NlTheme t;
  const _SectionTitle(this.text, this.icon, this.t);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: t.accent2),
      const SizedBox(width: 8),
      Text(text.toUpperCase(), style: TextStyle(color: t.muted, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 0.8)),
    ]);
  }
}

class _Banner extends StatelessWidget {
  final AppState s;
  final NlTheme t;
  final bool compact;
  const _Banner({required this.s, required this.t, required this.compact});

  @override
  Widget build(BuildContext context) {
    final online = s.netOnline;
    final cnt = s.devices.where((d) => d.online).length;
    String title;
    String sub;
    if (!online) {
      title = tr('Нет связи с сетью…', 'No network…');
      sub = tr('Как только Wi-Fi вернётся, NanoLink сам найдёт устройства и восстановит соединения.', 'As soon as Wi-Fi returns, NanoLink finds devices and restores connections by itself.');
    } else if (s.scanning) {
      title = tr('Ищем устройства…', 'Searching for devices…');
      sub = tr('Проверяем сеть: SMB, FTP, SSH, NanoLink, ТВ и приставки.', 'Checking the network: SMB, FTP, SSH, NanoLink, TVs and boxes.');
    } else {
      title = tr('Сеть готова', 'Network ready');
      sub = tr('В сети: $cnt · ваш адрес: ${s.nics.isEmpty ? '-' : s.nics.first.ip}', 'Online: $cnt · your address: ${s.nics.isEmpty ? '-' : s.nics.first.ip}');
    }
    return Container(
      height: compact ? 118 : 138,
      padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: t.border),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [t.accent.withValues(alpha: 0.38), t.surface, t.accent2.withValues(alpha: 0.22)],
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: compact ? 22 : 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text.withValues(alpha: 0.75), fontSize: compact ? 12.5 : 14)),
          ]),
        ),
        GlobeWidget(size: compact ? 96 : 124, a: t.accent, b: t.accent2),
      ]),
    );
  }
}

class _ThisDevice extends StatelessWidget {
  final AppState s;
  final NlTheme t;
  const _ThisDevice({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    final ips = s.nics.map((e) => e.ip).join('  ·  ');
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('ЭТО УСТРОЙСТВО', 'THIS DEVICE'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        Row(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(gradient: t.gradient, borderRadius: BorderRadius.circular(16)),
            child: Icon(kindIcon(s.myKind == DeviceKind.unknown ? DeviceKind.pc : s.myKind), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.myName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(ips.isEmpty ? tr('нет сети', 'no network') : ips, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted)),
            ]),
          ),
          IconBtn(
            icon: Icons.edit_rounded,
            tip: tr('Переименовать', 'Rename'),
            onTap: () async {
              final n = await promptText(context, title: tr('Имя этого устройства', 'Name of this device'), initial: s.myName);
              if (n != null) s.setDeviceName(n);
            },
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          PulseDot(color: s.server.running ? const Color(0xFF3DDC84) : const Color(0xFFFFB020)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.server.running
                  ? tr('Готов принимать подключения (порт $kPeerPort)', 'Ready for connections (port $kPeerPort)')
                  : (s.serverError != null
                      ? tr('Не удалось открыть порт $kPeerPort - возможно, он занят', 'Could not open port $kPeerPort - maybe it is in use')
                      : tr('Приём подключений выключен', 'Incoming connections are off')),
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _AddDevice extends StatefulWidget {
  final AppState s;
  final NlTheme t;
  const _AddDevice({required this.s, required this.t});

  @override
  State<_AddDevice> createState() => _AddDeviceState();
}

class _AddDeviceState extends State<_AddDevice> {
  final TextEditingController _ip = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await widget.s.addManual(_ip.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      toast(context, r);
    } else {
      _ip.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final t = widget.t;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('ДОБАВИТЬ УСТРОЙСТВО', 'ADD A DEVICE'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        TextField(
          controller: _ip,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(hintText: tr('IP или Tailscale 100.x, например 100.64.1.5', 'IP or Tailscale 100.x, e.g. 100.64.1.5'), prefixIcon: const Icon(Icons.lan_outlined)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: GradientButton(label: _busy ? tr('Проверяем…', 'Checking…') : tr('Добавить', 'Add'), icon: Icons.add_link_rounded, onTap: _busy ? null : _add)),
          const SizedBox(width: 10),
          Expanded(
            child: SoftButton(
              label: s.scanning ? '${(s.scanProgress * 100).round()}%' : tr('Сканировать сеть', 'Scan network'),
              icon: Icons.radar_rounded,
              onTap: s.scanning ? null : s.scan,
            ),
          ),
        ]),
        if (s.scanning) ...[
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: s.scanProgress == 0 ? null : s.scanProgress, minHeight: 4)),
        ],
      ]),
    );
  }
}

class _Cards extends StatelessWidget {
  final List<Device> devices;
  final double width;
  const _Cards({required this.devices, required this.width});

  @override
  Widget build(BuildContext context) {
    final cols = width >= 1000 ? 3 : (width >= 640 ? 2 : 1);
    final w = (width - (cols - 1) * 14) / cols;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [for (final d in devices) SizedBox(width: w, child: _DeviceCard(d: d))],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device d;
  const _DeviceCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final protos = s.protosOf(d);
    final online = d.online;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderColor: d.favorite ? t.accent.withValues(alpha: 0.45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(15), border: Border.all(color: t.border)),
              child: Icon(kindIcon(d.kind), color: online ? t.accent2 : t.muted, size: 26),
            ),
            Positioned(right: -2, bottom: -2, child: PulseDot(color: online ? const Color(0xFF3DDC84) : const Color(0xFFFF4D5E), size: 12)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${kindLabel(d.kind)} · ${d.host ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
            ]),
          ),
          IconBtn(
            icon: d.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            active: d.favorite,
            tip: tr('В избранное', 'Favorite'),
            onTap: () {
              d.favorite = !d.favorite;
              s.updateDevice(d);
            },
          ),
          IconBtn(icon: Icons.tune_rounded, tip: tr('Настроить', 'Edit'), onTap: () => editDeviceDialog(context, s, d)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in protos) _Chip(protoLabel(p), p == 'nano' ? t.accent : t.muted, t),
          if (protos.isEmpty) _Chip(tr('нет протоколов', 'no protocols'), t.muted, t),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: SoftButton(
              label: tr('Слева', 'Left'),
              icon: Icons.west_rounded,
              onTap: () => _open(context, s, true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SoftButton(
              label: tr('Справа', 'Right'),
              icon: Icons.east_rounded,
              onTap: () => _open(context, s, false),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _open(BuildContext context, AppState s, bool leftSide) async {
    final pane = leftSide ? s.left : s.right;
    s.setPage(1);
    await connectFlow(context, s, pane, d);
    if (pane.error != null && context.mounted) toast(context, pane.error!);
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final NlTheme t;
  const _Chip(this.text, this.color, this.t);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

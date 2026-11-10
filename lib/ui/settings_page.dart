import 'dart:io';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/platform.dart';
import '../core/state.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = NlScope.of(context);
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(tr('Настройки', 'Settings'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _Card(
              title: tr('ВНЕШНИЙ ВИД', 'APPEARANCE'),
              t: t,
              child: Wrap(spacing: 12, runSpacing: 12, children: [
                for (final th in kThemes) _ThemeTile(th: th, selected: th.id == s.settings.theme, onTap: () => s.setTheme(th.id)),
              ]),
            ),
            const SizedBox(height: 14),
            _Card(
              title: tr('ЯЗЫК', 'LANGUAGE'),
              t: t,
              child: Row(children: [
                SoftButton(label: 'Русский', selected: s.settings.lang != 'en', onTap: () => s.setLang('ru')),
                const SizedBox(width: 8),
                SoftButton(label: 'English', selected: s.settings.lang == 'en', onTap: () => s.setLang('en')),
              ]),
            ),
            const SizedBox(height: 14),
            _Card(
              title: tr('ЭТО УСТРОЙСТВО', 'THIS DEVICE'),
              t: t,
              child: Column(children: [
                _Row(
                  title: tr('Имя устройства', 'Device name'),
                  subtitle: s.myName,
                  trailing: IconBtn(
                    icon: Icons.edit_rounded,
                    onTap: () async {
                      final n = await promptText(context, title: tr('Имя этого устройства', 'Name of this device'), initial: s.myName);
                      if (n != null) s.setDeviceName(n);
                    },
                  ),
                ),
                _Row(
                  title: tr('Принимать подключения', 'Accept connections'),
                  subtitle: tr('Другие ваши устройства смогут открывать файлы этого', 'Your other devices can browse files here'),
                  trailing: Switch(value: s.settings.serverOn, onChanged: s.setServerOn),
                ),
                _Row(
                  title: tr('Разрешить запись и удаление', 'Allow write and delete'),
                  subtitle: tr('Если выключить - другие устройства смогут только читать', 'When off, other devices can only read'),
                  trailing: Switch(value: s.settings.allowWrite, onChanged: s.setAllowWrite),
                ),
                _Row(
                  title: tr('Если файл уже существует', 'If the file already exists'),
                  subtitle: tr('Что делать при совпадении имён', 'What to do on a name clash'),
                  trailing: DropdownButton<String>(
                    value: s.settings.conflict,
                    underline: const SizedBox.shrink(),
                    dropdownColor: t.surface2,
                    items: [
                      DropdownMenuItem(value: 'rename', child: Text(tr('Оставить оба', 'Keep both'))),
                      DropdownMenuItem(value: 'overwrite', child: Text(tr('Заменить', 'Replace'))),
                      DropdownMenuItem(value: 'skip', child: Text(tr('Пропустить', 'Skip'))),
                    ],
                    onChanged: (v) => s.setConflict(v ?? 'rename'),
                  ),
                ),
              ]),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 14),
              _Card(
                title: 'ANDROID',
                t: t,
                child: Column(children: [
                  _Row(
                    title: tr('Прямая сеть в обход VPN', 'Direct network, bypass VPN'),
                    subtitle: tr('Соединения с устройствами идут по Wi-Fi, даже если включён VPN', 'Device connections go over Wi-Fi even when a VPN is on'),
                    trailing: Switch(value: s.settings.bindWifi, onChanged: s.setBindWifi),
                  ),
                  _Row(
                    title: tr('Доступ ко всем файлам', 'All files access'),
                    subtitle: s.allFilesOk ? tr('Выдан', 'Granted') : tr('Не выдан - проводник увидит не всё', 'Not granted - explorer will miss files'),
                    trailing: s.allFilesOk
                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF3DDC84))
                        : SoftButton(
                            label: tr('Выдать', 'Grant'),
                            onTap: () async {
                              await Native.requestAllFiles();
                            },
                          ),
                  ),
                  _Row(
                    title: tr('Не усыплять в фоне', 'Keep running in background'),
                    subtitle: tr('Рекомендуется: отключите оптимизацию батареи для NanoLink, чтобы связь не рвалась при выключенном экране', 'Recommended: disable battery optimization so links survive a locked screen'),
                    trailing: SoftButton(label: tr('Открыть', 'Open'), onTap: Native.requestBatteryExemption),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            _Card(
              title: tr('СЕТЬ', 'NETWORK'),
              t: t,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  s.nics.isEmpty ? tr('Нет активного Wi-Fi / Ethernet', 'No active Wi-Fi / Ethernet') : s.nics.map((e) => '${e.name}: ${e.ip}').join('\n'),
                  style: TextStyle(color: t.muted, height: 1.5),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('Порты NanoLink: TCP $kPeerPort и UDP $kDiscoPort. При первом запуске на ПК разрешите доступ в брандмауэре Windows (частная сеть).',
                      'NanoLink ports: TCP $kPeerPort and UDP $kDiscoPort. On first launch on a PC allow it in Windows Firewall (private network).'),
                  style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('Как NanoLink держит связь: соединения привязываются к реальному Wi-Fi/Ethernet-адаптеру (VPN в сторону не влияет), недокачанные файлы лежат как *.nlpart и докачиваются с того же байта, а при обрыве сеть сканируется заново, чтобы найти устройство по MAC/имени/портам.',
                      'How NanoLink stays connected: sockets are bound to the real Wi-Fi/Ethernet adapter (VPN is bypassed), unfinished files are kept as *.nlpart and resumed from the same byte, and after a drop the network is rescanned to find the device by MAC / name / ports.'),
                  style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Center(child: Text('NanoLink 1.0', style: TextStyle(color: t.muted, fontSize: 12))),
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final NlTheme t;
  final Widget child;
  const _Card({required this.title, required this.t, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: t.muted, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;
  const _Row({required this.title, required this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: t.muted, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(width: 10),
        trailing,
      ]),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final NlTheme th;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeTile({required this.th, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 148,
        height: 92,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? th.accent2 : Colors.white.withValues(alpha: 0.1), width: selected ? 2 : 1),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [th.bg, th.surface2, th.accent.withValues(alpha: 0.55)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, gradient: th.gradient)),
            const SizedBox(width: 6),
            if (th.bgStyle == Bg.rain) const Icon(Icons.grain_rounded, size: 14, color: Colors.white70),
            const Spacer(),
            if (selected) Icon(Icons.check_circle_rounded, size: 18, color: th.accent2),
          ]),
          Text(th.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white)),
        ]),
      ),
    );
  }
}

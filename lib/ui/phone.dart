import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/category.dart';
import '../core/i18n.dart';
import '../core/local_vfs.dart';
import '../core/models.dart';
import '../core/pane.dart';
import '../core/platform.dart';
import '../core/state.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'folder_pick.dart';
import 'pane_view.dart';
import 'painters.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'transfers_page.dart';
import 'widgets.dart';

/// Главный экран на телефоне: минимализм в духе LocalSend.
/// Главная / Получить / Отправить / Передачи / Настройки. Файлы чужих устройств открываются отдельным экраном.
class PhoneHome extends StatefulWidget {
  const PhoneHome({super.key});

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  static const int tabHome = 0, tabRecv = 1, tabSend = 2, tabTransfers = 3, tabSettings = 4;
  int _tab = tabHome;
  final List<int> _hist = []; // стек вкладок для жеста «назад»
  AppState? _s;
  int _recvSeen = 0;
  final GlobalKey<SendPageState> _sendKey = GlobalKey<SendPageState>();

  void _go(int i) {
    if (i == _tab) return;
    setState(() {
      _hist.add(_tab);
      if (_hist.length > 20) _hist.removeAt(0);
      _tab = i;
    });
  }

  void _back() {
    if (_tab == tabSend && (_sendKey.currentState?.clearSelection() ?? false)) return;
    if (_hist.isNotEmpty) {
      setState(() => _tab = _hist.removeLast());
    } else if (_tab != tabHome) {
      setState(() => _tab = tabHome);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s == null) {
      _s = AppScope.of(context);
      _recvSeen = _s!.receivedTick;
      _s!.addListener(_onState);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _s!.pullShared();
        _onState();
      });
    }
  }

  @override
  void dispose() {
    _s?.removeListener(_onState);
    super.dispose();
  }

  // Диалог «Принять файл?» показывает Shell - здесь его открывать нельзя, иначе окон будет два.
  void _onState() {
    final s = _s;
    if (s == null || !mounted) return;
    if (s.pendingShare.isNotEmpty) {
      final items = List<FsEntry>.from(s.pendingShare);
      s.pendingShare.clear();
      _go(tabSend);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendKey.currentState?.addEntries(items);
        if (mounted) toast(context, tr('Выберите устройство для отправки', 'Pick a device to send to'));
      });
    }
    if (s.receivedTick != _recvSeen) {
      _recvSeen = s.receivedTick;
      final f = s.lastFile;
      if (f != null && _tab != tabRecv) {
        final name = f.substring(f.lastIndexOf('/') + 1);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Получено от ${s.lastFrom ?? ''}: $name', 'Received from ${s.lastFrom ?? ''}: $name')),
          action: SnackBarAction(label: tr('Открыть', 'Open'), onPressed: () => openReceived(context, f)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Column(children: [
        Expanded(
          // Скрытые вкладки не крутят анимации (пульс радара и т.п.): на слабых телефонах это заметно экономит кадры
          child: IndexedStack(index: _tab, children: [
            TickerMode(enabled: _tab == tabHome, child: HomePage(onGoSend: () => _go(tabSend))),
            TickerMode(enabled: _tab == tabRecv, child: const ReceivePage()),
            TickerMode(enabled: _tab == tabSend, child: SendPage(key: _sendKey, onSent: () => _go(tabTransfers))),
            TickerMode(enabled: _tab == tabTransfers, child: const TransfersPage()),
            TickerMode(enabled: _tab == tabSettings, child: const SettingsPage()),
          ]),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([s, s.transfers]),
          builder: (context, _) {
            final items = [
              (Icons.home_rounded, tr('Главная', 'Home'), 0),
              (Icons.wifi_tethering_rounded, tr('Получить', 'Receive'), s.incoming.length),
              (Icons.send_rounded, tr('Отправить', 'Send'), 0),
              (Icons.swap_vert_rounded, tr('Передачи', 'Transfers'), s.transfers.activeCount),
              (Icons.settings_rounded, tr('Настройки', 'Settings'), 0),
            ];
            return Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: t.border)),
              child: Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _go(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                        decoration: BoxDecoration(
                          gradient: _tab == i ? t.gradient : null,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Badge(
                            isLabelVisible: items[i].$3 > 0,
                            label: Text('${items[i].$3}'),
                            child: Icon(items[i].$1, size: 22, color: _tab == i ? Colors.white : t.muted),
                          ),
                          const SizedBox(height: 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(items[i].$2, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _tab == i ? Colors.white : t.muted)),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
      ]),
    );
  }
}

Future<void> openReceived(BuildContext context, String path) async {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1);
  final ok = await Native.openFile(path, PaneController.mimeOf(ext));
  if (!ok && context.mounted) toast(context, tr('Нет приложения для этого файла', 'No app can open this file'));
}

Future<bool?> openBrowse(BuildContext context, Device d, {List<FsEntry>? send, String? proto, bool ask = false}) {
  return Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BrowsePage(device: d, sendItems: send, proto: proto, ask: ask)));
}

/// Меню устройства (долгое нажатие).
void showDeviceSheet(
  BuildContext context,
  Device d, {
  List<FsEntry> sel = const [],
  required Future<void> Function({List<FsEntry>? send, String? proto, bool ask}) browse,
}) {
  final s = AppScope.of(context);
  final t = NlScope.of(context);
  final protos = s.protosOf(d);
  final dest = s.destFor(d);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.surface2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Row(children: [
              Icon(kindIcon(d.kind), color: t.accent2),
              const SizedBox(width: 12),
              Expanded(child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(tr('Открыть файлы', 'Browse files')),
            onTap: () {
              Navigator.pop(sheet);
              browse();
            },
          ),
          if (sel.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_rounded),
              title: Text(tr('Отправить в другую папку…', 'Send to another folder…')),
              subtitle: Text(tr('Можно запомнить как папку по умолчанию', 'Can be remembered as the default folder')),
              onTap: () {
                Navigator.pop(sheet);
                browse(send: sel);
              },
            ),
          if (protos.length > 1)
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(tr('Открыть по другому протоколу…', 'Open with another protocol…')),
              subtitle: Text(protos.map(protoLabel).join(' · ')),
              onTap: () {
                Navigator.pop(sheet);
                browse(ask: true);
              },
            ),
          if (!d.isSelf)
            ListTile(
              leading: const Icon(Icons.troubleshoot_rounded),
              title: Text(tr('Диагностика подключения', 'Connection diagnostics')),
              subtitle: Text(tr('Проверит порты, FTP и SMB и покажет ответы устройства', 'Checks ports, FTP and SMB and shows the device replies')),
              onTap: () {
                Navigator.pop(sheet);
                showDiagnose(context, d);
              },
            ),
          if (dest.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: Text(tr('Сбросить папку по умолчанию', 'Reset default folder')),
              subtitle: Text('$dest → ${tr('Рабочий стол', 'Desktop')}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(sheet);
                s.clearDest(d.id);
              },
            ),
          ListTile(
            leading: Icon(d.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: d.favorite ? const Color(0xFFFFC940) : null),
            title: Text(d.favorite ? tr('Убрать из избранного', 'Remove from favorites') : tr('В избранное', 'Add to favorites')),
            onTap: () {
              Navigator.pop(sheet);
              d.favorite = !d.favorite;
              s.updateDevice(d);
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: Text(tr('Переименовать, порт и логин', 'Rename, port and login')),
            onTap: () {
              Navigator.pop(sheet);
              editDeviceDialog(context, s, d);
            },
          ),
          if (d.host != null)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('Скопировать адрес ${d.host}', 'Copy address ${d.host}')),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: d.host!));
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

/// Вкладка «Главная»: поиск устройств, ручное подключение, список всех устройств.
class HomePage extends StatelessWidget {
  final VoidCallback onGoSend;
  const HomePage({super.key, required this.onGoSend});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = NlScope.of(context);
        final devs = s.others;
        final favs = devs.where((d) => d.favorite).toList();
        final rest = devs.where((d) => !d.favorite).toList();
        final ip = s.nics.isEmpty ? null : s.nics.first.ip;
        Widget tile(Device d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DevTile(
                d: d,
                armed: false,
                onTap: () => openBrowse(context, d),
                onLong: () => showDeviceSheet(context, d, browse: ({List<FsEntry>? send, String? proto, bool ask = false}) => openBrowse(context, d, send: send, proto: proto, ask: ask)),
                onBrowse: () => openBrowse(context, d),
              ),
            );
        return RefreshIndicator(
          onRefresh: s.rescan,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              GlassCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(children: [
                  GlobeWidget(size: 54, a: t.accent, b: t.accent2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.myName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        !s.netOnline
                            ? tr('Нет Wi-Fi', 'No Wi-Fi')
                            : (s.settings.serverOn ? tr('Видно другим${ip == null ? '' : ' · $ip'}', 'Visible to others${ip == null ? '' : ' · $ip'}') : tr('Приём выключен', 'Receiving is off')),
                        style: TextStyle(color: s.netOnline && s.settings.serverOn ? const Color(0xFF3DDC84) : t.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  Switch(value: s.settings.serverOn, onChanged: s.setServerOn),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _BigAction(
                    icon: Icons.radar_rounded,
                    label: s.scanning ? tr('Ищем… ${(s.scanProgress * 100).round()}%', 'Scanning… ${(s.scanProgress * 100).round()}%') : tr('Сканировать', 'Scan'),
                    primary: true,
                    onTap: s.scanning ? null : s.rescan,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigAction(
                    icon: Icons.add_link_rounded,
                    label: tr('Вручную', 'Manually'),
                    onTap: () => showManualAddSheet(context, s, onOpen: (d, proto) => openBrowse(context, d, proto: proto)),
                  ),
                ),
              ]),
              if (s.scanning) ...[
                const SizedBox(height: 10),
                ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: s.scanProgress == 0 ? null : s.scanProgress, minHeight: 4)),
              ],
              if (!s.allFilesOk) ...[
                const SizedBox(height: 14),
                _PermCard(s: s),
              ],
              const SizedBox(height: 18),
              if (favs.isNotEmpty) ...[
                Text(tr('ИЗБРАННОЕ', 'FAVORITES'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.9)),
                const SizedBox(height: 8),
                for (final d in favs) tile(d),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Text(tr('УСТРОЙСТВА', 'DEVICES'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.9)),
                const Spacer(),
                Text(tr('в сети: ${devs.where((d) => d.online).length}', 'online: ${devs.where((d) => d.online).length}'), style: TextStyle(color: t.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              if (devs.isEmpty)
                GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(children: [
                    Icon(Icons.radar_rounded, size: 40, color: t.muted),
                    const SizedBox(height: 10),
                    Text(
                      s.netOnline
                          ? tr('Пока никого нет. Нажмите «Сканировать» или подключитесь вручную по IP: роутер, приставка, ПК.', 'Nobody yet. Tap "Scan" or connect manually by IP: router, set-top box, PC.')
                          : tr('Нет подключения к сети. Включите Wi-Fi - поиск начнётся сам.', 'No network. Turn on Wi-Fi - the search starts by itself.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.muted),
                    ),
                  ]),
                )
              else
                for (final d in rest) tile(d),
              if (devs.isNotEmpty && rest.isEmpty && favs.isNotEmpty) const SizedBox.shrink(),
            ],
          ),
        );
      },
    );
  }
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  const _BigAction({required this.icon, required this.label, this.primary = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final fg = primary ? Colors.white : t.text;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: primary ? t.gradient : null,
              color: primary ? null : t.surface,
              borderRadius: BorderRadius.circular(18),
              border: primary ? null : Border.all(color: t.border),
              boxShadow: primary ? [BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))] : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 21, color: primary ? Colors.white : t.accent2),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: fg)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Вкладка «Получить»: большая пульсирующая иконка устройства и список принятых файлов.
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  List<FsEntry> _files = const [];
  List<FsEntry> _all = const [];
  final Set<String> _pick = {};
  String _dir = '';
  AppState? _s;
  int _seen = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s == null) {
      _s = AppScope.of(context);
      _s!.addListener(_check);
      _reload();
    }
  }

  void _check() {
    final s = _s;
    if (s != null && s.receivedTick != _seen) _reload();
  }

  Future<void> _reload() async {
    final s = _s;
    if (s == null) return;
    _seen = s.receivedTick;
    try {
      final dir = await s.localInbox();
      final l = await LocalVfs().list(dir);
      final files = l.where((e) => !e.isDir && !e.name.endsWith('.nlpart')).toList()
        ..sort((a, b) => (b.modified?.millisecondsSinceEpoch ?? 0).compareTo(a.modified?.millisecondsSinceEpoch ?? 0));
      if (!mounted) return;
      setState(() {
        _dir = dir;
        _all = files;
        _files = files.take(30).toList();
        _pick.removeWhere((p) => !files.any((e) => e.path == p));
      });
    } catch (_) {}
  }

  String get _dirName => _dir.isEmpty ? '' : _dir.substring(_dir.lastIndexOf('/') + 1);

  Future<void> _deleteMany(List<String> paths) async {
    final s = _s;
    if (s == null) return;
    for (final p in paths) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    s.forgetPaths(paths.toSet());
    _pick.clear();
    await _reload();
  }

  Future<void> _deleteSelected() async {
    final n = _pick.length;
    final ok = await confirmDialog(context, tr('Удалить выбранное?', 'Delete selected?'), tr('Файлов: $n. Это нельзя отменить.', 'Files: $n. This cannot be undone.'), okLabel: tr('Удалить', 'Delete'));
    if (ok) await _deleteMany(_pick.toList());
  }

  /// «Очистить»: в папке NanoLink удаляем всё, в чужой папке (например Загрузки) - только то, что принял NanoLink.
  Future<void> _clearAll() async {
    final s = _s;
    if (s == null || _all.isEmpty) return;
    final known = s.history.map((h) => h.path).toSet();
    final ownFolder = _dirName.toLowerCase() == 'nanolink';
    final victims = _all.where((e) => ownFolder || known.contains(e.path)).map((e) => e.path).toList();
    if (victims.isEmpty) {
      toast(context, tr('Здесь нет файлов, принятых через NanoLink', 'No files received through NanoLink here'));
      return;
    }
    final ok = await confirmDialog(
      context,
      tr('Очистить полученное?', 'Clear received files?'),
      tr('Будет удалено файлов: ${victims.length}\nПапка: $_dir${ownFolder ? '' : '\nУдаляются только файлы, принятые через NanoLink.'}\nЭто нельзя отменить.',
          'Files to delete: ${victims.length}\nFolder: $_dir${ownFolder ? '' : '\nOnly files received through NanoLink are removed.'}\nThis cannot be undone.'),
      okLabel: tr('Удалить', 'Delete'),
    );
    if (ok) await _deleteMany(victims);
  }

  @override
  void dispose() {
    _s?.removeListener(_check);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final on = s.settings.serverOn && s.netOnline;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final ip = s.nics.isEmpty ? null : s.nics.first.ip;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (s.scanning) {
                    toast(context, tr('Уже ищем…', 'Already scanning…'));
                    return;
                  }
                  toast(context, tr('Ищем устройства заново…', 'Searching for devices again…'));
                  s.rescan();
                },
                child: SizedBox(
                  height: 230,
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (_, __) => CustomPaint(
                      painter: _PulsePainter(_anim.value, on ? t.accent2 : t.muted, on),
                      child: Center(
                        child: s.scanning
                            ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                            : Icon(Icons.wifi_tethering_rounded, size: 54, color: on ? Colors.white : t.muted),
                      ),
                    ),
                  ),
                ),
              ),
              Center(child: Text(s.scanning ? tr('Идёт поиск…', 'Searching…') : tr('Нажмите на круг, чтобы искать заново', 'Tap the circle to search again'), style: TextStyle(color: t.muted, fontSize: 12))),
              Center(child: Text(s.myName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300))),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  !s.netOnline
                      ? tr('Нет Wi-Fi', 'No Wi-Fi')
                      : (s.settings.serverOn ? '${ip ?? ''}  ·  ${tr('видно другим', 'visible to others')}' : tr('Приём выключен', 'Receiving is off')),
                  style: TextStyle(color: on ? const Color(0xFF3DDC84) : t.muted, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Switch(value: s.settings.serverOn, onChanged: s.setServerOn)),
              const SizedBox(height: 18),
              if (s.others.any((d) => d.online)) ...[
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  for (final d in s.others.where((d) => d.online))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: d.has('nano') ? t.accent.withValues(alpha: 0.7) : t.border)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(kindIcon(d.kind), size: 16, color: t.accent2),
                        const SizedBox(width: 6),
                        Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (d.has('nano')) ...[const SizedBox(width: 6), Icon(Icons.bolt_rounded, size: 14, color: t.accent2)],
                      ]),
                    ),
                ]),
                const SizedBox(height: 18),
              ],
              if (s.incoming.isNotEmpty) ...[
                Text(tr('ПОЛУЧАЮ', 'RECEIVING'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.9)),
                const SizedBox(height: 8),
                for (final i in s.incoming.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassCard(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      borderColor: t.accent.withValues(alpha: 0.5),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
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
                const SizedBox(height: 10),
              ],
              Row(children: [
                Expanded(
                  child: Text(tr('ПОЛУЧЕННЫЕ ФАЙЛЫ · ${_all.length}', 'RECEIVED FILES · ${_all.length}'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.9)),
                ),
                IconBtn(icon: Icons.refresh_rounded, tip: tr('Обновить', 'Refresh'), onTap: _reload),
              ]),
              const SizedBox(height: 6),
              if (_dir.isNotEmpty)
                GlassCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.folder_rounded, color: t.accent2, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('Файлы лежат в папке', 'Files are stored in'), style: TextStyle(color: t.muted, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(_dir, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: SoftButton(label: tr('Открыть папку', 'Open folder'), icon: Icons.folder_open_rounded, onTap: () => openFolderFlow(context, s, _dir))),
                      const SizedBox(width: 8),
                      Expanded(child: SoftButton(label: tr('Очистить…', 'Clear…'), icon: Icons.delete_sweep_rounded, onTap: _all.isEmpty ? null : _clearAll)),
                    ]),
                  ]),
                ),
              const SizedBox(height: 8),
              if (_pick.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                    borderColor: t.accent.withValues(alpha: 0.6),
                    child: Row(children: [
                      Expanded(child: Text(tr('Выбрано: ${_pick.length}', 'Selected: ${_pick.length}'), style: const TextStyle(fontWeight: FontWeight.w800))),
                      TextButton(
                        onPressed: () => setState(() {
                          if (_pick.length == _files.length) {
                            _pick.clear();
                          } else {
                            _pick
                              ..clear()
                              ..addAll(_files.map((e) => e.path));
                          }
                        }),
                        child: Text(tr('Все', 'All')),
                      ),
                      IconBtn(icon: Icons.delete_outline_rounded, tip: tr('Удалить', 'Delete'), onTap: _deleteSelected),
                      IconBtn(icon: Icons.close_rounded, tip: tr('Отмена', 'Cancel'), onTap: () => setState(_pick.clear)),
                    ]),
                  ),
                ),
              if (_files.isEmpty)
                GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    tr('Пока ничего не получено. Когда вам отправят файлы, они появятся здесь.', 'Nothing received yet. Files sent to you will show up here.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted),
                  ),
                )
              else ...[
                for (final e in _files)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecvTile(
                      e: e,
                      selected: _pick.contains(e.path),
                      selecting: _pick.isNotEmpty,
                      onOpen: () {
                        if (_pick.isNotEmpty) {
                          setState(() => _pick.contains(e.path) ? _pick.remove(e.path) : _pick.add(e.path));
                        } else {
                          openReceived(context, e.path);
                        }
                      },
                      onLong: () => setState(() => _pick.contains(e.path) ? _pick.remove(e.path) : _pick.add(e.path)),
                      onDelete: () async {
                        final ok = await confirmDialog(context, tr('Удалить файл?', 'Delete file?'), e.name, okLabel: tr('Удалить', 'Delete'));
                        if (ok) await _deleteMany([e.path]);
                      },
                    ),
                  ),
                if (_all.length > _files.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('Показаны последние ${_files.length} из ${_all.length}. Остальные - в папке.', 'Showing the latest ${_files.length} of ${_all.length}. The rest are in the folder.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecvTile extends StatelessWidget {
  final FsEntry e;
  final bool selected;
  final bool selecting;
  final VoidCallback onOpen;
  final VoidCallback onLong;
  final VoidCallback onDelete;
  const _RecvTile({required this.e, required this.selected, required this.selecting, required this.onOpen, required this.onLong, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final st = fileStyle(e);
    return GestureDetector(
      onLongPress: onLong,
      child: GlassCard(
        onTap: onOpen,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        borderColor: selected ? t.accent2 : null,
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: st.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(st.icon, color: st.color),
            ),
            if (selected) Positioned(right: -4, bottom: -4, child: Icon(Icons.check_circle_rounded, size: 20, color: t.accent2)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${fmtSize(e.size)} · ${fmtDate(e.modified)}', style: TextStyle(color: t.muted, fontSize: 12)),
            ]),
          ),
          if (!selecting) IconBtn(icon: Icons.delete_outline_rounded, tip: tr('Удалить', 'Delete'), onTap: onDelete) else const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double v;
  final Color color;
  final bool on;
  _PulsePainter(this.v, this.color, this.on);

  @override
  void paint(Canvas c, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = 54.0;
    if (on) {
      for (var i = 0; i < 3; i++) {
        final k = (v + i / 3) % 1.0;
        final r = base + k * 80;
        c.drawCircle(center, r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = color.withValues(alpha: (1 - k) * 0.55));
      }
    }
    c.drawCircle(center, base, Paint()..color = on ? color.withValues(alpha: 0.9) : color.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant _PulsePainter o) => o.v != v || o.on != on || o.color != color;
}

enum PickKind { files, photos, videos, folder }

class SendPage extends StatefulWidget {
  final VoidCallback onSent;
  const SendPage({super.key, required this.onSent});

  @override
  State<SendPage> createState() => SendPageState();
}

class SendPageState extends State<SendPage> {
  final List<FsEntry> _sel = [];

  void addEntries(List<FsEntry> r) {
    setState(() {
      for (final e in r) {
        if (!_sel.any((x) => x.path == e.path)) _sel.add(e);
      }
    });
  }

  Future<void> _addText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final dir = Directory('${(await getTemporaryDirectory()).path}/nl_text');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final f = File('${dir.path}/text_${two(n.hour)}${two(n.minute)}${two(n.second)}.txt');
    await f.writeAsString(t);
    final e = entryOfPath(f.path);
    if (e != null && mounted) addEntries([e]);
  }

  Future<void> _textDialog() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr('Текст', 'Text')),
        content: SizedBox(width: 360, child: TextField(controller: c, autofocus: true, minLines: 3, maxLines: 8, decoration: InputDecoration(hintText: tr('Введите текст для отправки', 'Type the text to send')))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('Отмена', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dctx, c.text), child: Text(tr('Добавить', 'Add'))),
        ],
      ),
    );
    if (r != null) await _addText(r);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    final t = d?.text ?? '';
    if (t.trim().isEmpty) {
      if (mounted) toast(context, tr('Буфер обмена пуст', 'Clipboard is empty'));
      return;
    }
    await _addText(t);
  }

  int get _bytes => _sel.fold<int>(0, (a, e) => a + (e.isDir ? 0 : e.size));

  Future<void> _pick(PickKind k) async {
    final media = Platform.isAndroid && (k == PickKind.photos || k == PickKind.videos);
    final r = await Navigator.of(context).push<List<FsEntry>>(MaterialPageRoute(builder: (_) => media ? MediaPickerPage(video: k == PickKind.videos) : PickerPage(kind: k)));
    if (r == null || r.isEmpty || !mounted) return;
    setState(() {
      for (final e in r) {
        if (!_sel.any((x) => x.path == e.path)) _sel.add(e);
      }
    });
  }

  bool get hasSelection => _sel.isNotEmpty;

  String _destLabel(AppState s, Device d) {
    final p = s.destFor(d);
    if (p.isEmpty) return tr('Рабочий стол', 'Desktop');
    final n = p.substring(p.lastIndexOf(RegExp(r'[\\/]')) + 1);
    return n.isEmpty ? p : n;
  }

  /// Снять выбор (для жеста «назад»). true - выбор был и снят.
  bool clearSelection() {
    if (_sel.isEmpty) return false;
    setState(_sel.clear);
    return true;
  }

  Future<void> _browse(Device d, {List<FsEntry>? send, String? proto, bool ask = false}) async {
    final r = await openBrowse(context, d, send: send, proto: proto, ask: ask);
    if (r == true && mounted) {
      setState(_sel.clear);
      widget.onSent();
    }
  }

  Future<void> _tap(Device d) async {
    final s = AppScope.of(context);
    if (_sel.isEmpty) {
      await _browse(d);
      return;
    }
    final items = List<FsEntry>.from(_sel);
    if (!d.has('nano')) {
      await _browse(d, send: items);
      return;
    }
    // По умолчанию - сразу в запомненную папку или на «Рабочий стол» без вопросов.
    final err = await s.sendFiles(d, items);
    if (!mounted) return;
    if (err == null) {
      final dest = s.lastSendDest;
      final name = dest.substring(dest.lastIndexOf(RegExp(r'[\\/]')) + 1);
      toast(context, tr('Отправляем на «${d.title}» → ${name.isEmpty ? dest : name}', 'Sending to "${d.title}" → ${name.isEmpty ? dest : name}'));
      setState(_sel.clear);
      widget.onSent();
    } else if (err == 'pick') {
      await _browse(d, send: items);
    } else {
      toast(context, err);
    }
  }

  void _menu(Device d) {
    showDeviceSheet(
      context,
      d,
      sel: List<FsEntry>.from(_sel),
      browse: ({List<FsEntry>? send, String? proto, bool ask = false}) => _browse(d, send: send, proto: proto, ask: ask),
    );
  }

  void _addSheet() {
    final s = AppScope.of(context);
    showManualAddSheet(context, s, onOpen: (d, proto) {
      if (mounted) _browse(d, proto: proto);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = NlScope.of(context);
        final devs = s.others;
        final ip = s.nics.isEmpty ? null : s.nics.first.ip;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            // Это устройство
            GlassCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(children: [
                GlobeWidget(size: 54, a: t.accent, b: t.accent2),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.myName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      !s.netOnline
                          ? tr('Нет Wi-Fi', 'No Wi-Fi')
                          : (s.settings.serverOn ? tr('Видно другим${ip == null ? '' : ' · $ip'}', 'Visible to others${ip == null ? '' : ' · $ip'}') : tr('Приём выключен', 'Receiving is off')),
                      style: TextStyle(color: s.netOnline && s.settings.serverOn ? const Color(0xFF3DDC84) : t.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
                Switch(value: s.settings.serverOn, onChanged: s.setServerOn),
              ]),
            ),
            const SizedBox(height: 14),
            if (!s.allFilesOk) ...[
              _PermCard(s: s),
              const SizedBox(height: 14),
            ],
            // Что отправить
            Row(children: [
              _PickTile(icon: Icons.insert_drive_file_rounded, label: tr('Файлы', 'Files'), onTap: () => _pick(PickKind.files)),
              const SizedBox(width: 8),
              _PickTile(icon: Icons.photo_library_rounded, label: tr('Фото', 'Photos'), onTap: () => _pick(PickKind.photos)),
              const SizedBox(width: 8),
              _PickTile(icon: Icons.video_library_rounded, label: tr('Видео', 'Videos'), onTap: () => _pick(PickKind.videos)),
              const SizedBox(width: 8),
              _PickTile(icon: Icons.folder_rounded, label: tr('Папка', 'Folder'), onTap: () => _pick(PickKind.folder)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _PickTile(icon: Icons.notes_rounded, label: tr('Текст', 'Text'), onTap: _textDialog),
              const SizedBox(width: 8),
              _PickTile(icon: Icons.content_paste_rounded, label: tr('Вставить', 'Paste'), onTap: _paste),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ]),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _sel.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        borderColor: t.accent.withValues(alpha: 0.5),
                        child: Row(children: [
                          Icon(Icons.check_circle_rounded, color: t.accent2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(tr('Выбрано: ${_sel.length}', 'Selected: ${_sel.length}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(
                                _bytes > 0 ? '${fmtSize(_bytes)} · ${tr('нажмите на устройство ниже', 'tap a device below')}' : tr('нажмите на устройство ниже', 'tap a device below'),
                                style: TextStyle(color: t.muted, fontSize: 12),
                              ),
                            ]),
                          ),
                          IconBtn(icon: Icons.close_rounded, tip: tr('Сбросить', 'Clear'), onTap: () => setState(_sel.clear)),
                        ]),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            // Рядом
            Row(children: [
              Text(tr('РЯДОМ', 'NEARBY'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.9)),
              const SizedBox(width: 8),
              if (s.scanning)
                SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, value: s.scanProgress == 0 ? null : s.scanProgress)),
              const Spacer(),
              IconBtn(icon: Icons.refresh_rounded, tip: tr('Искать заново', 'Rescan'), onTap: s.scanning ? null : s.scan),
              IconBtn(icon: Icons.add_rounded, tip: tr('Добавить по адресу', 'Add by address'), onTap: _addSheet),
            ]),
            const SizedBox(height: 4),
            if (devs.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(22),
                child: Column(children: [
                  Icon(Icons.radar_rounded, size: 40, color: t.muted),
                  const SizedBox(height: 10),
                  Text(
                    s.netOnline
                        ? tr('Пока никого нет. Откройте NanoLink на другом устройстве в этой же сети или добавьте его по адресу (кнопка «+»).', 'Nobody yet. Open NanoLink on another device on this network or add it by address (the "+" button).')
                        : tr('Нет подключения к сети. Включите Wi-Fi - поиск начнётся сам.', 'No network. Turn on Wi-Fi - the search starts by itself.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted),
                  ),
                ]),
              )
            else
              for (final d in devs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DevTile(
                    d: d,
                    armed: _sel.isNotEmpty,
                    dest: _sel.isNotEmpty && d.has('nano') ? _destLabel(s, d) : null,
                    onTap: () => _tap(d),
                    onLong: () => _menu(d),
                    onBrowse: () => _browse(d),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.border)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 26, color: t.accent2),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DevTile extends StatelessWidget {
  final Device d;
  final bool armed;
  final String? dest;
  final VoidCallback onTap;
  final VoidCallback onLong;
  final VoidCallback onBrowse;
  const _DevTile({required this.d, required this.armed, this.dest, required this.onTap, required this.onLong, required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final online = d.online;
    return Opacity(
      opacity: online ? 1 : 0.55,
      child: GestureDetector(
        onLongPress: onLong,
        child: GlassCard(
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          borderColor: armed && online ? t.accent.withValues(alpha: 0.55) : (d.favorite ? t.accent.withValues(alpha: 0.3) : null),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(15), border: Border.all(color: t.border)),
                child: Icon(kindIcon(d.kind), color: online ? t.accent2 : t.muted, size: 25),
              ),
              Positioned(right: -2, bottom: -2, child: PulseDot(color: online ? const Color(0xFF3DDC84) : const Color(0xFFFF4D5E), size: 11)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  '${kindLabel(d.kind)} · ${d.host ?? '-'}${s.protosOf(d).contains('nano') ? '' : ' · ${s.protosOf(d).map(protoLabel).join('/')}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.muted, fontSize: 12),
                ),
                if (armed && online && dest != null)
                  Text('→ $dest', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.accent2, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (armed && online)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.send_rounded, color: t.accent2, size: 22),
              )
            else ...[
              IconBtn(
                icon: d.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                active: d.favorite,
                tip: tr('В избранное', 'Favorite'),
                onTap: () {
                  d.favorite = !d.favorite;
                  s.updateDevice(d);
                },
              ),
              IconBtn(icon: Icons.folder_open_rounded, tip: tr('Файлы', 'Files'), onTap: onBrowse),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Выбор файлов на этом телефоне.
class PickerPage extends StatefulWidget {
  final PickKind kind;
  const PickerPage({super.key, required this.kind});

  @override
  State<PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<PickerPage> {
  final PaneController pane = PaneController('pick');

  @override
  void dispose() {
    pane.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    pane.pickMode = true;
    pane.homeEnabled = widget.kind == PickKind.files;
    pane.grid = widget.kind == PickKind.photos || widget.kind == PickKind.videos;
    pane.attach(LocalVfs(), () => LocalVfs(), null).then((_) {
      if (!mounted) return;
      if (widget.kind == PickKind.photos) pane.openCategory(Cat.photos);
      if (widget.kind == PickKind.videos) pane.openCategory(Cat.videos);
    });
  }

  String get _title {
    switch (widget.kind) {
      case PickKind.photos:
        return tr('Фото', 'Photos');
      case PickKind.videos:
        return tr('Видео', 'Videos');
      case PickKind.folder:
        return tr('Выберите папки', 'Pick folders');
      case PickKind.files:
        return tr('Выберите файлы', 'Pick files');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!pane.back()) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          ListenableBuilder(
            listenable: pane,
            builder: (ctx, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                IconBtn(icon: pane.gridNow ? Icons.view_list_rounded : Icons.grid_view_rounded, tip: tr('Вид', 'View'), onTap: pane.toggleView),
                homeButton(ctx),
              ]),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: AppScope.of(context),
          builder: (context, _) {
            final s = AppScope.of(context);
            if (Platform.isAndroid && !s.allFilesOk) {
              return _Gate(
                icon: Icons.folder_open_rounded,
                text: tr('Чтобы выбирать файлы и папки, разрешите NanoLink доступ к файлам. Откроется системный экран - включите переключатель и вернитесь назад.',
                    'To pick files and folders allow NanoLink to access files. A system screen opens - switch it on and come back.'),
                button: tr('Разрешить доступ к файлам', 'Allow file access'),
                onTap: () => Native.requestAllFiles(),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: PaneView(pane: pane, hideHeader: true, hideSelBar: true, hideCats: true),
            );
          },
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: pane,
        builder: (context, _) {
          final n = pane.selected.length;
          if (n == 0) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: tr('Готово · $n', 'Done · $n'),
                  icon: Icons.check_rounded,
                  onTap: () => Navigator.pop(context, pane.selectedEntries),
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// Файлы другого устройства. Если передан [sendItems] - выбираем папку, куда отправить.
class BrowsePage extends StatefulWidget {
  final Device device;
  final List<FsEntry>? sendItems;
  final String? proto;
  final bool ask;
  const BrowsePage({super.key, required this.device, this.sendItems, this.proto, this.ask = false});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  late final PaneController pane = PaneController('br${widget.device.id}')..homeEnabled = true;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = AppScope.of(context);
      await connectFlow(context, s, pane, widget.device, proto: widget.proto, ask: widget.ask);
      if (!mounted) return;
      if (pane.error != null) toast(context, pane.error!);
      if (!pane.attached) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    pane.vfs?.close();
    pane.dispose();
    super.dispose();
  }

  Future<void> _sendHere() async {
    final s = AppScope.of(context);
    final items = widget.sendItems!;
    if (pane.isVirtualRoot) {
      toast(context, tr('Откройте папку назначения', 'Open a destination folder first'));
      return;
    }
    if (_remember) s.setDest(widget.device, pane.path);
    s.transfers.enqueue(
      srcFactory: () => LocalVfs(),
      dstFactory: pane.factory!,
      srcDev: null,
      dstDev: widget.device,
      items: items,
      dstDir: pane.path,
      move: false,
      conflict: s.settings.conflict,
    );
    Navigator.pop(context, true);
  }

  Future<void> _download() async {
    final s = AppScope.of(context);
    final items = pane.selectedEntries;
    if (items.isEmpty) return;
    final t = NlScope.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(alignment: Alignment.centerLeft, child: Text(tr('Куда сохранить на этом устройстве?', 'Where to save on this device?'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ),
          ListTile(
            leading: Icon(Icons.bolt_rounded, color: t.accent2),
            title: Text(tr('Папка приёма', 'Receive folder')),
            subtitle: Text(s.settings.inboxDir.isEmpty ? 'Загрузки/NanoLink' : s.settings.inboxDir),
            onTap: () => Navigator.pop(sheet, 'quick'),
          ),
          ListTile(
            leading: Icon(Icons.folder_open_rounded, color: t.accent2),
            title: Text(tr('Выбрать другую папку…', 'Choose another folder…')),
            onTap: () => Navigator.pop(sheet, 'pick'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    String dir;
    if (choice == 'pick') {
      final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => FolderPickPage(title: tr('Куда скачать', 'Where to download'))));
      if (r == null) return;
      dir = r;
    } else {
      dir = await s.localInbox();
    }
    s.transfers.enqueue(
      srcFactory: pane.factory!,
      dstFactory: () => LocalVfs(),
      srcDev: widget.device,
      dstDev: null,
      items: items,
      dstDir: dir,
      move: false,
      conflict: s.settings.conflict,
    );
    pane.clearSelection();
    if (mounted) toast(context, tr('Скачиваем в $dir - смотрите вкладку «Передачи»', 'Downloading to $dir - see the Transfers tab'));
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final send = widget.sendItems;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!pane.back()) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          backgroundColor: t.bg,
          elevation: 0,
          title: ListenableBuilder(
            listenable: pane,
            builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.device.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(
                pane.attached && pane.error == null && pane.entries.isNotEmpty
                    ? tr('Файлы этого устройства · подключено', "This device's files · connected")
                    : tr('Файлы этого устройства', "This device's files"),
                style: TextStyle(color: pane.attached && pane.error == null && pane.entries.isNotEmpty ? const Color(0xFF3DDC84) : NlScope.of(context).muted, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
          actions: [
            ListenableBuilder(
              listenable: pane,
              builder: (ctx, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                IconBtn(icon: pane.gridNow ? Icons.view_list_rounded : Icons.grid_view_rounded, tip: tr('Вид', 'View'), onTap: pane.toggleView),
                homeButton(ctx),
              ]),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: PaneView(pane: pane, hideHeader: true, hideSelBar: true),
          ),
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: pane,
          builder: (context, _) {
            if (send != null) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _remember = !_remember),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false), visualDensity: VisualDensity.compact),
                          Expanded(
                            child: Text(
                              tr('Запомнить эту папку для «${widget.device.title}»', 'Remember this folder for "${widget.device.title}"'),
                              style: TextStyle(color: t.muted, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        label: tr('Отправить сюда · ${send.length}', 'Send here · ${send.length}'),
                        icon: Icons.send_rounded,
                        onTap: pane.attached && !pane.home ? _sendHere : null,
                      ),
                    ),
                  ]),
                ),
              );
            }
            final n = pane.selected.length;
            if (n == 0) return const SizedBox.shrink();
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
                decoration: BoxDecoration(color: t.surface2, border: Border(top: BorderSide(color: t.border))),
                child: Row(children: [
                  Text(tr('Выбрано: $n', 'Selected: $n'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconBtn(
                    icon: Icons.delete_outline_rounded,
                    tip: tr('Удалить', 'Delete'),
                    onTap: () async {
                      final ok = await confirmDialog(context, tr('Удалить выбранное?', 'Delete selected?'), tr('Будет удалено объектов: $n. Это нельзя отменить.', 'Items to delete: $n. This cannot be undone.'), okLabel: tr('Удалить', 'Delete'));
                      if (!ok) return;
                      try {
                        await pane.deleteSelected();
                      } catch (err) {
                        if (context.mounted) toast(context, friendlyError(err));
                      }
                    },
                  ),
                  IconBtn(icon: Icons.close_rounded, tip: tr('Снять выбор', 'Clear'), onTap: pane.clearSelection),
                  // Скачивать «на телефон» имеет смысл только с чужого устройства
                  if (!pane.isLocal) ...[
                    const SizedBox(width: 4),
                    GradientButton(compact: true, label: tr('Скачать', 'Download'), icon: Icons.download_rounded, onTap: _download),
                  ],
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  final IconData icon;
  final String text;
  final String button;
  final VoidCallback onTap;
  final String? second;
  final VoidCallback? onSecond;
  const _Gate({required this.icon, required this.text, required this.button, required this.onTap, this.second, this.onSecond});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 54, color: t.accent2),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 14.5, height: 1.35)),
          const SizedBox(height: 20),
          GradientButton(label: button, icon: Icons.lock_open_rounded, onTap: onTap),
          if (second != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onSecond, child: Text(second!)),
          ],
        ]),
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  final AppState s;
  const _PermCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      borderColor: const Color(0xFFFFB020).withValues(alpha: 0.6),
      child: Row(children: [
        const Icon(Icons.shield_outlined, color: Color(0xFFFFB020)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Нужен доступ к файлам', 'File access needed'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(tr('Чтобы принимать и отправлять файлы', 'To receive and send files'), style: TextStyle(color: t.muted, fontSize: 12)),
          ]),
        ),
        GradientButton(compact: true, label: tr('Разрешить', 'Allow'), onTap: () => Native.requestAllFiles()),
      ]),
    );
  }
}

class _MItem {
  final String path;
  final int size;
  final DateTime modified;
  final String bucket;
  _MItem(this.path, this.size, this.modified, this.bucket);
  String get name => path.substring(path.lastIndexOf('/') + 1);
}

/// Галерея фото/видео телефона: быстрый запрос к MediaStore, выбор тапом, без галочек.
class MediaPickerPage extends StatefulWidget {
  final bool video;
  const MediaPickerPage({super.key, required this.video});

  @override
  State<MediaPickerPage> createState() => _MediaPickerPageState();
}

class _MediaPickerPageState extends State<MediaPickerPage> {
  bool _loading = true;
  bool _denied = false;
  List<_MItem> _all = const [];
  final Map<String, int> _buckets = {};
  String? _bucket; // null = все
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
    });
    final ok = await Native.ensureMedia();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }
    final raw = await Native.queryMedia(widget.video ? 'video' : 'images');
    if (!mounted) return;
    final items = <_MItem>[];
    _buckets.clear();
    for (final m in raw ?? const <Map<String, dynamic>>[]) {
      final p = (m['p'] ?? '').toString();
      if (p.isEmpty) continue;
      final b = (m['b'] ?? '').toString();
      items.add(_MItem(p, (m['s'] as num?)?.toInt() ?? 0, DateTime.fromMillisecondsSinceEpoch((m['m'] as num?)?.toInt() ?? 0), b));
      _buckets[b] = (_buckets[b] ?? 0) + 1;
    }
    setState(() {
      _all = items;
      _loading = false;
    });
  }

  List<_MItem> get _view => _bucket == null ? _all : _all.where((e) => e.bucket == _bucket).toList();

  void _done() {
    final res = <FsEntry>[];
    for (final e in _all) {
      if (_sel.contains(e.path)) res.add(FsEntry(name: e.name, path: e.path, isDir: false, size: e.size, modified: e.modified));
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final s = AppScope.of(context);
    final listMode = s.settings.pickList;
    final view = _view;
    final names = _buckets.keys.toList()..sort((a, b) => _buckets[b]!.compareTo(_buckets[a]!));
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text(widget.video ? tr('Видео', 'Videos') : tr('Фото', 'Photos'), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (!_loading && view.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                final all = view.every((e) => _sel.contains(e.path));
                for (final e in view) {
                  all ? _sel.remove(e.path) : _sel.add(e.path);
                }
              }),
              child: Text(tr('Выбрать все', 'Select all')),
            ),
          IconBtn(
            icon: listMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
            tip: listMode ? tr('Плитки', 'Grid') : tr('Список с размером и датой', 'List with size and date'),
            size: 24,
            onTap: () => s.setPickList(!listMode),
          ),
          homeButton(context),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _denied
                ? _Gate(
                    icon: widget.video ? Icons.video_library_rounded : Icons.photo_library_rounded,
                    text: tr('Чтобы показать галерею, разрешите NanoLink доступ к фото и видео.', 'To show the gallery allow NanoLink to access photos and videos.'),
                    button: tr('Разрешить', 'Allow'),
                    onTap: _load,
                    second: tr('Открыть настройки приложения', 'Open app settings'),
                    onSecond: Native.openAppSettings,
                  )
                : Column(children: [
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        children: [
                          _Bucket(label: tr('Все', 'All'), count: _all.length, selected: _bucket == null, onTap: () => setState(() => _bucket = null)),
                          for (final n in names)
                            _Bucket(label: n.isEmpty ? '-' : n, count: _buckets[n]!, selected: _bucket == n, onTap: () => setState(() => _bucket = n)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: view.isEmpty
                          ? Center(child: Text(widget.video ? tr('Видео не найдено', 'No videos found') : tr('Фото не найдены', 'No photos found'), style: TextStyle(color: t.muted)))
                          : listMode
                              ? ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                  itemCount: view.length,
                                  itemExtent: 72,
                                  addAutomaticKeepAlives: false,
                                  itemBuilder: (_, i) {
                                    final e = view[i];
                                    final on = _sel.contains(e.path);
                                    return _MListRow(
                                      key: ValueKey(e.path),
                                      item: e,
                                      video: widget.video,
                                      selected: on,
                                      onTap: () => setState(() => on ? _sel.remove(e.path) : _sel.add(e.path)),
                                    );
                                  },
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 4, crossAxisSpacing: 4),
                                  itemCount: view.length,
                                  addAutomaticKeepAlives: false,
                                  itemBuilder: (_, i) {
                                    final e = view[i];
                                    final on = _sel.contains(e.path);
                                    return RepaintBoundary(
                                      key: ValueKey(e.path),
                                      child: GestureDetector(
                                        onTap: () => setState(() => on ? _sel.remove(e.path) : _sel.add(e.path)),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Stack(fit: StackFit.expand, children: [
                                            _Thumb(path: e.path, video: widget.video),
                                            // размер и дата прямо на плитке
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                                                decoration: const BoxDecoration(
                                                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)]),
                                                ),
                                                child: Text(
                                                  '${fmtSize(e.size)} · ${_shortDate(e.modified)}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                                                ),
                                              ),
                                            ),
                                            if (on) Container(color: t.accent.withValues(alpha: 0.35)),
                                            if (on) Positioned(right: 6, top: 6, child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 24, shadows: [Shadow(color: t.accent, blurRadius: 8)])),
                                            if (widget.video) const Positioned(left: 6, top: 6, child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 22)),
                                            if (on) DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.accent2, width: 3))),
                                          ]),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ]),
      ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: GradientButton(label: tr('Готово · ${_sel.length}', 'Done · ${_sel.length}'), icon: Icons.check_rounded, onTap: _done),
                ),
              ),
            ),
    );
  }
}

String _shortDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year % 100}';
}

/// Строка списка: эскиз, имя, размер, дата и папка.
class _MListRow extends StatelessWidget {
  final _MItem item;
  final bool video;
  final bool selected;
  final VoidCallback onTap;
  const _MListRow({super.key, required this.item, required this.video, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: selected ? t.accent.withValues(alpha: 0.18) : t.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? t.accent2 : t.border, width: selected ? 2 : 1),
              ),
              child: Row(children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Stack(fit: StackFit.expand, children: [
                      _Thumb(path: item.path, video: video),
                      if (video) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 22)),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
                    const SizedBox(height: 3),
                    Text('${fmtSize(item.size)}  ·  ${fmtDate(item.modified)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.muted)),
                    if (item.bucket.isNotEmpty) Text(item.bucket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: t.muted.withValues(alpha: 0.8))),
                  ]),
                ),
                const SizedBox(width: 8),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? t.accent2 : t.muted, size: 26),
                const SizedBox(width: 6),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bucket extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _Bucket({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? t.accent.withValues(alpha: 0.22) : t.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? t.accent.withValues(alpha: 0.8) : t.border),
            ),
            child: Text('$label · $count', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? t.text : t.muted)),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatefulWidget {
  final String path;
  final bool video;
  const _Thumb({required this.path, required this.video});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late Future<Uint8List?> _f = Native.thumb(widget.path, size: 256);

  @override
  void didUpdateWidget(covariant _Thumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _f = Native.thumb(widget.path, size: 256);
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (_, snap) {
        final b = snap.data;
        if (b != null) return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
        if (snap.connectionState != ConnectionState.done) return Container(color: t.surface2);
        // системный эскиз недоступен (старый Android) - читаем сам файл в уменьшенном виде
        if (!widget.video) {
          return Image.file(File(widget.path), fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true, errorBuilder: (_, __, ___) => Container(color: t.surface2));
        }
        return Container(color: t.surface2, child: Icon(Icons.movie_rounded, color: t.muted));
      },
    );
  }
}

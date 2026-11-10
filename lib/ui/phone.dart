import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/category.dart';
import '../core/i18n.dart';
import '../core/local_vfs.dart';
import '../core/models.dart';
import '../core/pane.dart';
import '../core/state.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'pane_view.dart';
import 'painters.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'transfers_page.dart';
import 'widgets.dart';

/// Главный экран на телефоне: минимализм в духе LocalSend.
/// Отправить / Передачи / Настройки. Файлы чужих устройств открываются отдельным экраном.
class PhoneHome extends StatefulWidget {
  const PhoneHome({super.key});

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    return Column(children: [
      Expanded(
        child: IndexedStack(index: _tab, children: [
          SendPage(onSent: () => setState(() => _tab = 1)),
          const TransfersPage(),
          const SettingsPage(),
        ]),
      ),
      ListenableBuilder(
        listenable: Listenable.merge([s, s.transfers]),
        builder: (context, _) {
          final items = [
            (Icons.send_rounded, tr('Отправить', 'Send'), 0),
            (Icons.swap_vert_rounded, tr('Передачи', 'Transfers'), s.transfers.activeCount),
            (Icons.settings_rounded, tr('Настройки', 'Settings'), 0),
          ];
          return Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: t.border)),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 10),
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
                        Text(items[i].$2, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _tab == i ? Colors.white : t.muted)),
                      ]),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    ]);
  }
}

enum PickKind { files, photos, videos, folder }

class SendPage extends StatefulWidget {
  final VoidCallback onSent;
  const SendPage({super.key, required this.onSent});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final List<FsEntry> _sel = [];

  int get _bytes => _sel.fold<int>(0, (a, e) => a + (e.isDir ? 0 : e.size));

  Future<void> _pick(PickKind k) async {
    final r = await Navigator.of(context).push<List<FsEntry>>(MaterialPageRoute(builder: (_) => PickerPage(kind: k)));
    if (r == null || r.isEmpty || !mounted) return;
    setState(() {
      for (final e in r) {
        if (!_sel.any((x) => x.path == e.path)) _sel.add(e);
      }
    });
  }

  Future<void> _browse(Device d, {List<FsEntry>? send}) async {
    final r = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BrowsePage(device: d, sendItems: send)));
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
    toast(context, tr('Отправляем на «${d.title}»…', 'Sending to "${d.title}"…'));
    final err = await s.sendFiles(d, items);
    if (!mounted) return;
    if (err == null) {
      setState(_sel.clear);
      widget.onSent();
    } else if (err == 'pick') {
      await _browse(d, send: items);
    } else {
      toast(context, err);
    }
  }

  void _menu(Device d) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Row(children: [
              Icon(kindIcon(d.kind), color: t.accent2),
              const SizedBox(width: 12),
              Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(tr('Открыть файлы', 'Browse files')),
            onTap: () {
              Navigator.pop(sheet);
              _browse(d);
            },
          ),
          if (_sel.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_rounded),
              title: Text(tr('Отправить в выбранную папку…', 'Send to a chosen folder…')),
              onTap: () {
                Navigator.pop(sheet);
                _browse(d, send: List<FsEntry>.from(_sel));
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
            title: Text(tr('Переименовать, настроить', 'Rename, settings')),
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
    );
  }

  void _addSheet() {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    final c = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheet).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Добавить устройство', 'Add a device'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            tr('IP в вашей сети или адрес Tailscale (100.x) - так устройства видят друг друга даже через мобильный интернет.',
                'An IP on your network or a Tailscale (100.x) address - this way devices see each other even over mobile data.'),
            style: TextStyle(color: t.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(hintText: '192.168.1.50  /  100.64.1.5', prefixIcon: const Icon(Icons.lan_outlined)),
            onSubmitted: (_) async {
              Navigator.pop(sheet);
              final r = await s.addManual(c.text);
              if (mounted && r != null) toast(context, r);
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: tr('Добавить', 'Add'),
              icon: Icons.add_link_rounded,
              onTap: () async {
                Navigator.pop(sheet);
                final r = await s.addManual(c.text);
                if (mounted && r != null) toast(context, r);
              },
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = NlScope.of(context);
        final devs = s.sortedDevices.where((d) => !d.isSelf).toList();
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
              Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
  final VoidCallback onTap;
  final VoidCallback onLong;
  final VoidCallback onBrowse;
  const _DevTile({required this.d, required this.armed, required this.onTap, required this.onLong, required this.onBrowse});

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
  void initState() {
    super.initState();
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
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          ListenableBuilder(
            listenable: pane,
            builder: (_, __) => IconBtn(icon: pane.grid ? Icons.view_list_rounded : Icons.grid_view_rounded, tip: tr('Вид', 'View'), onTap: pane.toggleGrid),
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
    );
  }
}

/// Файлы другого устройства. Если передан [sendItems] - выбираем папку, куда отправить.
class BrowsePage extends StatefulWidget {
  final Device device;
  final List<FsEntry>? sendItems;
  const BrowsePage({super.key, required this.device, this.sendItems});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  late final PaneController pane = PaneController('br${widget.device.id}');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = AppScope.of(context);
      await connectFlow(context, s, pane, widget.device);
      if (!mounted) return;
      if (pane.error != null) toast(context, pane.error!);
      if (!pane.attached) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    pane.vfs?.close();
    super.dispose();
  }

  Future<void> _sendHere() async {
    final s = AppScope.of(context);
    final items = widget.sendItems!;
    if (pane.isVirtualRoot) {
      toast(context, tr('Откройте папку назначения', 'Open a destination folder first'));
      return;
    }
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
    final dir = await s.localInbox();
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
    if (mounted) toast(context, tr('Скачиваем в «Загрузки/NanoLink» - смотрите вкладку «Передачи»', 'Downloading to Downloads/NanoLink - see the Transfers tab'));
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final send = widget.sendItems;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: ListenableBuilder(
          listenable: pane,
          builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.device.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            if (pane.attached && pane.error == null && pane.entries.isNotEmpty)
              Text(tr('Подключено', 'Connected'), style: const TextStyle(color: Color(0xFF3DDC84), fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
        actions: [
          ListenableBuilder(
            listenable: pane,
            builder: (_, __) => IconBtn(icon: pane.grid ? Icons.view_list_rounded : Icons.grid_view_rounded, tip: tr('Вид', 'View'), onTap: pane.toggleGrid),
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
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: tr('Отправить сюда · ${send.length}', 'Send here · ${send.length}'),
                    icon: Icons.send_rounded,
                    onTap: pane.attached ? _sendHere : null,
                  ),
                ),
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
                const SizedBox(width: 4),
                GradientButton(compact: true, label: tr('Скачать', 'Download'), icon: Icons.download_rounded, onTap: _download),
              ]),
            ),
          );
        },
      ),
    );
  }
}

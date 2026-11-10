import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/state.dart';
import 'devices_page.dart';
import 'dialogs.dart';
import 'explorer_page.dart';
import 'painters.dart';
import 'phone.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'transfers_page.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  AppState? _s;
  bool _pairOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s == null) {
      _s = AppScope.of(context);
      _s!.addListener(_onState);
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onState());
    }
  }

  @override
  void dispose() {
    _s?.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _s?.checkAllFiles();
      _s?.pullShared();
    }
  }

  void _onState() {
    final s = _s;
    if (s == null || !mounted) return;
    if (s.pendingPair != null && !_pairOpen) {
      _pairOpen = true;
      showPairDialog(context, s).whenComplete(() {
        _pairOpen = false;
        if (mounted) _onState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = NlScope.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(children: [
        Positioned.fill(child: AmbientBackground(theme: t)),
        SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 700) return const PhoneHome();
            final wide = c.maxWidth >= 900;
            final stack = ListenableBuilder(
              listenable: s,
              builder: (context, _) => IndexedStack(index: s.page, children: const [DevicesPage(), ExplorerPage(), TransfersPage(), SettingsPage()]),
            );
            if (wide) {
              return Row(children: [
                _Sidebar(s: s, t: t),
                Expanded(child: stack),
              ]);
            }
            return Column(children: [
              Expanded(child: stack),
              _BottomNav(s: s, t: t),
            ]);
          }),
        ),
      ]),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

List<_NavItem> _items() => [
      _NavItem(Icons.devices_rounded, tr('Устройства', 'Devices')),
      _NavItem(Icons.vertical_split_rounded, tr('Проводник', 'Explorer')),
      _NavItem(Icons.swap_vert_rounded, tr('Передачи', 'Transfers')),
      _NavItem(Icons.settings_rounded, tr('Настройки', 'Settings')),
    ];

class _Sidebar extends StatelessWidget {
  final AppState s;
  final NlTheme t;
  const _Sidebar({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      margin: const EdgeInsets.fromLTRB(10, 10, 0, 10),
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: t.border)),
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final its = _items();
          return Column(children: [
            Row(children: [
              GlobeWidget(size: 62, a: t.accent, b: t.accent2),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('NanoLink', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                  Text(tr('файлы между устройствами', 'files between devices'), style: TextStyle(color: t.muted, fontSize: 11.5)),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            for (var i = 0; i < its.length; i++)
              _SideTile(
                item: its[i],
                selected: s.page == i,
                t: t,
                badge: i == 2 ? s.transfers.activeCount : 0,
                onTap: () => s.setPage(i),
              ),
            const SizedBox(height: 8),
            Expanded(child: HelixWidget(color: t.accent)),
            _StatusPill(s: s, t: t),
            const SizedBox(height: 10),
            _LangSwitch(s: s, t: t),
          ]);
        },
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final NlTheme t;
  final int badge;
  final VoidCallback onTap;
  const _SideTile({required this.item, required this.selected, required this.t, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: selected ? t.surface2 : Colors.transparent, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 3,
              height: selected ? 26 : 0,
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 10),
            Icon(item.icon, color: selected ? t.accent2 : t.muted, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(item.label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 15, color: selected ? t.text : t.muted))),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(gradient: t.gradient, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final AppState s;
  final NlTheme t;
  const _StatusPill({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    final online = s.netOnline;
    final cnt = s.devices.where((d) => d.online).length;
    final col = online ? const Color(0xFF3DDC84) : const Color(0xFFFFB020);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(22), border: Border.all(color: t.border)),
      child: Row(children: [
        PulseDot(color: col),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            online ? (cnt > 0 ? tr('В сети · $cnt', 'Online · $cnt') : tr('В сети', 'Online')) : tr('Нет связи', 'No link'),
            style: TextStyle(color: t.text.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
          ),
        ),
        WaveWidget(color: col, alive: online, width: 58),
      ]),
    );
  }
}

class _LangSwitch extends StatelessWidget {
  final AppState s;
  final NlTheme t;
  const _LangSwitch({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    final ru = s.settings.lang != 'en';
    Widget half(String label, bool on, VoidCallback tap) {
      return Expanded(
        child: GestureDetector(
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.center,
            height: 40,
            decoration: BoxDecoration(gradient: on ? t.gradient : null, borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : t.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(24), border: Border.all(color: t.border)),
      child: Row(children: [
        half('RU', ru, () => s.setLang('ru')),
        half('EN', !ru, () => s.setLang('en')),
      ]),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final AppState s;
  final NlTheme t;
  const _BottomNav({required this.s, required this.t});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final its = _items();
        return Container(
          decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border))),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: t.accent.withValues(alpha: 0.22),
              labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(fontSize: 11.5, fontWeight: st.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500, color: st.contains(WidgetState.selected) ? t.text : t.muted)),
              iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? t.accent2 : t.muted)),
            ),
            child: NavigationBar(
              height: 62,
              elevation: 0,
              selectedIndex: s.page,
              onDestinationSelected: s.setPage,
              destinations: [
                for (var i = 0; i < its.length; i++)
                  NavigationDestination(
                    icon: Badge(isLabelVisible: i == 2 && s.transfers.activeCount > 0, label: Text('${s.transfers.activeCount}'), child: Icon(its[i].icon)),
                    label: its[i].label,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

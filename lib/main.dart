import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/i18n.dart';
import 'core/state.dart';
import 'ui/painters.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) => FlutterError.presentError(d);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    runApp(NanoApp(state: AppState()));
  }, (e, st) {
    // Любая необработанная ошибка в сетевом коде не должна ронять приложение.
    debugPrint('NanoLink uncaught: $e\n$st');
  });
}

class NanoApp extends StatefulWidget {
  final AppState state;
  const NanoApp({super.key, required this.state});

  @override
  State<NanoApp> createState() => _NanoAppState();
}

class _NanoAppState extends State<NanoApp> {
  late String _themeId;
  late bool _ready;
  late bool _ru;
  ThemeData? _data;
  String? _dataFor;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _themeId = s.settings.theme;
    _ready = s.ready;
    _ru = L.ru;
    s.addListener(_onState);
    unawaited(s.init().catchError((Object e) {
      debugPrint('init failed: $e');
      // Лучше открыть интерфейс с частично рабочим состоянием, чем вечная заставка.
      s.ready = true;
      s.deviceChanged();
    }));
  }

  void _onState() {
    final s = widget.state;
    if (s.settings.theme != _themeId || s.ready != _ready || L.ru != _ru) {
      setState(() {
        _themeId = s.settings.theme;
        _ready = s.ready;
        _ru = L.ru;
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final nl = themeById(_themeId);
    if (_dataFor != nl.id) {
      _data = buildTheme(nl);
      _dataFor = nl.id;
    }
    return AppScope(
      state: s,
      child: NlScope(
        theme: nl,
        child: MaterialApp(
          title: 'NanoLink',
          debugShowCheckedModeBanner: false,
          theme: _data,
          home: _ready ? Shell(key: ValueKey(_ru)) : _Splash(nl: nl),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  final NlTheme nl;
  const _Splash({required this.nl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: nl.bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GlobeWidget(size: 120, a: nl.accent, b: nl.accent2),
          const SizedBox(height: 16),
          const Text('NanoLink', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/local_vfs.dart';
import '../core/pane.dart';
import '../core/platform.dart';
import '../core/state.dart';
import 'pane_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// Выбор папки на этом телефоне. Возвращает путь или null.
class FolderPickPage extends StatefulWidget {
  final String title;
  const FolderPickPage({super.key, required this.title});

  @override
  State<FolderPickPage> createState() => _FolderPickPageState();
}

class _FolderPickPageState extends State<FolderPickPage> {
  final PaneController pane = PaneController('folder');

  @override
  void initState() {
    super.initState();
    pane.attach(LocalVfs(), () => LocalVfs(), null);
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final s = AppScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!pane.back()) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(backgroundColor: t.bg, elevation: 0, title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)), actions: [homeButton(context)]),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            if (Platform.isAndroid && !s.allFilesOk) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.folder_open_rounded, size: 54, color: t.accent2),
                    const SizedBox(height: 16),
                    Text(tr('Чтобы выбрать папку, разрешите NanoLink доступ к файлам.', 'To pick a folder allow NanoLink to access files.'), textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                    const SizedBox(height: 20),
                    GradientButton(label: tr('Разрешить доступ к файлам', 'Allow file access'), icon: Icons.lock_open_rounded, onTap: () => Native.requestAllFiles()),
                  ]),
                ),
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
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: tr('Выбрать эту папку', 'Use this folder'),
                icon: Icons.check_rounded,
                onTap: pane.attached && !pane.isVirtualRoot && pane.path.isNotEmpty ? () => Navigator.pop(context, pane.path) : null,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Встроенный проводник для папки на этом телефоне (например, «Показать в папке» после приёма).
class FolderViewPage extends StatefulWidget {
  final String path;
  const FolderViewPage({super.key, required this.path});

  @override
  State<FolderViewPage> createState() => _FolderViewPageState();
}

class _FolderViewPageState extends State<FolderViewPage> {
  final PaneController pane = PaneController('fview');

  @override
  void initState() {
    super.initState();
    pane.attach(LocalVfs(), () => LocalVfs(), null).then((_) {
      if (mounted) pane.cd(widget.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final name = widget.path.substring(widget.path.lastIndexOf('/') + 1);
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
          title: Text(name.isEmpty ? widget.path : name, style: const TextStyle(fontWeight: FontWeight.w800)),
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
            child: PaneView(pane: pane, hideHeader: true, hideSelBar: true, hideCats: true),
          ),
        ),
      ),
    );
  }
}

/// Выбор приложения, в котором открывать папки. Возвращает [пакет, название] или null.
/// Пакет 'nanolink' - встроенный проводник. [forceRemember] - всегда запоминать (из настроек).
Future<List<String>?> chooseFolderApp(BuildContext ctx, AppState s, String samplePath, {bool forceRemember = false}) async {
  final apps = await Native.listFolderApps(samplePath);
  if (!ctx.mounted) return null;
  final t = NlScope.of(ctx);
  var remember = true;
  return showModalBottomSheet<List<String>>(
    context: ctx,
    backgroundColor: t.surface2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setS) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('Чем открывать папки?', 'Open folders with?'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.bolt_rounded, color: t.accent2),
              title: const Text('NanoLink'),
              subtitle: Text(tr('Встроенный проводник: фото и видео открываются прямо там', 'Built-in explorer: photos and videos open right there')),
              onTap: () {
                if (remember || forceRemember) s.setFolderApp('nanolink', 'NanoLink');
                Navigator.pop(sheet, ['nanolink', 'NanoLink']);
              },
            ),
            for (final a in apps)
              ListTile(
                leading: Icon(Icons.folder_rounded, color: t.accent2),
                title: Text(a['label'] ?? a['pkg'] ?? ''),
                subtitle: Text(a['pkg'] ?? '', style: TextStyle(color: t.muted, fontSize: 11.5)),
                onTap: () {
                  if (remember || forceRemember) s.setFolderApp(a['pkg'] ?? '', a['label'] ?? '');
                  Navigator.pop(sheet, [a['pkg'] ?? '', a['label'] ?? '']);
                },
              ),
            if (!forceRemember)
              CheckboxListTile(
                value: remember,
                onChanged: (v) => setS(() => remember = v ?? true),
                title: Text(tr('Запомнить выбор', 'Remember my choice')),
                subtitle: Text(tr('Изменить можно в настройках', 'Can be changed in settings')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ),
  );
}

/// «Показать в папке»: открывает [path] в выбранном приложении (спросит один раз и запомнит).
Future<void> openFolderFlow(BuildContext ctx, AppState s, String path) async {
  var app = s.settings.folderApp;
  if (app.isEmpty) {
    final r = await chooseFolderApp(ctx, s, path);
    if (r == null || !ctx.mounted) return;
    app = r[0];
  }
  if (app != 'nanolink') {
    final ok = await Native.openFolder(path, pkg: app);
    if (ok) return;
    if (ctx.mounted) toast(ctx, tr('Это приложение не смогло открыть папку - открываем в NanoLink', 'That app could not open the folder - opening in NanoLink'));
  }
  if (ctx.mounted) await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => FolderViewPage(path: path)));
}

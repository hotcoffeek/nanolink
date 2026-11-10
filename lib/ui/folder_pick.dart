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
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(backgroundColor: t.bg, elevation: 0, title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800))),
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
    );
  }
}

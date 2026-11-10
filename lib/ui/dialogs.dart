import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/models.dart';
import '../core/pane.dart';
import '../core/state.dart';
import '../core/util.dart';
import 'theme.dart';
import 'widgets.dart';

Future<String?> promptText(
  BuildContext ctx, {
  required String title,
  String? initial,
  String? hint,
  String? okLabel,
}) {
  final c = TextEditingController(text: initial ?? '');
  c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  return showDialog<String>(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(dctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('Отмена', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(dctx, c.text), child: Text(okLabel ?? 'OK')),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext ctx, String title, String text, {String? okLabel}) async {
  final r = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('Отмена', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(okLabel ?? tr('Да', 'Yes'))),
      ],
    ),
  );
  return r == true;
}

/// Запрос на сопряжение от другого устройства.
Future<void> showPairDialog(BuildContext ctx, AppState s) async {
  final req = s.pendingPair;
  if (req == null) return;
  await showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (dctx) {
      final t = NlScope.of(dctx);
      return AlertDialog(
        title: Row(children: [
          Icon(kindIcon(req.kind), color: t.accent2),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('Новое подключение', 'New connection'))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(req.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(req.ip, style: TextStyle(color: t.muted)),
            const SizedBox(height: 14),
            Text(tr(
              'Это устройство хочет получить доступ к файлам. Разрешите один раз - дальше оно будет подключаться само.',
              'This device wants access to your files. Allow it once - after that it connects automatically.',
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              s.answerPair(false);
              Navigator.pop(dctx);
            },
            child: Text(tr('Отклонить', 'Deny')),
          ),
          FilledButton(
            onPressed: () {
              s.answerPair(true);
              Navigator.pop(dctx);
            },
            child: Text(tr('Разрешить', 'Allow')),
          ),
        ],
      );
    },
  );
}

Future<String?> pickProto(BuildContext ctx, AppState s, Device d, List<String> protos) {
  String hint(String p) {
    switch (p) {
      case 'nano':
        return tr('Самый надёжный: докачка, авто-восстановление', 'Most reliable: resume, auto-recovery');
      case 'smb':
        return tr('Сетевая папка Windows / Samba', 'Windows / Samba share');
      case 'sftp':
        return tr('По SSH (например Steam Deck)', 'Over SSH (e.g. Steam Deck)');
      case 'ftp':
        return tr('FTP-сервер (например на ТВ-приставке)', 'FTP server (e.g. on a TV box)');
    }
    return '';
  }

  return showDialog<String>(
    context: ctx,
    builder: (dctx) {
      final t = NlScope.of(dctx);
      return SimpleDialog(
        title: Text(tr('Как подключиться к «${d.title}»?', 'How to connect to "${d.title}"?')),
        children: [
          for (final p in protos)
            ListTile(
              leading: Icon(p == 'nano' ? Icons.bolt_rounded : Icons.folder_shared_rounded, color: t.accent2),
              title: Text(protoLabel(p), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(hint(p)),
              onTap: () => Navigator.pop(dctx, p),
            ),
        ],
      );
    },
  );
}

/// Логин/пароль/порт для FTP, SFTP, SMB. Возвращает true, если сохранено.
Future<bool> credsDialog(BuildContext ctx, AppState s, Device d, String proto) async {
  final svc = d.services.putIfAbsent(proto, () => <String, dynamic>{});
  final defPort = proto == 'ftp' ? 21 : (proto == 'sftp' ? 22 : 445);
  final defUser = proto == 'ftp' ? 'anonymous' : (proto == 'sftp' ? 'deck' : 'guest');
  final user = TextEditingController(text: (svc['user'] ?? defUser).toString());
  final pass = TextEditingController(text: (svc['pass'] ?? '').toString());
  final port = TextEditingController(text: ((svc['port'] as num?)?.toInt() ?? defPort).toString());
  final r = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: Text('${protoLabel(proto)} · ${d.title}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: user, decoration: InputDecoration(labelText: tr('Логин', 'Login'))),
          const SizedBox(height: 10),
          TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: tr('Пароль', 'Password'))),
          const SizedBox(height: 10),
          TextField(controller: port, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Порт', 'Port'))),
          const SizedBox(height: 10),
          Text(
            proto == 'smb'
                ? tr('Для общей папки без пароля оставьте guest и пустой пароль.', 'For an open share keep guest and an empty password.')
                : (proto == 'ftp'
                    ? tr('Если сервер без пароля - оставьте anonymous.', 'If the server has no password keep anonymous.')
                    : tr('Логин и пароль пользователя SSH на устройстве.', 'SSH user login and password on the device.')),
            style: TextStyle(color: NlScope.of(dctx).muted, fontSize: 12.5),
          ),
          if (proto == 'sftp') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: NlScope.of(dctx).surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: NlScope.of(dctx).border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  tr('Steam Deck: без этих двух команд в консоли доступ не заработает (и задайте пароль командой passwd):', 'Steam Deck: SFTP will not work without these two console commands (and set a password with passwd):'),
                  style: TextStyle(color: NlScope.of(dctx).muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                const SelectableText('sudo systemctl enable sshd\nsudo systemctl start sshd', style: TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Clipboard.setData(const ClipboardData(text: 'sudo systemctl enable sshd\nsudo systemctl start sshd')),
                    child: Text(tr('Копировать', 'Copy')),
                  ),
                ),
              ]),
            ),
          ],
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('Отмена', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr('Сохранить', 'Save'))),
      ],
    ),
  );
  if (r != true) return false;
  svc['user'] = user.text.trim();
  svc['pass'] = pass.text;
  svc['port'] = int.tryParse(port.text.trim()) ?? defPort;
  svc['configured'] = true;
  s.updateDevice(d);
  return true;
}

Future<void> editDeviceDialog(BuildContext ctx, AppState s, Device d) async {
  final name = TextEditingController(text: d.alias ?? d.name);
  final host = TextEditingController(text: d.host ?? '');
  var kind = d.kind == DeviceKind.thisDevice ? DeviceKind.pc : d.kind;
  final enabled = <String, bool>{for (final p in ['ftp', 'sftp', 'smb']) p: d.has(p)};
  await showDialog<void>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) {
        final t = NlScope.of(dctx);
        return AlertDialog(
          title: Text(tr('Устройство', 'Device')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tr('Название (как вам удобно)', 'Name (anything you like)'))),
                const SizedBox(height: 12),
                TextField(controller: host, decoration: InputDecoration(labelText: tr('IP-адрес', 'IP address'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<DeviceKind>(
                  initialValue: kind,
                  decoration: InputDecoration(labelText: tr('Тип устройства', 'Device type')),
                  items: [
                    for (final k in DeviceKind.values)
                      if (k != DeviceKind.thisDevice) DropdownMenuItem(value: k, child: Text(kindLabel(k))),
                  ],
                  onChanged: (v) => setS(() => kind = v ?? kind),
                ),
                const SizedBox(height: 14),
                Text(tr('Протоколы доступа', 'Access protocols'), style: TextStyle(color: t.muted, fontWeight: FontWeight.w600)),
                for (final p in ['smb', 'sftp', 'ftp'])
                  Row(children: [
                    Expanded(child: Text(protoLabel(p), style: const TextStyle(fontWeight: FontWeight.w600))),
                    TextButton(
                      onPressed: enabled[p] == true
                          ? () async {
                              await credsDialog(dctx, s, d, p);
                            }
                          : null,
                      child: Text(tr('Логин / порт', 'Login / port')),
                    ),
                    Switch(value: enabled[p] == true, onChanged: (v) => setS(() => enabled[p] = v)),
                  ]),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(dctx, tr('Удалить устройство?', 'Remove device?'), tr('Оно исчезнет из списка и потеряет доверие.', 'It will disappear from the list and lose trust.'));
                if (ok && dctx.mounted) {
                  s.removeDevice(d);
                  Navigator.pop(dctx);
                }
              },
              child: Text(tr('Удалить', 'Remove')),
            ),
            TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('Отмена', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final n = name.text.trim();
                d.alias = (n.isEmpty || n == d.name) ? null : n;
                d.kind = kind;
                final h = host.text.trim();
                if (h.isNotEmpty) d.host = h;
                for (final p in ['ftp', 'sftp', 'smb']) {
                  if (enabled[p] == true) {
                    d.services.putIfAbsent(p, () => {'port': p == 'ftp' ? 21 : (p == 'sftp' ? 22 : 445)});
                  } else {
                    d.services.remove(p);
                  }
                }
                s.updateDevice(d);
                Navigator.pop(dctx);
              },
              child: Text(tr('Сохранить', 'Save')),
            ),
          ],
        );
      },
    ),
  );
}

/// Выбор протокола, логина и подключение устройства в панель.
Future<void> connectFlow(BuildContext ctx, AppState s, PaneController pane, Device d) async {
  if (d.isSelf) {
    await s.openLocal(pane);
    return;
  }
  var protos = s.protosOf(d);
  if (protos.isEmpty) {
    await editDeviceDialog(ctx, s, d);
    protos = s.protosOf(d);
    if (protos.isEmpty) return;
  }
  String? proto;
  if (protos.length == 1) {
    proto = protos.first;
  } else if (ctx.mounted) {
    proto = await pickProto(ctx, s, d, protos);
  }
  if (proto == null) return;
  if (proto != 'nano' && d.services[proto]?['configured'] != true && ctx.mounted) {
    final ok = await credsDialog(ctx, s, d, proto);
    if (!ok) return;
  }
  await s.connect(pane, d, proto);
}

/// «Устройство хочет отправить вам файл» - принять или отклонить.
Future<void> showRecvDialog(BuildContext ctx, AppState s) async {
  final req = s.pendingRecv;
  if (req == null) return;
  await showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      title: Text(tr('Входящий файл', 'Incoming file')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(req.from, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(req.file),
        const SizedBox(height: 10),
        Text(tr('Если принять, остальные файлы от этого устройства в течение 2 минут принимаются без вопросов.', 'If you accept, the other files from this device in the next 2 minutes are accepted without asking.'),
            style: TextStyle(color: NlScope.of(dctx).muted, fontSize: 12.5)),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            s.answerRecv(false);
            Navigator.pop(dctx);
          },
          child: Text(tr('Отклонить', 'Decline')),
        ),
        FilledButton(
          onPressed: () {
            s.answerRecv(true);
            Navigator.pop(dctx);
          },
          child: Text(tr('Принять', 'Accept')),
        ),
      ],
    ),
  );
}

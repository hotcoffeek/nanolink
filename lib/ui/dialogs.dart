import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diagnose.dart';
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
Future<void> connectFlow(BuildContext ctx, AppState s, PaneController pane, Device d, {String? proto, bool ask = false}) async {
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
  String? use = proto;
  if (use == null || !protos.contains(use)) {
    use = null;
    if (!ask) {
      if (protos.contains('nano')) {
        use = 'nano'; // NanoLink есть - всегда им, не спрашиваем
      } else if (d.prefProto != null && protos.contains(d.prefProto)) {
        use = d.prefProto;
      } else if (protos.length == 1) {
        use = protos.first;
      }
    }
    if (use == null && ctx.mounted) use = await pickProto(ctx, s, d, protos);
  }
  if (use == null) return;
  if (protos.length > 1 && d.prefProto != use) {
    d.prefProto = use;
    s.updateDevice(d);
  }
  if (use != 'nano' && d.services[use]?['configured'] != true && ctx.mounted) {
    final ok = await credsDialog(ctx, s, d, use);
    if (!ok) return;
  }
  await s.connect(pane, d, use);
}

/// «Устройство хочет отправить вам файл» - принять или отклонить.
bool _recvShowing = false;

Future<void> showRecvDialog(BuildContext ctx, AppState s) async {
  final req = s.pendingRecv;
  if (req == null || _recvShowing) return;
  _recvShowing = true;
  try {
    await _showRecv(ctx, s, req);
  } finally {
    _recvShowing = false;
  }
}

Future<void> _showRecv(BuildContext ctx, AppState s, RecvRequest req) async {
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
        Text(tr('Остальные файлы этой же отправки примутся без вопросов. Следующая отправка спросит снова.', 'The rest of this same transfer is accepted without asking. The next transfer asks again.'),
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


/// «Диагностика»: проверяет порты и вход по FTP/SMB и показывает точные ответы устройства.
Future<void> showDiagnose(BuildContext ctx, Device d) {
  final fut = diagnoseDevice(d);
  return showDialog<void>(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: Text(tr('Диагностика · ${d.title}', 'Diagnostics · ${d.title}')),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<String>(
          future: fut,
          builder: (_, snap) {
            if (!snap.hasData) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 10),
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(tr('Проверяем порты, FTP и SMB…', 'Checking ports, FTP and SMB…')),
              ]);
            }
            return SingleChildScrollView(child: SelectableText(snap.data!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)));
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final text = await fut;
            await Clipboard.setData(ClipboardData(text: text));
            if (dctx.mounted) toast(dctx, tr('Скопировано', 'Copied'));
          },
          child: Text(tr('Копировать', 'Copy')),
        ),
        FilledButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('Закрыть', 'Close'))),
      ],
    ),
  );
}

/// Ручное подключение: адрес, протокол, порт, логин и пароль (FTP / SFTP / SMB / NanoLink).
Future<void> showManualAddSheet(BuildContext ctx, AppState s, {required void Function(Device d, String? proto) onOpen}) {
  final t = NlScope.of(ctx);
  final host = TextEditingController();
  final port = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();
  var proto = 'auto';
  var busy = false;
  return showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: t.surface2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setS) {
        final plain = proto == 'ftp' || proto == 'sftp' || proto == 'smb';
        final defPort = proto == 'ftp' ? '21' : (proto == 'sftp' ? '22' : (proto == 'smb' ? '445' : ''));
        final defUser = proto == 'ftp' ? 'anonymous' : (proto == 'sftp' ? 'deck' : 'guest');
        Future<void> go() async {
          if (busy) return;
          setS(() => busy = true);
          final r = await s.addManualEx(host.text, proto, port: int.tryParse(port.text.trim()) ?? 0, user: user.text, pass: pass.text);
          if (!sheet.mounted) return;
          if (r.error != null || r.device == null) {
            setS(() => busy = false);
            toast(sheet, r.error ?? r.note ?? tr('Не удалось добавить устройство', 'Could not add the device'));
            return;
          }
          Navigator.pop(sheet);
          if (r.note != null && ctx.mounted) toast(ctx, r.note!);
          onOpen(r.device!, plain ? proto : null);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(sheet).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Подключиться вручную', 'Connect manually'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                tr('IP или имя устройства: роутер, приставка, ПК, адрес Tailscale (100.x). Выберите протокол и при необходимости порт, логин и пароль.',
                    'IP or device name: router, set-top box, PC, Tailscale address (100.x). Pick a protocol and, if needed, port, login and password.'),
                style: TextStyle(color: t.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: host,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: '192.168.1.1  /  100.64.1.5', prefixIcon: Icon(Icons.lan_outlined)),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in const ['auto', 'nano', 'ftp', 'sftp', 'smb'])
                  ChoiceChip(
                    label: Text(p == 'auto' ? tr('Авто', 'Auto') : protoLabel(p)),
                    selected: proto == p,
                    onSelected: (_) => setS(() => proto = p),
                  ),
              ]),
              if (plain) ...[
                const SizedBox(height: 12),
                Row(children: [
                  SizedBox(
                    width: 110,
                    child: TextField(controller: port, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Порт', 'Port'), hintText: defPort)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: user, decoration: InputDecoration(labelText: tr('Логин', 'Login'), hintText: defUser))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: tr('Пароль', 'Password'))),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: busy ? tr('Подключаемся…', 'Connecting…') : tr('Подключиться', 'Connect'),
                  icon: Icons.link_rounded,
                  onTap: busy ? null : go,
                ),
              ),
            ]),
          ),
        );
      },
    ),
  );
}

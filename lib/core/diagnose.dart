import 'package:dartssh2/dartssh2.dart';

import 'ftp_vfs.dart';
import 'models.dart';
import 'smb_probe.dart';
import 'smb_vfs.dart';
import 'util.dart';

/// Диагностика подключения к устройству: порты, вход по FTP и SMB. Результат можно скопировать и прислать.
Future<String> diagnoseDevice(Device d) async {
  final out = <String>[];
  final host = d.host ?? '';
  out.add('Устройство: ${d.title}');
  out.add('Адрес: ${host.isEmpty ? 'неизвестен' : host}');
  out.add('Протоколы в программе: ${d.services.keys.join(', ')}');
  if (host.isEmpty) return out.join('\n');
  final names = {21: 'FTP', 2121: 'FTP (2121)', 2021: 'FTP (2021)', 8021: 'FTP (8021)', 22: 'SFTP/SSH', 445: 'SMB', 139: 'SMB (NetBIOS)', 80: 'веб-панель', 443: 'веб-панель (https)', 47322: 'NanoLink'};
  final res = await Future.wait(names.keys.map((p) async => MapEntry(p, await portOpen(host, p, ms: 900))));
  out.add('');
  out.add('Порты:');
  for (final e in res) {
    out.add('  ${e.key} ${names[e.key]}: ${e.value ? 'открыт' : 'закрыт'}');
  }
  final open = {for (final e in res) e.key: e.value};
  if (open[21] == true || open[2121] == true || open[2021] == true || open[8021] == true || d.services.containsKey('ftp')) {
    out.add('');
    out.addAll(await ftpDiagnose(d));
  }
  if (open[445] == true || d.services.containsKey('smb')) {
    out.add('');
    out.addAll(await smbProbe(host));
    out.add('');
    out.addAll(await smbDiagnose(d));
  }
  if (open[22] == true) {
    out.add('');
    out.addAll(await sftpDiagnose(d));
  }
  out.add('');
  out.add('Если закрыты все порты, кроме веб-панели, включите FTP/Samba в настройках роутера (USB-приложение).');
  return out.join('\n');
}

/// Проверка входа по SFTP (SSH). Логин/пароль берём от SFTP, а если их нет - от SMB.
Future<List<String>> sftpDiagnose(Device d) async {
  final out = <String>[];
  final host = d.host ?? '';
  final port = d.portOf('sftp', 22);
  var user = d.str('sftp', 'user');
  var pass = d.str('sftp', 'pass');
  if (user == null || user.isEmpty || user == 'deck') {
    final su = d.str('smb', 'user');
    if (su != null && su.isNotEmpty) {
      user = su;
      pass = d.str('smb', 'pass');
    }
  }
  user = (user == null || user.isEmpty) ? 'admin' : user;
  pass = pass ?? '';
  out.add('SFTP  $host:$port, логин «$user»');
  SSHClient? client;
  try {
    final socket = await SSHSocket.connect(host, port).timeout(const Duration(seconds: 6));
    client = SSHClient(socket, username: user, onPasswordRequest: () => pass);
    await client.authenticated.timeout(const Duration(seconds: 12));
    out.add('✓ вход по SSH выполнен');
    try {
      final sftp = await client.sftp().timeout(const Duration(seconds: 10));
      final items = await sftp.listdir('/').timeout(const Duration(seconds: 10));
      final names = items.map((e) => e.filename).where((n) => n != '.' && n != '..').take(8).join(', ');
      out.add('✓ SFTP работает, в корне: $names');
    } catch (e) {
      var t = '${e.runtimeType}: $e';
      if (t.length > 200) t = '${t.substring(0, 200)}…';
      out.add('✗ SFTP-подсистема недоступна: $t');
      out.add('  (на роутерах ASUS SSH обычно без SFTP - тогда нужен SMB или FTP)');
    }
  } catch (e) {
    var t = '${e.runtimeType}: $e';
    if (t.length > 200) t = '${t.substring(0, 200)}…';
    out.add('✗ вход по SSH: $t');
  } finally {
    try {
      client?.close();
    } catch (_) {}
  }
  return out;
}

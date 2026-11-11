import 'ftp_vfs.dart';
import 'models.dart';
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
  final names = {21: 'FTP', 2121: 'FTP (2121)', 22: 'SFTP/SSH', 445: 'SMB', 139: 'SMB (NetBIOS)', 80: 'веб-панель', 443: 'веб-панель (https)', 47322: 'NanoLink'};
  final res = await Future.wait(names.keys.map((p) async => MapEntry(p, await portOpen(host, p, ms: 900))));
  out.add('');
  out.add('Порты:');
  for (final e in res) {
    out.add('  ${e.key} ${names[e.key]}: ${e.value ? 'открыт' : 'закрыт'}');
  }
  final open = {for (final e in res) e.key: e.value};
  if (open[21] == true || open[2121] == true || d.services.containsKey('ftp')) {
    out.add('');
    out.addAll(await ftpDiagnose(d));
  }
  if (open[445] == true || d.services.containsKey('smb')) {
    out.add('');
    out.addAll(await smbDiagnose(d));
  }
  out.add('');
  out.add('Если закрыты все порты, кроме веб-панели, включите FTP/Samba в настройках роутера (USB-приложение).');
  return out.join('\n');
}

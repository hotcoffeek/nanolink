import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'util.dart';

String _hex(List<int> b, [int max = 16]) {
  final n = b.length < max ? b.length : max;
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    sb.write(b[i].toRadixString(16).padLeft(2, '0'));
    if (i < n - 1) sb.write(' ');
  }
  return sb.toString();
}

String _dialectName(int d) {
  switch (d) {
    case 0x0202:
      return 'SMB 2.0.2';
    case 0x0210:
      return 'SMB 2.1';
    case 0x0300:
      return 'SMB 3.0';
    case 0x0302:
      return 'SMB 3.0.2';
    case 0x0311:
      return 'SMB 3.1.1';
    case 0x02FF:
      return 'SMB 2 (общий ответ)';
  }
  return '0x${d.toRadixString(16)}';
}

/// Отправляет в сокет один запрос и ждёт ответ (NetBIOS-кадр: 4 байта заголовка + тело).
Future<Uint8List?> _exchange(String host, int port, Uint8List req, {int ms = 4000}) async {
  Socket? s;
  try {
    s = await lanConnect(host, port, timeout: const Duration(seconds: 4));
    final done = Completer<Uint8List?>();
    final buf = BytesBuilder();
    final sub = s.listen((d) {
      buf.add(d);
      final all = buf.toBytes();
      if (all.length >= 4) {
        final len = (all[1] << 16) | (all[2] << 8) | all[3];
        if (all.length >= 4 + len && !done.isCompleted) done.complete(all);
      }
    }, onError: (Object _) {
      if (!done.isCompleted) done.complete(buf.isEmpty ? null : buf.toBytes());
    }, onDone: () {
      if (!done.isCompleted) done.complete(buf.isEmpty ? null : buf.toBytes());
    });
    s.add(req);
    await s.flush();
    final r = await done.future.timeout(Duration(milliseconds: ms), onTimeout: () => null);
    await sub.cancel();
    return r;
  } catch (_) {
    return null;
  } finally {
    try {
      s?.destroy();
    } catch (_) {}
  }
}

Uint8List _frame(List<int> body) {
  final b = BytesBuilder();
  b.add([0, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
  b.add(body);
  return b.toBytes();
}

Uint8List _smb2Negotiate() {
  final h = Uint8List(64);
  h[0] = 0xFE;
  h[1] = 0x53;
  h[2] = 0x4D;
  h[3] = 0x42;
  h[4] = 64; // StructureSize
  h[14] = 31; // CreditRequest
  final dialects = [0x0202, 0x0210, 0x0300, 0x0302];
  final b = Uint8List(36 + dialects.length * 2);
  b[0] = 36;
  b[2] = dialects.length;
  b[4] = 1; // SecurityMode: signing enabled
  for (var i = 0; i < 16; i++) {
    b[12 + i] = (i * 7 + 3) & 0xFF; // ClientGuid
  }
  for (var i = 0; i < dialects.length; i++) {
    b[36 + i * 2] = dialects[i] & 0xFF;
    b[37 + i * 2] = dialects[i] >> 8;
  }
  return _frame([...h, ...b]);
}

Uint8List _smb1Negotiate() {
  final h = Uint8List(32);
  h[0] = 0xFF;
  h[1] = 0x53;
  h[2] = 0x4D;
  h[3] = 0x42;
  h[4] = 0x72; // SMB_COM_NEGOTIATE
  h[9] = 0x18; // flags
  h[10] = 0x43; // flags2 (LE 0xC843)
  h[11] = 0xC8;
  h[30] = 0x01; // mid
  final dialects = <String>['NT LM 0.12', 'SMB 2.002', 'SMB 2.???'];
  final d = BytesBuilder();
  for (final s in dialects) {
    d.addByte(0x02);
    d.add(s.codeUnits);
    d.addByte(0);
  }
  final data = d.toBytes();
  final body = BytesBuilder();
  body.add(h);
  body.addByte(0); // WordCount
  body.add([data.length & 0xFF, data.length >> 8]);
  body.add(data);
  return _frame(body.toBytes());
}

/// Сырая проверка SMB без библиотек: какие версии протокола и как отвечает сервер.
Future<List<String>> smbProbe(String host, {int port = 445}) async {
  final out = <String>[];
  out.add('Проверка SMB-протокола напрямую ($host:$port):');
  final r2 = await _exchange(host, port, _smb2Negotiate());
  if (r2 == null) {
    out.add('  SMB2-запрос: нет ответа за 4 с (сервер молчит или рвёт соединение)');
  } else if (r2.length >= 8 && r2[4] == 0xFE) {
    final status = r2.length >= 16 ? (r2[12] | (r2[13] << 8) | (r2[14] << 16) | (r2[15] << 24)) : -1;
    if (r2.length >= 74 && status == 0) {
      final dialect = r2[72] | (r2[73] << 8);
      final mode = r2[70];
      out.add('  SMB2-запрос: ответ получен, версия ${_dialectName(dialect)}, подпись ${(mode & 2) != 0 ? 'обязательна' : ((mode & 1) != 0 ? 'включена' : 'выключена')}');
    } else {
      out.add('  SMB2-запрос: ответ SMB2, статус 0x${status.toRadixString(16)} (${r2.length} байт)');
    }
  } else if (r2.length >= 8 && r2[4] == 0xFF) {
    out.add('  SMB2-запрос: сервер ответил как SMB1 (только старый протокол)');
  } else {
    out.add('  SMB2-запрос: непонятный ответ ${_hex(r2)}');
  }
  final r1 = await _exchange(host, port, _smb1Negotiate());
  if (r1 == null) {
    out.add('  SMB1-запрос: нет ответа за 4 с');
  } else if (r1.length >= 8 && r1[4] == 0xFF) {
    var line = '  SMB1-запрос: ответ SMB1 (сервер поддерживает старый протокол)';
    if (r1.length > 37) {
      final idx = r1[37] | (r1[38 < r1.length ? 38 : 37] << 8);
      line += ', выбран диалект №$idx';
    }
    out.add(line);
  } else if (r1.length >= 8 && r1[4] == 0xFE) {
    out.add('  SMB1-запрос: сервер перешёл на SMB2 (SMB1 не нужен)');
  } else {
    out.add('  SMB1-запрос: непонятный ответ ${_hex(r1)}');
  }
  return out;
}

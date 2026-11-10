import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class ByteQueue {
  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _off = 0;
  int length = 0;

  void add(Uint8List d) {
    if (d.isEmpty) return;
    _chunks.addLast(d);
    length += d.length;
  }

  Uint8List take(int n) {
    final out = Uint8List(n);
    var w = 0;
    while (w < n) {
      final c = _chunks.first;
      final k = min(c.length - _off, n - w);
      out.setRange(w, w + k, c, _off);
      w += k;
      _off += k;
      if (_off == c.length) {
        _chunks.removeFirst();
        _off = 0;
      }
    }
    length -= n;
    return out;
  }
}

/// Обёртка над сокетом: кадры JSON + «сырые» байты, таймауты простоя и обратное давление.
class FrameSocket {
  final Socket socket;
  final ByteQueue _q = ByteQueue();
  late final StreamSubscription<Uint8List> _sub;
  Completer<void>? _wait;
  bool closed = false;
  bool _paused = false;

  FrameSocket(this.socket) {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _sub = socket.listen(
      (d) {
        _q.add(d);
        if (!_paused && _q.length > (6 << 20)) {
          _paused = true;
          _sub.pause();
        }
        _wake();
      },
      onError: (Object e) {
        closed = true;
        _wake();
      },
      onDone: () {
        closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  void _wake() {
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _resumeIfNeeded() {
    if (_paused && _q.length < (1 << 20)) {
      _paused = false;
      _sub.resume();
    }
  }

  Future<void> _need(int n, Duration idle) async {
    while (_q.length < n) {
      if (closed) throw const SocketException('connection closed');
      final c = Completer<void>();
      _wait = c;
      await c.future.timeout(idle, onTimeout: () {
        throw TimeoutException('network idle');
      });
    }
  }

  Future<Uint8List> readExact(int n, {Duration idle = const Duration(seconds: 15)}) async {
    await _need(n, idle);
    final r = _q.take(n);
    _resumeIfNeeded();
    return r;
  }

  /// Вернуть от 1 до [max] доступных байт.
  Future<Uint8List> readSome(int max, {Duration idle = const Duration(seconds: 15)}) async {
    await _need(1, idle);
    final r = _q.take(min(max, _q.length));
    _resumeIfNeeded();
    return r;
  }

  Future<Map<String, dynamic>> readJson({Duration idle = const Duration(seconds: 15)}) async {
    final h = await readExact(4, idle: idle);
    final len = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
    if (len <= 0 || len > (32 << 20)) throw const SocketException('bad frame');
    final body = await readExact(len, idle: idle);
    return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  }

  void sendJson(Map<String, dynamic> m) {
    final b = utf8.encode(jsonEncode(m));
    final h = Uint8List(4);
    h[0] = (b.length >> 24) & 255;
    h[1] = (b.length >> 16) & 255;
    h[2] = (b.length >> 8) & 255;
    h[3] = b.length & 255;
    socket.add(h);
    socket.add(b);
  }

  Future<void> closeGraceful() async {
    try {
      await socket.flush();
      await socket.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    destroy();
  }

  void destroy() {
    closed = true;
    try {
      socket.destroy();
    } catch (_) {}
  }
}

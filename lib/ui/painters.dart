import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Вращающийся глобус с орбитой - логотип и украшение шапки.
class GlobeWidget extends StatefulWidget {
  final double size;
  final Color a;
  final Color b;
  const GlobeWidget({super.key, required this.size, required this.a, required this.b});

  @override
  State<GlobeWidget> createState() => _GlobeWidgetState();
}

class _GlobeWidgetState extends State<GlobeWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _GlobePainter(_c.value, widget.a, widget.b)),
      ),
    );
  }
}

class _GlobePainter extends CustomPainter {
  final double t;
  final Color a;
  final Color b;
  _GlobePainter(this.t, this.a, this.b);

  @override
  void paint(Canvas c, Size s) {
    final r = min(s.width, s.height) / 2 * 0.6;
    final ctr = s.center(Offset.zero);
    final rect = Rect.fromCircle(center: ctr, radius: r);

    // свечение
    c.drawCircle(
      ctr,
      r * 1.5,
      Paint()
        ..shader = RadialGradient(colors: [a.withValues(alpha: 0.28), Colors.transparent]).createShader(Rect.fromCircle(center: ctr, radius: r * 1.5)),
    );
    // шар
    c.drawCircle(
      ctr,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.45),
          colors: [b.withValues(alpha: 0.95), a.withValues(alpha: 0.6), const Color(0xFF02060C)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.30);
    c.save();
    c.clipPath(Path()..addOval(rect));
    for (var i = 0; i < 4; i++) {
      final ph = t * 2 * pi + i * pi / 4;
      final w = r * cos(ph).abs();
      c.drawOval(Rect.fromCenter(center: ctr, width: max(w * 2, 0.5), height: r * 2), line);
    }
    for (final lat in const [-0.55, 0.0, 0.55]) {
      final y = ctr.dy + r * lat;
      final hw = r * sqrt(1 - lat * lat);
      c.drawOval(Rect.fromCenter(center: Offset(ctr.dx, y), width: hw * 2, height: hw * 0.3), line);
    }
    c.restore();

    // орбита и «спутник»
    c.save();
    c.translate(ctr.dx, ctr.dy);
    c.rotate(-0.55);
    final ring = Rect.fromCenter(center: Offset.zero, width: r * 2.9, height: r * 1.05);
    c.drawOval(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = a.withValues(alpha: 0.55),
    );
    for (var k = 0; k < 3; k++) {
      final ang = t * 2 * pi * 2 + k * 2.1;
      final p = Offset(cos(ang) * ring.width / 2, sin(ang) * ring.height / 2);
      c.drawCircle(p, k == 0 ? 3.4 : 2.2, Paint()..color = Colors.white.withValues(alpha: k == 0 ? 1 : 0.7));
      if (k == 0) c.drawCircle(p, 8, Paint()..color = b.withValues(alpha: 0.25));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => old.t != t || old.a != a;
}

/// Двойная спираль в боковой панели.
class HelixWidget extends StatefulWidget {
  final Color color;
  const HelixWidget({super.key, required this.color});

  @override
  State<HelixWidget> createState() => _HelixWidgetState();
}

class _HelixWidgetState extends State<HelixWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _HelixPainter(_c.value, widget.color), size: Size.infinite),
      ),
    );
  }
}

class _HelixPainter extends CustomPainter {
  final double t;
  final Color color;
  _HelixPainter(this.t, this.color);

  @override
  void paint(Canvas c, Size s) {
    if (s.height < 40) return;
    final cx = s.width / 2;
    final amp = min(s.width * 0.36, 48.0);
    final phase = t * 2 * pi;
    const freq = 0.021;
    final p1 = Path();
    final p2 = Path();
    for (double y = 0; y <= s.height; y += 3) {
      final x1 = cx + amp * sin(y * freq + phase);
      final x2 = cx + amp * sin(y * freq + phase + pi);
      if (y == 0) {
        p1.moveTo(x1, y);
        p2.moveTo(x2, y);
      } else {
        p1.lineTo(x1, y);
        p2.lineTo(x2, y);
      }
    }
    final fade = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, color.withValues(alpha: 0.55), color.withValues(alpha: 0.55), Colors.transparent],
      stops: const [0, 0.18, 0.82, 1],
    ).createShader(Offset.zero & s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = fade;
    c.drawPath(p1, stroke);
    c.drawPath(p2, stroke);

    final rung = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.16);
    for (double y = 8; y < s.height; y += 22) {
      final x1 = cx + amp * sin(y * freq + phase);
      final x2 = cx + amp * sin(y * freq + phase + pi);
      c.drawLine(Offset(x1, y), Offset(x2, y), rung);
      final depth = cos(y * freq + phase);
      final edge = min(y, s.height - y) / 120;
      final al = (edge.clamp(0.0, 1.0)) * 0.9;
      c.drawCircle(Offset(x1, y), depth > 0 ? 2.6 : 1.6, Paint()..color = color.withValues(alpha: al * (depth > 0 ? 1 : 0.5)));
      c.drawCircle(Offset(x2, y), depth > 0 ? 1.6 : 2.6, Paint()..color = color.withValues(alpha: al * (depth > 0 ? 0.5 : 1)));
    }
  }

  @override
  bool shouldRepaint(covariant _HelixPainter old) => old.t != t || old.color != color;
}

/// Анимированная линия «пульса» рядом со статусом.
class WaveWidget extends StatefulWidget {
  final Color color;
  final bool alive;
  final double width;
  const WaveWidget({super.key, required this.color, required this.alive, this.width = 70});

  @override
  State<WaveWidget> createState() => _WaveWidgetState();
}

class _WaveWidgetState extends State<WaveWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size(widget.width, 22),
        painter: _WavePainter(_c.value, widget.color, widget.alive),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double t;
  final Color color;
  final bool alive;
  _WavePainter(this.t, this.color, this.alive);

  @override
  void paint(Canvas c, Size s) {
    final mid = s.height / 2;
    final path = Path();
    final head = t * s.width;
    for (double x = 0; x <= s.width; x += 1.5) {
      var y = mid;
      if (alive) {
        final d = (x - head).abs();
        y = mid - exp(-d * d / 60) * 7 * sin((x - head) * 0.9);
      } else {
        y = mid + sin(x * 0.25 + t * 6) * 0.8;
      }
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final shader = LinearGradient(colors: [color.withValues(alpha: 0.0), color, color.withValues(alpha: 0.1)]).createShader(Offset.zero & s);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    if (alive) {
      c.drawCircle(Offset(head, mid), 3, Paint()..color = Colors.white);
      c.drawCircle(Offset(head, mid), 7, Paint()..color = color.withValues(alpha: 0.3));
    } else {
      c.drawCircle(Offset(s.width - 4, mid), 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t || old.alive != alive || old.color != color;
}

/// Фон темы: мягкие подвижные «шары» или цифровой дождь.
class AmbientBackground extends StatelessWidget {
  final NlTheme theme;
  const AmbientBackground({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    switch (theme.bgStyle) {
      case Bg.orbs:
        return IgnorePointer(child: RepaintBoundary(child: _Orbs(theme: theme)));
      case Bg.rain:
        return IgnorePointer(child: RepaintBoundary(child: _Rain(color: theme.rainColor)));
      case Bg.none:
        return const SizedBox.shrink();
    }
  }
}

class _Orbs extends StatefulWidget {
  final NlTheme theme;
  const _Orbs({required this.theme});

  @override
  State<_Orbs> createState() => _OrbsState();
}

class _OrbsState extends State<_Orbs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(painter: _OrbsPainter(_c.value, widget.theme.accent, widget.theme.accent2), size: Size.infinite),
    );
  }
}

class _OrbsPainter extends CustomPainter {
  final double t;
  final Color a;
  final Color b;
  _OrbsPainter(this.t, this.a, this.b);

  @override
  void paint(Canvas c, Size s) {
    void orb(double fx, double fy, double r, Color col, double ph) {
      final ctr = Offset(s.width * (fx + 0.12 * sin(t * 2 * pi + ph)), s.height * (fy + 0.1 * cos(t * 2 * pi * 1.0 + ph * 1.7)));
      final rad = max(s.width, s.height) * r;
      c.drawCircle(
        ctr,
        rad,
        Paint()..shader = RadialGradient(colors: [col.withValues(alpha: 0.20), Colors.transparent]).createShader(Rect.fromCircle(center: ctr, radius: rad)),
      );
    }

    orb(0.15, 0.2, 0.45, a, 0);
    orb(0.85, 0.75, 0.5, b, 2.1);
    orb(0.55, 0.05, 0.3, a, 4.2);
  }

  @override
  bool shouldRepaint(covariant _OrbsPainter old) => old.t != t;
}

class _Rain extends StatefulWidget {
  final Color color;
  const _Rain({required this.color});

  @override
  State<_Rain> createState() => _RainState();
}

class _RainState extends State<_Rain> {
  Timer? _timer;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 45), (_) {
      if (mounted) setState(() => _t = DateTime.now().millisecondsSinceEpoch / 1000.0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RainPainter(_t, widget.color), size: Size.infinite);
  }
}

class _RainPainter extends CustomPainter {
  final double t;
  final Color color;
  _RainPainter(this.t, this.color);

  static const String _glyphs = 'ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ0123456789ABCDEFXYZ<>+=*';
  static final Map<String, TextPainter> _cache = {};

  TextPainter _tp(int gi, int bucket, bool head) {
    final key = '${color.hashCode}:$gi:$bucket:$head';
    return _cache.putIfAbsent(key, () {
      final al = head ? 1.0 : (0.12 + 0.88 * bucket / 7.0);
      final col = head ? Colors.white.withValues(alpha: 0.95) : color.withValues(alpha: al);
      final tp = TextPainter(
        text: TextSpan(text: _glyphs[gi % _glyphs.length], style: TextStyle(color: col, fontSize: 16, fontFamily: 'monospace', height: 1.0)),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  @override
  void paint(Canvas c, Size s) {
    const cell = 20.0;
    final cols = (s.width / cell).floor();
    final rows = (s.height / cell).ceil();
    for (var i = 0; i < cols; i++) {
      final speed = 5 + (i * 37 % 60) / 8.0; // ячеек в секунду
      final len = 7 + (i * 13) % 13;
      final span = rows + len + 6;
      final off = (i * 97 % 211) / 211.0 * span;
      final head = (t * speed + off) % span;
      for (var k = 0; k < len; k++) {
        final row = head.floor() - k;
        if (row < 0 || row >= rows) continue;
        final bucket = (7 - (k * 7 / len)).clamp(0, 7).floor();
        final gi = ((i * 31 + row * 17 + (t * (k == 0 ? 9 : 1.5)).floor()) % _glyphs.length);
        _tp(gi, bucket, k == 0).paint(c, Offset(i * cell + 2, row * cell));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter old) => old.t != t || old.color != color;
}

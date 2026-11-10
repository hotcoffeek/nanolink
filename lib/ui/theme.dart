import 'package:flutter/material.dart';

enum Bg { none, orbs, rain }

class NlTheme {
  final String id;
  final String name;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color accent;
  final Color accent2;
  final Color text;
  final Color muted;
  final Bg bgStyle;
  final Color rainColor;

  const NlTheme({
    required this.id,
    required this.name,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.accent,
    required this.accent2,
    this.text = const Color(0xFFF2F4F8),
    this.muted = const Color(0xFF8A92A3),
    this.bgStyle = Bg.none,
    this.rainColor = const Color(0xFF00FF66),
  });

  Color get border => Colors.white.withValues(alpha: 0.07);
  LinearGradient get gradient => LinearGradient(colors: [accent, accent2], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

const List<NlTheme> kThemes = [
  NlTheme(
    id: 'oled',
    name: 'OLED Black',
    bg: Color(0xFF000000),
    surface: Color(0xFF0B0B0D),
    surface2: Color(0xFF151518),
    accent: Color(0xFF1E90FF),
    accent2: Color(0xFF00C6FF),
  ),
  NlTheme(
    id: 'midnight',
    name: 'Midnight',
    bg: Color(0xFF05070F),
    surface: Color(0xFF0C1120),
    surface2: Color(0xFF141B30),
    accent: Color(0xFF5B8CFF),
    accent2: Color(0xFF9D7BFF),
    bgStyle: Bg.orbs,
  ),
  NlTheme(
    id: 'aurora',
    name: 'Aurora',
    bg: Color(0xFF020A0B),
    surface: Color(0xFF08181A),
    surface2: Color(0xFF0F2427),
    accent: Color(0xFF14D6A6),
    accent2: Color(0xFF2BA4FF),
    bgStyle: Bg.orbs,
  ),
  NlTheme(
    id: 'crimson',
    name: 'Crimson',
    bg: Color(0xFF000000),
    surface: Color(0xFF0E0809),
    surface2: Color(0xFF1A0E10),
    accent: Color(0xFFB3123A),
    accent2: Color(0xFFFF4D6D),
  ),
  NlTheme(
    id: 'violet',
    name: 'Violet Neon',
    bg: Color(0xFF07040F),
    surface: Color(0xFF110B22),
    surface2: Color(0xFF1B1235),
    accent: Color(0xFF8B5CF6),
    accent2: Color(0xFFEC4899),
    bgStyle: Bg.orbs,
  ),
  NlTheme(
    id: 'emerald',
    name: 'Emerald',
    bg: Color(0xFF000000),
    surface: Color(0xFF07110C),
    surface2: Color(0xFF0D1D15),
    accent: Color(0xFF22C55E),
    accent2: Color(0xFF84CC16),
  ),
  NlTheme(
    id: 'amber',
    name: 'Amber',
    bg: Color(0xFF000000),
    surface: Color(0xFF110C05),
    surface2: Color(0xFF1D1409),
    accent: Color(0xFFF59E0B),
    accent2: Color(0xFFFF6B35),
  ),
  NlTheme(
    id: 'matrix',
    name: 'Matrix',
    bg: Color(0xFF000000),
    surface: Color(0xCC050A06),
    surface2: Color(0xCC0A140C),
    accent: Color(0xFF00C853),
    accent2: Color(0xFF69F0AE),
    bgStyle: Bg.rain,
    rainColor: Color(0xFF00FF66),
  ),
  NlTheme(
    id: 'rain_blue',
    name: 'Rain Blue',
    bg: Color(0xFF000000),
    surface: Color(0xCC040810),
    surface2: Color(0xCC081020),
    accent: Color(0xFF2F80FF),
    accent2: Color(0xFF00E5FF),
    bgStyle: Bg.rain,
    rainColor: Color(0xFF2F9BFF),
  ),
  NlTheme(
    id: 'rain_red',
    name: 'Rain Crimson',
    bg: Color(0xFF000000),
    surface: Color(0xCC0C0405),
    surface2: Color(0xCC180A0C),
    accent: Color(0xFFB3123A),
    accent2: Color(0xFFFF5C7A),
    bgStyle: Bg.rain,
    rainColor: Color(0xFFFF2D55),
  ),
];

NlTheme themeById(String id) {
  for (final t in kThemes) {
    if (t.id == id) return t;
  }
  return kThemes.first;
}

ThemeData buildTheme(NlTheme t) {
  final scheme = ColorScheme.dark(
    primary: t.accent,
    secondary: t.accent2,
    surface: t.surface,
    onSurface: t.text,
    onPrimary: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.surface,
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: t.border)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surface2,
      contentTextStyle: TextStyle(color: t.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.accent)),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : Colors.transparent),
      side: BorderSide(color: t.muted, width: 1.4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : t.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : t.surface2),
    ),
    dividerColor: t.border,
    textTheme: Typography.whiteMountainView.apply(bodyColor: t.text, displayColor: t.text),
  );
}

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/models.dart';
import '../core/state.dart';
import 'theme.dart';

/// Тема (меняется редко - подписка только на смену темы).
class NlScope extends InheritedWidget {
  final NlTheme theme;
  const NlScope({super.key, required this.theme, required super.child});

  static NlTheme of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<NlScope>()!.theme;

  @override
  bool updateShouldNotify(NlScope old) => old.theme.id != theme.id;
}

/// Доступ к состоянию без подписки (подписываемся точечно через ListenableBuilder).
class AppScope extends InheritedWidget {
  final AppState state;
  const AppScope({super.key, required this.state, required super.child});

  static AppState of(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.state;

  @override
  bool updateShouldNotify(AppScope old) => false;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.color,
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? t.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? t.border),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool compact;
  const GradientButton({super.key, required this.label, this.icon, this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          onTap: onTap,
          child: Ink(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22, vertical: compact ? 9 : 14),
            decoration: BoxDecoration(
              gradient: t.gradient,
              borderRadius: BorderRadius.circular(compact ? 12 : 16),
              boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: compact ? 17 : 20, color: Colors.white), const SizedBox(width: 8)],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: compact ? 13 : 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SoftButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;
  const SoftButton({super.key, required this.label, this.icon, this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? t.accent.withValues(alpha: 0.18) : t.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? t.accent.withValues(alpha: 0.7) : t.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: selected ? t.accent2 : t.muted), const SizedBox(width: 6)],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final String? tip;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  const IconBtn({super.key, required this.icon, this.tip, this.onTap, this.active = false, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final t = NlScope.of(context);
    final w = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: size, color: onTap == null ? t.muted.withValues(alpha: 0.4) : (active ? t.accent2 : t.muted)),
        ),
      ),
    );
    return tip == null ? w : Tooltip(message: tip!, child: w);
  }
}

class PulseDot extends StatelessWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 9});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
      ),
    );
  }
}

IconData kindIcon(DeviceKind k) {
  switch (k) {
    case DeviceKind.thisDevice:
      return Icons.home_rounded;
    case DeviceKind.pc:
      return Icons.desktop_windows_rounded;
    case DeviceKind.laptop:
      return Icons.laptop_rounded;
    case DeviceKind.phone:
      return Icons.smartphone_rounded;
    case DeviceKind.tablet:
      return Icons.tablet_android_rounded;
    case DeviceKind.tv:
      return Icons.tv_rounded;
    case DeviceKind.steamDeck:
      return Icons.sports_esports_rounded;
    case DeviceKind.nas:
      return Icons.storage_rounded;
    case DeviceKind.router:
      return Icons.router_rounded;
    case DeviceKind.printer:
      return Icons.print_rounded;
    case DeviceKind.server:
      return Icons.dns_rounded;
    case DeviceKind.unknown:
      return Icons.devices_other_rounded;
  }
}

String kindLabel(DeviceKind k) {
  switch (k) {
    case DeviceKind.thisDevice:
      return tr('Это устройство', 'This device');
    case DeviceKind.pc:
      return tr('Компьютер', 'Computer');
    case DeviceKind.laptop:
      return tr('Ноутбук', 'Laptop');
    case DeviceKind.phone:
      return tr('Телефон', 'Phone');
    case DeviceKind.tablet:
      return tr('Планшет', 'Tablet');
    case DeviceKind.tv:
      return tr('ТВ / приставка', 'TV / box');
    case DeviceKind.steamDeck:
      return 'Steam Deck';
    case DeviceKind.nas:
      return 'NAS';
    case DeviceKind.router:
      return tr('Роутер', 'Router');
    case DeviceKind.printer:
      return tr('Принтер', 'Printer');
    case DeviceKind.server:
      return tr('Сервер', 'Server');
    case DeviceKind.unknown:
      return tr('Устройство', 'Device');
  }
}

IconData placeIcon(String k) {
  switch (k) {
    case 'desktop':
      return Icons.desktop_windows_outlined;
    case 'downloads':
      return Icons.download_rounded;
    case 'documents':
      return Icons.description_outlined;
    case 'pictures':
      return Icons.photo_outlined;
    case 'videos':
      return Icons.movie_outlined;
    case 'music':
      return Icons.music_note_rounded;
  }
  return Icons.folder_outlined;
}

class FileStyle {
  final IconData icon;
  final Color color;
  const FileStyle(this.icon, this.color);
}

FileStyle fileStyle(FsEntry e) {
  if (e.isDir) return const FileStyle(Icons.folder_rounded, Color(0xFFFFC857));
  switch (e.ext) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'heic':
    case 'bmp':
      return const FileStyle(Icons.image_rounded, Color(0xFF4FC3F7));
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
    case 'webm':
    case '3gp':
      return const FileStyle(Icons.movie_rounded, Color(0xFFBA68C8));
    case 'mp3':
    case 'flac':
    case 'wav':
    case 'm4a':
    case 'ogg':
    case 'aac':
    case 'opus':
      return const FileStyle(Icons.music_note_rounded, Color(0xFF66BB6A));
    case 'pdf':
      return const FileStyle(Icons.picture_as_pdf_rounded, Color(0xFFEF5350));
    case 'doc':
    case 'docx':
    case 'txt':
    case 'rtf':
    case 'odt':
      return const FileStyle(Icons.description_rounded, Color(0xFF42A5F5));
    case 'xls':
    case 'xlsx':
    case 'csv':
      return const FileStyle(Icons.table_chart_rounded, Color(0xFF26A69A));
    case 'ppt':
    case 'pptx':
      return const FileStyle(Icons.slideshow_rounded, Color(0xFFFF7043));
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return const FileStyle(Icons.folder_zip_rounded, Color(0xFFFFB74D));
    case 'apk':
      return const FileStyle(Icons.android_rounded, Color(0xFF9CCC65));
    case 'exe':
    case 'msi':
    case 'bat':
      return const FileStyle(Icons.settings_applications_rounded, Color(0xFF90A4AE));
    case 'nlpart':
      return const FileStyle(Icons.downloading_rounded, Color(0xFF8A92A3));
  }
  return const FileStyle(Icons.insert_drive_file_rounded, Color(0xFF9AA4B5));
}

void toast(BuildContext context, String msg) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

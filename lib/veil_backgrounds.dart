import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'veil_theme.dart';

class VeilBackground extends StatelessWidget {
  final bool isDark;
  final int screenIndex; // 0=Chats 1=Groups 2=Encrypt 3=Stego 4=Settings 99=ChatDetail

  const VeilBackground({super.key, required this.isDark, required this.screenIndex});

  // Map each screen to its background image
  String? _assetForScreen() {
    switch (screenIndex) {
      case 0:  return isDark ? 'assets/images/chat_dark.jpg'     : 'assets/images/chat_light.jpg';
      case 1:  return isDark ? 'assets/images/group_dark.jpg'    : 'assets/images/group_light.jpg';
      case 2:  return isDark ? 'assets/images/encrypt_dark.jpg'  : 'assets/images/encrypt_light.jpg';
      case 3:  return isDark ? 'assets/images/stego_dark.jpg'    : 'assets/images/stego_light.jpg';
      case 4:  return isDark ? 'assets/images/settings_dark.jpg' : 'assets/images/settings_light.jpg';
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Custom chat wallpaper (per-contact)
    if (screenIndex == 99 && VeilTheme.chatBgPath != null) {
      final f = File(VeilTheme.chatBgPath!);
      if (f.existsSync()) return _img(FileImage(f));
    }
    // Custom main wallpaper override
    if (screenIndex != 99 && VeilTheme.useCustomBg && VeilTheme.customBgPath != null) {
      final f = File(VeilTheme.customBgPath!);
      if (f.existsSync()) return _img(FileImage(f));
    }
    // Use per-screen asset image
    final asset = _assetForScreen();
    if (asset != null) {
      return _img(AssetImage(asset));
    }
    // Fallback: procedural
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BgPainter(
            isDark: isDark,
            style: VeilTheme.currentWallpaper,
            accent: VeilTheme.accentColor),
      ),
    );
  }

  Widget _img(ImageProvider p) => Stack(fit: StackFit.expand, children: [
    Image(
      image: p,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true, // prevents flicker on rebuild
    ),
    Container(color: Colors.black.withOpacity(isDark ? 0.55 : 0.15)),
  ]);
}

class _BgPainter extends CustomPainter {
  final bool isDark;
  final WallpaperStyle style;
  final Color accent;
  _BgPainter({required this.isDark, required this.style, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _base(canvas, rect);
    final rng = Random(42);
    switch (style) {
      case WallpaperStyle.cosmos:   _cosmos(canvas, size, rng); break;
      case WallpaperStyle.mesh:     _mesh(canvas, size); break;
      case WallpaperStyle.nebula:   _nebula(canvas, size, rng); break;
      case WallpaperStyle.circuits: _circuits(canvas, size, rng); break;
      case WallpaperStyle.aurora:   _aurora(canvas, size); break;
      case WallpaperStyle.matrix:   _matrix(canvas, size, rng); break;
    }
  }

  void _base(Canvas canvas, Rect rect) => canvas.drawRect(rect, Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: isDark
          ? [const Color(0xFF020510), const Color(0xFF0A0F1E), const Color(0xFF050A18)]
          : [const Color(0xFFF0F4FF), const Color(0xFFE8F0FF), const Color(0xFFF5F0FF)],
    ).createShader(rect));

  void _cosmos(Canvas canvas, Size size, Random rng) {
    if (isDark) for (int i = 0; i < 70; i++) canvas.drawCircle(
      Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), rng.nextDouble() * 1.5 + 0.3,
      Paint()..color = Colors.white.withOpacity(rng.nextDouble() * 0.6 + 0.1));
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.15), 120, Paint()..color = accent.withOpacity(0.05));
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.8), 100, Paint()..color = VeilTheme.neonPurple.withOpacity(0.04));
  }

  void _mesh(Canvas canvas, Size size) {
    final p = Paint()..color = accent.withOpacity(0.08)..strokeWidth = 0.5..style = PaintingStyle.stroke;
    const s = 40.0;
    for (double x = 0; x < size.width; x += s) canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += s) canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    final d = Paint()..color = accent.withOpacity(0.10);
    for (double x = 0; x < size.width; x += s) for (double y = 0; y < size.height; y += s) canvas.drawCircle(Offset(x, y), 1.5, d);
  }

  void _nebula(Canvas canvas, Size size, Random rng) {
    final orbs = [[0.5, 0.3, 180.0, accent], [0.2, 0.6, 120.0, VeilTheme.neonPurple], [0.8, 0.7, 100.0, accent], [0.1, 0.2, 80.0, VeilTheme.neonPurple]];
    for (final o in orbs) canvas.drawCircle(
      Offset(size.width * (o[0] as double), size.height * (o[1] as double)), o[2] as double,
      Paint()..color = (o[3] as Color).withOpacity(isDark ? 0.06 : 0.04));
  }

  void _circuits(Canvas canvas, Size size, Random rng) {
    final p = Paint()..color = accent.withOpacity(isDark ? 0.10 : 0.08)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    for (int i = 0; i < 12; i++) {
      double x = rng.nextDouble() * size.width, y = rng.nextDouble() * size.height;
      final path = Path()..moveTo(x, y);
      for (int j = 0; j < 5; j++) {
        final dx = (rng.nextBool() ? 1 : -1) * (20 + rng.nextDouble() * 60);
        final dy = (rng.nextBool() ? 1 : -1) * (20 + rng.nextDouble() * 60);
        if (rng.nextBool()) { path.lineTo(x + dx, y); path.lineTo(x + dx, y + dy); }
        else                { path.lineTo(x, y + dy); path.lineTo(x + dx, y + dy); }
        x += dx; y += dy;
      }
      canvas.drawPath(path, p);
    }
    final d = Paint()..color = accent.withOpacity(0.16);
    for (int i = 0; i < 15; i++) canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), 2.5, d);
  }

  void _aurora(Canvas canvas, Size size) {
    // Wide sweeping aurora bands - visually distinct from cosmos dots
    final auroraColors = isDark
        ? [const Color(0xFF00FF88), const Color(0xFF00CCFF), const Color(0xFF8844FF), const Color(0xFF00FFCC)]
        : [const Color(0xFF44DDAA), const Color(0xFF3399FF), const Color(0xFF9955EE), const Color(0xFF22CCBB)];
    final positions = [0.12, 0.28, 0.48, 0.65, 0.82];
    for (int i = 0; i < positions.length; i++) {
      final yBase = size.height * positions[i];
      final col = auroraColors[i % auroraColors.length];
      for (int layer = 0; layer < 4; layer++) {
        final thickness = (40.0 - layer * 8);
        final opacity = (0.12 - layer * 0.025) * (isDark ? 1.0 : 0.7);
        if (opacity <= 0) continue;
        final path = Path()
          ..moveTo(0, yBase + layer * 4.0)
          ..cubicTo(
            size.width * 0.25, yBase - 30 + layer * 3.0,
            size.width * 0.6,  yBase + 40 + layer * 5.0,
            size.width,        yBase + layer * 4.0,
          )
          ..lineTo(size.width, yBase + thickness + layer * 4.0)
          ..cubicTo(
            size.width * 0.6, yBase + 40 + thickness + layer * 5.0,
            size.width * 0.25, yBase - 30 + thickness + layer * 3.0,
            0, yBase + thickness + layer * 4.0,
          )
          ..close();
        canvas.drawPath(path, Paint()..color = col.withOpacity(opacity));
      }
    }
    // Vertical light rays
    for (int i = 0; i < 8; i++) {
      final x = size.width * (i / 7.0);
      final col2 = auroraColors[i % auroraColors.length];
      final h = size.height * 0.3;
      final rect = Rect.fromLTWH(x - 4, size.height * 0.1, 8, h);
      canvas.drawRect(rect, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [col2.withOpacity(0.0), col2.withOpacity(isDark ? 0.08 : 0.05), col2.withOpacity(0.0)],
        ).createShader(rect));
    }
  }

  void _matrix(Canvas canvas, Size size, Random rng) {
    // Matrix rain: vertical columns of glowing green dots at varying heights
    final green = isDark ? const Color(0xFF00FF41) : const Color(0xFF00AA33);
    const colWidth = 22.0;
    const dotSpacing = 18.0;
    int col = 0;
    for (double x = colWidth / 2; x < size.width; x += colWidth) {
      // Each column starts at a random y offset (like falling rain)
      final startY = rng.nextDouble() * size.height;
      final trailLen = 8 + rng.nextInt(10);
      for (int d = 0; d < trailLen; d++) {
        final y = (startY + d * dotSpacing) % size.height;
        // Head dot is brightest, trail fades
        final brightness = d == 0 ? 0.9 : (1.0 - d / trailLen) * (isDark ? 0.35 : 0.25);
        final radius = d == 0 ? 2.5 : 1.5;
        canvas.drawCircle(
          Offset(x, y), radius,
          Paint()..color = green.withOpacity(brightness),
        );
      }
      // Second trail in same column, offset
      final startY2 = (startY + size.height * 0.6) % size.height;
      final trailLen2 = 5 + rng.nextInt(7);
      for (int d = 0; d < trailLen2; d++) {
        final y = (startY2 + d * dotSpacing) % size.height;
        final brightness = d == 0 ? 0.7 : (1.0 - d / trailLen2) * (isDark ? 0.25 : 0.15);
        canvas.drawCircle(
          Offset(x, y), 1.5,
          Paint()..color = green.withOpacity(brightness),
        );
      }
      col++;
    }
    // Horizontal scan line
    final scanY = size.height * 0.5;
    canvas.drawLine(
      Offset(0, scanY), Offset(size.width, scanY),
      Paint()..color = green.withOpacity(isDark ? 0.06 : 0.04)..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => old.isDark != isDark || old.style != style || old.accent != accent;
}

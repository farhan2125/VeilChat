import 'dart:math';
import 'package:flutter/material.dart';
import 'veil_theme.dart';

// ── Dynamic per-contact chat background ───────────────────────
class DynamicChatPainter extends CustomPainter {
  final bool isDark;
  final String seed;
  final Color themeColor;
  final WallpaperStyle style;

  const DynamicChatPainter({
    required this.isDark,
    required this.seed,
    required this.themeColor,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed.hashCode);
    final rect = Offset.zero & size;

    // Base fill
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF020810),
                  const Color(0xFF0A1020),
                  const Color(0xFF050A18),
                ]
              : [
                  const Color(0xFFF5F8FF),
                  const Color(0xFFEEF3FF),
                  const Color(0xFFF5F0FF),
                ],
        ).createShader(rect),
    );

    switch (style) {
      case WallpaperStyle.cosmos:
        _drawCosmos(canvas, size, rng);
        break;
      case WallpaperStyle.mesh:
        _drawMesh(canvas, size, rng);
        break;
      case WallpaperStyle.nebula:
        _drawNebula(canvas, size, rng);
        break;
      case WallpaperStyle.circuits:
        _drawCircuits(canvas, size, rng);
        break;
      case WallpaperStyle.aurora:
        _drawAurora(canvas, size, rng);
        break;
      case WallpaperStyle.matrix:
        _drawMatrix(canvas, size, rng);
        break;
    }
  }

  // No MaskFilter.blur used anywhere — all effects via opacity circles
  void _drawCosmos(Canvas canvas, Size size, Random rng) {
    // Dots
    for (int i = 0; i < 60; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        rng.nextDouble() * 1.4 + 0.3,
        Paint()
          ..color = Colors.white.withValues(
            alpha: isDark ? rng.nextDouble() * 0.5 + 0.1 : 0.0,
          ),
      );
    }
    // Accent orbs (no blur — just low opacity large circles)
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.15),
      120,
      Paint()..color = themeColor.withValues(alpha: isDark ? 0.05 : 0.04),
    );
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.8),
      100,
      Paint()
        ..color = VeilTheme.neonPurple.withValues(alpha: isDark ? 0.04 : 0.03),
    );
    // Dot grid
    _dotGrid(canvas, size);
  }

  void _drawMesh(Canvas canvas, Size size, Random rng) {
    final p = Paint()
      ..color = themeColor.withValues(alpha: isDark ? 0.07 : 0.06)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const s = 36.0;
    for (double x = 0; x < size.width; x += s) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += s) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final dot = Paint()
      ..color = themeColor.withValues(alpha: isDark ? 0.1 : 0.08);
    for (double x = 0; x < size.width; x += s) {
      for (double y = 0; y < size.height; y += s) {
        canvas.drawCircle(Offset(x, y), 1.5, dot);
      }
    }
  }

  void _drawNebula(Canvas canvas, Size size, Random rng) {
    // Curved bands — NO blur
    for (int i = 0; i < 4; i++) {
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(
        Offset(size.width * rng.nextDouble(), y),
        140.0 + rng.nextDouble() * 80,
        Paint()
          ..color = (i % 2 == 0 ? themeColor : VeilTheme.neonPurple).withValues(
            alpha: isDark ? 0.05 : 0.04,
          ),
      );
    }
    _dotGrid(canvas, size);
  }

  void _drawCircuits(Canvas canvas, Size size, Random rng) {
    final p = Paint()
      ..color = themeColor.withValues(alpha: isDark ? 0.1 : 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < 10; i++) {
      double x = rng.nextDouble() * size.width,
          y = rng.nextDouble() * size.height;
      final path = Path()..moveTo(x, y);
      for (int j = 0; j < 4; j++) {
        final dx = (rng.nextBool() ? 1 : -1) * (20 + rng.nextDouble() * 50);
        final dy = (rng.nextBool() ? 1 : -1) * (20 + rng.nextDouble() * 50);
        if (rng.nextBool()) {
          path.lineTo(x + dx, y);
          path.lineTo(x + dx, y + dy);
        } else {
          path.lineTo(x, y + dy);
          path.lineTo(x + dx, y + dy);
        }
        x += dx;
        y += dy;
      }
      canvas.drawPath(path, p);
    }
    final dot = Paint()..color = themeColor.withValues(alpha: 0.18);
    for (int i = 0; i < 12; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        2.5,
        dot,
      );
    }
  }

  void _drawAurora(Canvas canvas, Size size, Random rng) {
    final bands = [
      [0.15, themeColor, 0.07],
      [0.35, VeilTheme.neonPurple, 0.05],
      [0.55, themeColor, 0.04],
    ];
    for (final b in bands) {
      final yp = b[0] as double;
      final col = b[1] as Color;
      final op = b[2] as double;
      final path = Path()
        ..moveTo(0, size.height * yp)
        ..cubicTo(
          size.width * 0.3,
          size.height * (yp - 0.05),
          size.width * 0.7,
          size.height * (yp + 0.06),
          size.width,
          size.height * yp,
        )
        ..lineTo(size.width, size.height * (yp + 0.14))
        ..cubicTo(
          size.width * 0.7,
          size.height * (yp + 0.18),
          size.width * 0.3,
          size.height * (yp + 0.08),
          0,
          size.height * (yp + 0.14),
        )
        ..close();
      canvas.drawPath(path, Paint()..color = col.withValues(alpha: op));
    }
  }

  void _drawMatrix(Canvas canvas, Size size, Random rng) {
    final p = Paint()
      ..color = const Color(0xFF00FF41).withValues(alpha: isDark ? 0.07 : 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    const col = 28.0;
    for (double x = 0; x < size.width; x += col) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    // Random bright dots
    final dot = Paint()
      ..color = const Color(0xFF00FF41).withValues(alpha: isDark ? 0.18 : 0.12);
    for (int i = 0; i < 40; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        1.5,
        dot,
      );
    }
  }

  void _dotGrid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = themeColor.withValues(alpha: isDark ? 0.04 : 0.035);
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DynamicChatPainter old) =>
      old.isDark != isDark ||
      old.seed != seed ||
      old.themeColor != themeColor ||
      old.style != style;
}

// ── Login background ──────────────────────────────────────────
class BackgroundPainter extends CustomPainter {
  final bool isDark;
  const BackgroundPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader =
            (isDark
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF02050A),
                          Color(0xFF0F172A),
                          Color(0xFF050A18),
                        ],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFFF5F5),
                          Color(0xFFE0F7FA),
                          Color(0xFFF3E5F5),
                        ],
                      ))
                .createShader(rect),
    );

    if (isDark) {
      final beamPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = VeilTheme.neonBlue.withValues(alpha: 0.1);
      for (int i = 0; i < 5; i++) {
        final x = size.width * (0.15 + i * 0.18);
        final h = size.height * (0.35 + (i % 3) * 0.2);
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x, size.height - h),
          beamPaint,
        );
      }
      canvas.drawCircle(
        Offset(size.width * 0.8, size.height * 0.2),
        110,
        Paint()..color = VeilTheme.neonBlue.withValues(alpha: 0.04),
      );
      canvas.drawCircle(
        Offset(size.width * 0.2, size.height * 0.8),
        110,
        Paint()..color = VeilTheme.neonPurple.withValues(alpha: 0.04),
      );
    } else {
      final path = Path()
        ..moveTo(0, size.height * 0.3)
        ..quadraticBezierTo(
          size.width * 0.5,
          size.height * 0.4,
          size.width,
          size.height * 0.2,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundPainter old) => old.isDark != isDark;
}

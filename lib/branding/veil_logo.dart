import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'veil_brand.dart';

/// ─────────────────────────────────────────────────────────────
/// VeilChat logo widget.
///
/// Renders the vector SVG mark from `assets/branding/…` and falls back to a
/// pure-Dart [CustomPainter] if the asset is missing or fails to decode — so
/// the brand never renders as a broken box, even before `flutter pub get`
/// picks up the new asset folder.
/// ─────────────────────────────────────────────────────────────
enum VeilLogoVariant { mark, wordmark, icon }

class VeilLogo extends StatelessWidget {
  final double size;
  final VeilLogoVariant variant;

  /// When true the mark breathes with a soft glow pulse.
  final bool animated;

  const VeilLogo({
    super.key,
    this.size = 96,
    this.variant = VeilLogoVariant.mark,
    this.animated = false,
  });

  const VeilLogo.mark({super.key, this.size = 96, this.animated = false})
      : variant = VeilLogoVariant.mark;

  const VeilLogo.wordmark({super.key, this.size = 220, this.animated = false})
      : variant = VeilLogoVariant.wordmark;

  const VeilLogo.icon({super.key, this.size = 64, this.animated = false})
      : variant = VeilLogoVariant.icon;

  String get _asset {
    switch (variant) {
      case VeilLogoVariant.wordmark:
        return 'assets/branding/veilchat_wordmark.svg';
      case VeilLogoVariant.icon:
        return 'assets/branding/veilchat_icon.svg';
      case VeilLogoVariant.mark:
        return 'assets/branding/veilchat_logo.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double width =
        variant == VeilLogoVariant.wordmark ? size : size;
    final double height =
        variant == VeilLogoVariant.wordmark ? size * (180 / 720) : size;

    Widget child = SvgPicture.asset(
      _asset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      // Graceful degradation: if the asset isn't bundled yet, paint the mark.
      placeholderBuilder: (_) => _VeilLogoFallback(size: size),
    );

    if (animated) {
      child = _PulseGlow(size: size, child: child);
    }

    return SizedBox(width: width, height: height, child: child);
  }
}

/// Soft breathing halo behind the mark — subtle "encrypted heartbeat".
class _PulseGlow extends StatefulWidget {
  final Widget child;
  final double size;
  const _PulseGlow({required this.child, required this.size});

  @override
  State<_PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<_PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    // ✅ Leak fix: controllers must always be disposed.
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: VeilBrand.veilCyan.withValues(alpha: 0.10 + 0.22 * t),
                blurRadius: 24 + 26 * t,
                spreadRadius: 2 + 6 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Pure-Dart fallback so branding survives a missing/corrupt asset.
class _VeilLogoFallback extends StatelessWidget {
  final double size;
  const _VeilLogoFallback({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: VeilLogoPainter(),
    );
  }
}

/// Draws the VeilChat mark: shield/veil silhouette, drape arc, and lock node.
/// Designed on a 512×512 canvas and scaled to fit.
class VeilLogoPainter extends CustomPainter {
  final Color start;
  final Color mid;
  final Color end;

  VeilLogoPainter({
    this.start = VeilBrand.veilIndigo,
    this.mid = VeilBrand.veilCyan,
    this.end = VeilBrand.veilTeal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 512.0;
    canvas.save();
    canvas.scale(scale);

    final rect = const Rect.fromLTWH(0, 0, 512, 512);
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [start, mid, end],
    ).createShader(rect);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..shader = shader;

    // ── Shield / veil silhouette ──────────────────────────────
    final shield = Path()
      ..moveTo(256, 54)
      ..lineTo(406, 112)
      ..cubicTo(406, 112, 410, 268, 384, 330)
      ..cubicTo(358, 392, 300, 428, 256, 448)
      ..cubicTo(212, 428, 154, 392, 128, 330)
      ..cubicTo(102, 268, 106, 112, 106, 112)
      ..close();
    canvas.drawPath(shield, stroke..strokeWidth = 18);

    // Speech-bubble tail
    final tail = Path()
      ..moveTo(232, 430)
      ..lineTo(256, 470)
      ..lineTo(280, 430)
      ..close();
    canvas.drawPath(tail, fill);

    // ── Veil drape arcs ───────────────────────────────────────
    final drape1 = Path()
      ..moveTo(136, 178)
      ..cubicTo(196, 214, 316, 214, 376, 178);
    canvas.drawPath(
      drape1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..color = Colors.white.withValues(alpha: 0.75),
    );

    final drape2 = Path()
      ..moveTo(144, 226)
      ..cubicTo(200, 258, 312, 258, 368, 226);
    canvas.drawPath(
      drape2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    // ── Lock node ─────────────────────────────────────────────
    final shackle = Path()
      ..moveTo(222, 288)
      ..lineTo(222, 266)
      ..cubicTo(222, 247, 237, 232, 256, 232)
      ..cubicTo(275, 232, 290, 247, 290, 266)
      ..lineTo(290, 288);
    canvas.drawPath(shackle, stroke..strokeWidth = 16);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(206, 288, 100, 82),
        const Radius.circular(20),
      ),
      fill,
    );

    // Keyhole
    final keyhole = Paint()..color = VeilBrand.veilVoid;
    canvas.drawCircle(const Offset(256, 320), 11, keyhole);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(250, 326, 12, 24),
        const Radius.circular(6),
      ),
      keyhole,
    );

    // ── Crypto mesh nodes ─────────────────────────────────────
    canvas.drawCircle(const Offset(150, 300), 9, Paint()..color = end);
    canvas.drawCircle(const Offset(362, 300), 9, Paint()..color = start);
    canvas.drawCircle(const Offset(256, 150), 9, Paint()..color = mid);

    final link = Paint()
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..color = mid.withValues(alpha: 0.5);
    canvas.drawLine(const Offset(150, 300), const Offset(206, 320), link);
    canvas.drawLine(const Offset(362, 300), const Offset(306, 320), link);
    canvas.drawLine(const Offset(256, 150), const Offset(256, 232), link);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VeilLogoPainter old) =>
      old.start != start || old.mid != mid || old.end != end;
}

/// Small inline "VeilChat" text lockup for headers/footers where an SVG would
/// be overkill. Uses the brand gradient on the "Chat" half.
class VeilWordmarkText extends StatelessWidget {
  final double fontSize;
  final bool isDark;

  const VeilWordmarkText({
    super.key,
    this.fontSize = 24,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Veil',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.5,
              color: isDark ? VeilBrand.veilFog : VeilBrand.veilInk,
            ),
          ),
          TextSpan(
            text: 'Chat',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: VeilBrand.primaryGradient,
                ).createShader(
                  Rect.fromLTWH(0, 0, fontSize * 3, fontSize),
                ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative rotating "encryption ring" — used behind avatars in call and
/// group headers to signal an active secure session.
class VeilEncryptionRing extends StatefulWidget {
  final double size;
  final Color color;
  final Widget? child;

  const VeilEncryptionRing({
    super.key,
    this.size = 72,
    this.color = VeilBrand.veilTeal,
    this.child,
  });

  @override
  State<VeilEncryptionRing> createState() => _VeilEncryptionRingState();
}

class _VeilEncryptionRingState extends State<VeilEncryptionRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

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
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Transform.rotate(
              angle: _c.value * 2 * math.pi,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _RingPainter(widget.color),
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  _RingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.7);

    // Four dashed arcs — reads as a "scanning" secure ring.
    for (int i = 0; i < 4; i++) {
      final start = (math.pi / 2) * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        math.pi / 3.4,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.color != color;
}

import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────
/// VeilChat — Brand Identity Tokens
///
/// Theme: privacy, stealth, high-tech cryptography, smooth modern
/// communication.
///
/// Palette philosophy:
///   • `veilVoid`   — near-black canvas, the "veil" itself
///   • `veilIndigo` — ambient indigo, the calm cryptographic base
///   • `veilTeal`   — emerald/cyber teal, the "signal" that cuts through
///   • gradients always flow indigo → teal (dark → signal)
/// ─────────────────────────────────────────────────────────────
class VeilBrand {
  VeilBrand._();

  // ── Core brand colors ───────────────────────────────────────
  static const Color veilVoid = Color(0xFF05070F);
  static const Color veilInk = Color(0xFF0B1020);
  static const Color veilSlate = Color(0xFF161B2E);

  static const Color veilIndigo = Color(0xFF6366F1);
  static const Color veilIndigoDeep = Color(0xFF4338CA);
  static const Color veilTeal = Color(0xFF2DD4BF);
  static const Color veilEmerald = Color(0xFF10B981);
  static const Color veilCyan = Color(0xFF22D3EE);

  static const Color veilMist = Color(0xFFF4F7FF);
  static const Color veilFog = Color(0xFFE4EAFB);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);

  // ── Signature gradients ─────────────────────────────────────
  static const List<Color> primaryGradient = [veilIndigo, veilTeal];
  static const List<Color> deepGradient = [
    veilIndigoDeep,
    veilIndigo,
    veilCyan,
  ];
  static const List<Color> stealthGradient = [veilVoid, veilInk, veilSlate];

  static LinearGradient brandSweep({
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
  }) => LinearGradient(begin: begin, end: end, colors: primaryGradient);

  static LinearGradient stealthSweep() => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: stealthGradient,
  );

  // ── Elevation / glow ────────────────────────────────────────
  static List<BoxShadow> glow(
    Color color, {
    double blur = 24,
    double spread = 0,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: 0.35),
      blurRadius: blur,
      spreadRadius: spread,
    ),
  ];

  static List<BoxShadow> softShadow(bool isDark) => [
    BoxShadow(
      color: (isDark ? Colors.black : const Color(0xFF334155)).withValues(
        alpha: isDark ? 0.45 : 0.10,
      ),
      blurRadius: 22,
      offset: const Offset(0, 8),
    ),
  ];

  // ── Motion tokens (used by micro-animations app-wide) ───────
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve springIn = Curves.easeOutBack;
  static const Curve smooth = Curves.easeOutCubic;

  // ── Radii / spacing scale ───────────────────────────────────
  static const double rSm = 12;
  static const double rMd = 18;
  static const double rLg = 24;
  static const double rXl = 32;

  static const double sXs = 4;
  static const double sSm = 8;
  static const double sMd = 16;
  static const double sLg = 24;
  static const double sXl = 32;

  // ── Typography scale ────────────────────────────────────────
  static TextStyle display(bool isDark) => TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: isDark ? Colors.white : veilInk,
  );

  static TextStyle title(bool isDark) => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: isDark ? Colors.white : veilInk,
  );

  static TextStyle body(bool isDark) => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: isDark ? Colors.white70 : const Color(0xFF334155),
  );

  static TextStyle caption(bool isDark) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: isDark ? Colors.white38 : const Color(0xFF64748B),
  );

  /// Section label — uppercase, tracked out. Used across settings/group info.
  static TextStyle sectionLabel(bool isDark, Color accent) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.6,
    color: accent.withValues(alpha: isDark ? 0.85 : 0.9),
  );

  // ── Contrast helper ─────────────────────────────────────────
  /// Returns black or white — whichever has a better contrast ratio against
  /// [background]. Prevents unreadable text on dynamic accent colors.
  static Color onColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? const Color(0xFF0B1020) : Colors.white;
  }
}

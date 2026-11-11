import 'package:flutter/material.dart';

enum WallpaperStyle { cosmos, mesh, nebula, circuits, aurora, matrix }

enum AppTheme { cyberpunk, midnight, rose, emerald, sunset, ocean }

class VeilTheme {
  static Color accentColor = const Color(0xFF00F0FF);
  static WallpaperStyle currentWallpaper = WallpaperStyle.cosmos;
  static AppTheme currentTheme = AppTheme.cyberpunk;

  static String? customBgPath;
  static String? chatBgPath;
  static bool useCustomBg = false;

  // Core colors
  static const Color darkBg = Color(0xFF050A15);
  static const Color neonBlue = Color(0xFF00F0FF);
  static const Color neonPurple = Color(0xFFBC13FE);
  static const Color lightBg = Color(0xFFF2F6FF);
  static const Color holoPink = Color(0xFFFF59B6);
  static const Color holoBlue = Color(0xFF5CA1FF);

  // Theme palettes — dark accent / light accent
  static const Map<AppTheme, List<Color>> _palettes = {
    AppTheme.cyberpunk: [Color(0xFF00F0FF), Color(0xFFFF59B6)],
    AppTheme.midnight: [Color(0xFFBC13FE), Color(0xFF9C27B0)],
    AppTheme.rose: [Color(0xFFFF2D78), Color(0xFFE91E63)],
    AppTheme.emerald: [Color(0xFF00FF88), Color(0xFF00BFA5)],
    AppTheme.sunset: [Color(0xFFFF6B35), Color(0xFFFF5722)],
    AppTheme.ocean: [Color(0xFF5CA1FF), Color(0xFF1976D2)],
  };

  static Map<AppTheme, List<Color>> get themePalettes => _palettes;

  static void applyTheme(AppTheme theme, bool isDark) {
    currentTheme = theme;
    final p = _palettes[theme]!;
    accentColor = isDark ? p[0] : p[1];
  }

  // Text helpers
  static Color text(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF1A202C);
  static Color subText(bool isDark) =>
      isDark ? Colors.white54 : const Color(0xFF4A5568);
  static Color dimText(bool isDark) => isDark ? Colors.white30 : Colors.black38;

  // Bridges
  static Color get holoCyan => accentColor;
  static Color get techAccent => accentColor;

  // Glass decorations
  static BoxDecoration ultraGlass({required bool isDark, double radius = 25}) =>
      BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(
          alpha: isDark ? 0.22 : 0.50,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.blueGrey).withValues(
              alpha: 0.12,
            ),
            blurRadius: 20,
          ),
        ],
      );

  static BoxDecoration glassBox({required bool isDark}) =>
      ultraGlass(isDark: isDark, radius: 20);
}

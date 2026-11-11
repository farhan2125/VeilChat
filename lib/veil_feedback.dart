import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'branding/veil_brand.dart';

/// ─────────────────────────────────────────────────────────────
/// VeilFeedback — one unified, theme-aware, haptic-backed feedback layer.
///
/// Replaces the scattered ad-hoc `ScaffoldMessenger.of(context).showSnackBar`
/// calls across the app. Every call is null-safe and no-ops when the widget is
/// unmounted, which removes a whole class of
/// "setState() called after dispose()" / "Looking up a deactivated widget"
/// exceptions seen in the logs.
/// ─────────────────────────────────────────────────────────────
enum VeilFeedbackKind { success, error, info, warning }

class VeilFeedback {
  VeilFeedback._();

  static void success(BuildContext context, String message) =>
      _show(context, message, VeilFeedbackKind.success);

  static void error(BuildContext context, String message) =>
      _show(context, message, VeilFeedbackKind.error);

  static void info(BuildContext context, String message) =>
      _show(context, message, VeilFeedbackKind.info);

  static void warning(BuildContext context, String message) =>
      _show(context, message, VeilFeedbackKind.warning);

  static void _show(
    BuildContext context,
    String message,
    VeilFeedbackKind kind,
  ) {
    // Guard: context may be gone if an async op finished after a pop.
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final (Color color, IconData icon) = switch (kind) {
      VeilFeedbackKind.success => (
        VeilBrand.success,
        Icons.check_circle_rounded,
      ),
      VeilFeedbackKind.error => (VeilBrand.danger, Icons.error_rounded),
      VeilFeedbackKind.warning => (
        VeilBrand.warning,
        Icons.warning_amber_rounded,
      ),
      VeilFeedbackKind.info => (VeilBrand.info, Icons.info_rounded),
    };

    switch (kind) {
      case VeilFeedbackKind.success:
        HapticFeedback.lightImpact();
      case VeilFeedbackKind.error:
        HapticFeedback.heavyImpact();
      case VeilFeedbackKind.warning:
        HapticFeedback.mediumImpact();
      case VeilFeedbackKind.info:
        HapticFeedback.selectionClick();
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: VeilBrand.veilSlate,
          elevation: 8,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilBrand.rMd),
            side: BorderSide(color: color.withValues(alpha: 0.45), width: 1),
          ),
          content: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              // ✅ RenderFlex fix: text must be flexible inside a Row.
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Themed confirmation dialog with haptics. Returns `true` only when the
  /// user explicitly confirms.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    IconData icon = Icons.help_outline_rounded,
    Color? accent,
    bool destructive = false,
  }) async {
    HapticFeedback.mediumImpact();
    final color =
        accent ?? (destructive ? VeilBrand.danger : VeilBrand.veilTeal);

    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: TweenAnimationBuilder<double>(
          duration: VeilBrand.normal,
          curve: VeilBrand.springIn,
          tween: Tween(begin: 0.92, end: 1),
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: VeilBrand.veilSlate,
              borderRadius: BorderRadius.circular(VeilBrand.rLg),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              boxShadow: VeilBrand.softShadow(true),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(VeilBrand.rSm),
                          ),
                        ),
                        child: Text(
                          cancelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(ctx, true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: VeilBrand.onColor(color),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(VeilBrand.rSm),
                          ),
                        ),
                        child: Text(
                          confirmLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return result ?? false;
  }
}

/// A tap-responsive wrapper that adds a spring scale micro-animation to any
/// child. Used for buttons, tiles and cards across the redesign.
class VeilTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;
  final BorderRadius? borderRadius;

  const VeilTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.borderRadius,
  });

  @override
  State<VeilTapScale> createState() => _VeilTapScaleState();
}

class _VeilTapScaleState extends State<VeilTapScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (mounted && _pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!.call();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: VeilBrand.fast,
        curve: VeilBrand.smooth,
        child: widget.child,
      ),
    );
  }
}

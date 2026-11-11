import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'veil_theme.dart';
import 'veil_feedback.dart';
import 'branding/veil_brand.dart';

// ── 1. HEADER ─────────────────────────────────────────────────
class VeilHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final IconData icon;
  const VeilHeader({
    super.key,
    required this.title,
    required this.isDark,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: VeilTheme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: VeilTheme.accentColor, size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: VeilTheme.text(isDark),
                letterSpacing: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 2. GLASS CONTAINER ────────────────────────────────────────
class VeilGlassContainer extends StatelessWidget {
  final bool isDark;
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  const VeilGlassContainer({
    super.key,
    required this.isDark,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(25),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : Colors.blueGrey).withValues(
                  alpha: 0.12,
                ),
                blurRadius: 20,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── 3. TEXT FIELD ─────────────────────────────────────────────
class VeilTextField extends StatefulWidget {
  final bool isDark;
  final String label;
  final bool isPassword;
  final int maxLines;
  final IconData? prefixIcon;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  const VeilTextField({
    super.key,
    required this.isDark,
    required this.label,
    this.isPassword = false,
    this.maxLines = 1,
    this.prefixIcon,
    this.controller,
    this.onChanged,
    this.hintText,
  });

  @override
  State<VeilTextField> createState() => _VeilTextFieldState();
}

class _VeilTextFieldState extends State<VeilTextField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = VeilTheme.accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              color: _focused ? c : VeilTheme.subText(widget.isDark),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFFE8ECF4).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _focused
                  ? c
                  : (widget.isDark ? Colors.white10 : Colors.black12),
              width: _focused ? 1.5 : 1.0,
            ),
            boxShadow: _focused
                ? [BoxShadow(color: c.withValues(alpha: 0.15), blurRadius: 12)]
                : [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.isPassword && _obscure,
            maxLines: widget.isPassword ? 1 : widget.maxLines,
            style: TextStyle(
              color: VeilTheme.text(widget.isDark),
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
            cursorColor: c,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText:
                  widget.hintText ??
                  (widget.maxLines == 1
                      ? 'Enter ${widget.label.toLowerCase()}...'
                      : null),
              hintStyle: TextStyle(
                color: widget.isDark ? Colors.white24 : Colors.black26,
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: _focused
                          ? c
                          : (widget.isDark ? Colors.white38 : Colors.black38),
                      size: 20,
                    )
                  : null,
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: widget.isDark ? Colors.white38 : Colors.black38,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 4. BUTTON ─────────────────────────────────────────────────
class VeilButton extends StatelessWidget {
  final bool isDark;
  final String label;
  final VoidCallback onTap;
  final List<Color> gradient;
  final bool isOutlined;
  final IconData? icon;
  const VeilButton({
    super.key,
    required this.isDark,
    required this.label,
    required this.onTap,
    required this.gradient,
    this.isOutlined = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (isOutlined) {
      return VeilTapScale(
        onTap: onTap,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: icon != null
              ? Icon(icon, size: 18, color: gradient.first)
              : const SizedBox.shrink(),
          label: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              fontSize: 13,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: gradient.last.withValues(alpha: 0.6),
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            foregroundColor: VeilTheme.text(isDark),
          ),
        ),
      );
    }
    final fgColor = VeilBrand.onColor(gradient.first);
    return VeilTapScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fgColor, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fgColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 4B. TELEMETRY BADGE / PILL ────────────────────────────────
class VeilBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool isDark;

  const VeilBadge({
    super.key,
    required this.label,
    required this.color,
    required this.isDark,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(VeilBrand.rSm),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : VeilBrand.veilInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 5. SECTION LABEL ──────────────────────────────────────────
class VeilSectionLabel extends StatelessWidget {
  final String label;
  const VeilSectionLabel(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: VeilTheme.accentColor,
        letterSpacing: 1.5,
      ),
    ),
  );
}

// ── 6. SHIELD ICON ────────────────────────────────────────────
class ShieldIcon extends StatelessWidget {
  final bool isDark;
  const ShieldIcon({super.key, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: isDark ? VeilTheme.neonBlue : VeilTheme.holoPink,
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: VeilTheme.accentColor.withValues(alpha: 0.25),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Icon(
      Icons.shield_outlined,
      size: 36,
      color: isDark ? VeilTheme.neonBlue : VeilTheme.holoPink,
    ),
  );
}

// ── 7. ONLINE DOT ─────────────────────────────────────────────
class OnlineDot extends StatelessWidget {
  final bool isOnline;
  const OnlineDot({super.key, required this.isOnline});
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: isOnline ? Colors.greenAccent : Colors.grey,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black26, width: 1),
      boxShadow: isOnline
          ? [
              BoxShadow(
                color: Colors.greenAccent.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ]
          : [],
    ),
  );
}

// ── 8. VEIL AVATAR ────────────────────────────────────────────
class VeilAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final bool showOnline;
  final bool isOnline;
  final String? imagePath; // local file path for profile picture
  const VeilAvatar({
    super.key,
    required this.name,
    this.radius = 22,
    this.showOnline = false,
    this.isOnline = false,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    // Check if image file exists
    ImageProvider? image;
    if (imagePath != null && imagePath!.isNotEmpty) {
      final f = File(imagePath!);
      if (f.existsSync()) image = FileImage(f);
    }
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: VeilTheme.accentColor.withValues(alpha: 0.15),
          backgroundImage: image,
          child: image == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: radius * 0.85,
                    fontWeight: FontWeight.bold,
                    color: VeilTheme.accentColor,
                  ),
                )
              : null,
        ),
        if (showOnline)
          Positioned(right: 0, bottom: 0, child: OnlineDot(isOnline: isOnline)),
      ],
    );
  }
}

// ── 9. EMPTY STATE ────────────────────────────────────────────
class VeilEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isDark;

  const VeilEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VeilTheme.accentColor.withValues(alpha: 0.12),
                border: Border.all(
                  color: VeilTheme.accentColor.withValues(alpha: 0.28),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: VeilTheme.accentColor.withValues(alpha: 0.15),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(icon, size: 36, color: VeilTheme.accentColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: VeilTheme.text(isDark),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: VeilTheme.subText(isDark),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              VeilButton(
                isDark: isDark,
                label: actionLabel!,
                onTap: onAction!,
                gradient: VeilBrand.primaryGradient,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 10. LOADING INDICATOR ─────────────────────────────────────
class VeilLoadingIndicator extends StatelessWidget {
  final String? message;
  final bool isDark;

  const VeilLoadingIndicator({super.key, this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(VeilTheme.accentColor),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: VeilTheme.subText(isDark),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 11. ERROR CARD ────────────────────────────────────────────
class VeilErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isDark;

  const VeilErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: VeilBrand.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VeilBrand.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: VeilBrand.danger,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 13.5,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: VeilBrand.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 12. CARD CONTAINER ────────────────────────────────────────
class VeilCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const VeilCard({
    super.key,
    required this.child,
    required this.isDark,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? VeilBrand.veilInk : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: VeilBrand.softShadow(isDark),
      ),
      child: child,
    );

    if (onTap == null) return cardContent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: cardContent,
      ),
    );
  }
}

// ── 13. SNACK BAR HELPER ──────────────────────────────────────
void showVeilSnack(
  BuildContext context,
  String message, {
  Color color = Colors.green,
  IconData icon = Icons.check_circle,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Flexible(child: Text(message)),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(15),
      duration: const Duration(seconds: 2),
    ),
  );
}

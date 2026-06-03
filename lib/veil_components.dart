import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'veil_theme.dart';

// ── 1. HEADER ─────────────────────────────────────────────────
class VeilHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final IconData icon;
  const VeilHeader({super.key, required this.title, required this.isDark, required this.icon});

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
              color: VeilTheme.accentColor.withOpacity(0.15),
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
            color: isDark ? Colors.black.withOpacity(0.25) : Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : Colors.blueGrey).withOpacity(0.12),
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
    _focus.addListener(() { if (mounted) setState(() => _focused = _focus.hasFocus); });
  }

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

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
              fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.black.withOpacity(0.3) : const Color(0xFFE8ECF4).withOpacity(0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _focused ? c : (widget.isDark ? Colors.white10 : Colors.black12),
              width: _focused ? 1.5 : 1.0,
            ),
            boxShadow: _focused ? [BoxShadow(color: c.withOpacity(0.15), blurRadius: 12)] : [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.isPassword && _obscure,
            maxLines: widget.isPassword ? 1 : widget.maxLines,
            style: TextStyle(color: VeilTheme.text(widget.isDark), fontWeight: FontWeight.w500, fontSize: 15),
            cursorColor: c,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: widget.hintText ?? (widget.maxLines == 1 ? 'Enter ${widget.label.toLowerCase()}...' : null),
              hintStyle: TextStyle(color: widget.isDark ? Colors.white24 : Colors.black26, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, color: _focused ? c : (widget.isDark ? Colors.white38 : Colors.black38), size: 20)
                  : null,
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: widget.isDark ? Colors.white38 : Colors.black38, size: 20),
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
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: icon != null ? Icon(icon, size: 18, color: gradient.first) : const SizedBox.shrink(),
        label: Text(label.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: gradient.last.withOpacity(0.6), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          foregroundColor: VeilTheme.text(isDark),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: gradient.last.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))],
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
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
                Text(label.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
              ],
            ),
          ),
        ),
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
    child: Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: VeilTheme.accentColor, letterSpacing: 1.5)),
  );
}

// ── 6. SHIELD ICON ────────────────────────────────────────────
class ShieldIcon extends StatelessWidget {
  final bool isDark;
  const ShieldIcon({super.key, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    width: 72, height: 72,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: isDark ? VeilTheme.neonBlue : VeilTheme.holoPink, width: 2),
      boxShadow: [BoxShadow(color: VeilTheme.accentColor.withOpacity(0.25), blurRadius: 20, spreadRadius: 2)],
    ),
    child: Icon(Icons.shield_outlined, size: 36, color: isDark ? VeilTheme.neonBlue : VeilTheme.holoPink),
  );
}

// ── 7. ONLINE DOT ─────────────────────────────────────────────
class OnlineDot extends StatelessWidget {
  final bool isOnline;
  const OnlineDot({super.key, required this.isOnline});
  @override
  Widget build(BuildContext context) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(
      color: isOnline ? Colors.greenAccent : Colors.grey,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black26, width: 1),
      boxShadow: isOnline ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.5), blurRadius: 6)] : [],
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
          backgroundColor: VeilTheme.accentColor.withOpacity(0.15),
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

// ── 9. SNACK BAR ──────────────────────────────────────────────
void showVeilSnack(BuildContext context, String message, {Color color = Colors.green, IconData icon = Icons.check_circle}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 10), Flexible(child: Text(message))]),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(15),
    duration: const Duration(seconds: 2),
  ));
}

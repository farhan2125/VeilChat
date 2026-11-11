import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'veil_theme.dart';
import 'services/network_service.dart';

/// Per-chat PIN lock screen.
/// Shows a numeric PIN pad before allowing access to a locked chat.
/// PIN is stored as SHA-256 hash per (owner, contact) in SharedPreferences.
class ChatLockScreen extends StatefulWidget {
  final String contactName;
  final String? myUsername;
  final bool isDark;
  final Widget child; // The actual chat screen

  const ChatLockScreen({
    super.key,
    required this.contactName,
    this.myUsername,
    required this.isDark,
    required this.child,
  });

  static String _prefKey(String contact, [String? owner]) {
    final user = (owner != null && owner.isNotEmpty)
        ? owner
        : (NetworkService().currentUser ?? 'global');
    return 'chat_lock_pin_${user}_$contact';
  }

  /// Check if a contact has a lock set
  static Future<bool> isLocked(String contact, [String? owner]) async {
    final prefs = await SharedPreferences.getInstance();
    // Clean up legacy corrupted key so old typo never locks unconfigured chats
    const legacyKey = 'chat_lock_pin_\$contact';
    if (prefs.containsKey(legacyKey)) {
      await prefs.remove(legacyKey);
    }
    return prefs.containsKey(_prefKey(contact, owner));
  }

  /// Set PIN for a contact (null to remove)
  static Future<void> setPin(
    String contact,
    String? pin, [
    String? owner,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    const legacyKey = 'chat_lock_pin_\$contact';
    if (prefs.containsKey(legacyKey)) {
      await prefs.remove(legacyKey);
    }
    final key = _prefKey(contact, owner);
    if (pin == null) {
      await prefs.remove(key);
    } else {
      final hash = sha256.convert(utf8.encode(pin)).toString();
      await prefs.setString(key, hash);
    }
  }

  @override
  State<ChatLockScreen> createState() => _ChatLockScreenState();
}

class _ChatLockScreenState extends State<ChatLockScreen>
    with SingleTickerProviderStateMixin {
  String _entered = '';
  bool _isUnlocked = false;
  bool _hasLock = false;
  bool _error = false;
  bool _verifying = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));
    _checkLock();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkLock() async {
    final locked = await ChatLockScreen.isLocked(
      widget.contactName,
      widget.myUsername,
    );
    if (mounted) setState(() => _hasLock = locked);
  }

  Future<void> _onDigit(String digit) async {
    if (_entered.length >= 4) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    HapticFeedback.lightImpact();
    if (_entered.length == 4) await _verify();
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
    HapticFeedback.lightImpact();
  }

  Future<void> _onSubmit() async {
    if (_entered.length < 4) {
      HapticFeedback.heavyImpact();
      setState(() => _error = true);
      _shakeCtrl.forward(from: 0);
      return;
    }
    await _verify();
  }

  Future<void> _verify() async {
    if (_verifying) return;
    _verifying = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = ChatLockScreen._prefKey(
        widget.contactName,
        widget.myUsername,
      );
      final stored = prefs.getString(key);
      final hash = sha256.convert(utf8.encode(_entered)).toString();
      if (hash == stored) {
        HapticFeedback.mediumImpact();
        if (mounted) setState(() => _isUnlocked = true);
      } else {
        HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _error = true;
            _entered = '';
          });
        }
        _shakeCtrl.forward(from: 0);
      }
    } catch (e) {
      debugPrint('❌ PIN verify failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not verify PIN. Try again.')),
        );
      }
    } finally {
      _verifying = false;
    }
  }

  Future<void> _showResetDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
        title: Text(
          'Reset Chat Lock?',
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
        ),
        content: Text(
          'Remove the PIN lock for "${widget.contactName}"? You will regain instant access to this chat.',
          style: TextStyle(
            color: widget.isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'RESET LOCK',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ChatLockScreen.setPin(widget.contactName, null, widget.myUsername);
      setState(() => _isUnlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasLock || _isUnlocked) return widget.child;
    final themeColor = VeilTheme.accentColor;

    return Scaffold(
      backgroundColor: widget.isDark
          ? const Color(0xFF050A15)
          : const Color(0xFFF2F6FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compact lock icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(Icons.lock_rounded, color: themeColor, size: 36),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.contactName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter PIN to unlock',
                  style: TextStyle(
                    color: widget.isDark ? Colors.white38 : Colors.black38,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                // PIN dots
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(
                      _error
                          ? (_shakeAnim.value *
                                10 *
                                ((_shakeAnim.value * 4).toInt() % 2 == 0
                                    ? 1
                                    : -1))
                          : 0,
                      0,
                    ),
                    child: child,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < _entered.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _error
                              ? Colors.red
                              : filled
                              ? themeColor
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _error
                                ? Colors.red
                                : filled
                                ? themeColor
                                : (widget.isDark
                                      ? Colors.white38
                                      : Colors.black38),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                if (_error) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Wrong PIN',
                    style: TextStyle(
                      color: Colors.red.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                // Responsive keypad (childAspectRatio: 1.35 prevents vertical overflow)
                SizedBox(
                  width: 280,
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.35,
                    children: [
                      ...[
                        '1',
                        '2',
                        '3',
                        '4',
                        '5',
                        '6',
                        '7',
                        '8',
                        '9',
                      ].map((d) => _digitBtn(d, themeColor)),
                      _deleteBtn(themeColor),
                      _digitBtn('0', themeColor),
                      _submitBtn(themeColor),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _showResetDialog,
                  child: Text(
                    'Forgot PIN?',
                    style: TextStyle(
                      color: themeColor.withValues(alpha: 0.75),
                      fontSize: 13,
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

  Widget _digitBtn(String digit, Color color) {
    return GestureDetector(
      onTap: () => _onDigit(digit),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            digit,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: widget.isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _submitBtn(Color color) {
    final ready = _entered.length == 4;
    return GestureDetector(
      onTap: _onSubmit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: ready
              ? LinearGradient(
                  colors: [color, color.withValues(alpha: 0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: ready ? null : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ready ? color : color.withValues(alpha: 0.18),
          ),
          boxShadow: ready
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Icon(
            Icons.check_rounded,
            size: 24,
            color: ready
                ? Colors.black
                : (widget.isDark ? Colors.white24 : Colors.black26),
          ),
        ),
      ),
    );
  }

  Widget _deleteBtn(Color color) {
    return GestureDetector(
      onTap: _onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: const Center(
          child: Icon(Icons.backspace_outlined, color: Colors.red, size: 22),
        ),
      ),
    );
  }
}

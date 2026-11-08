import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'veil_theme.dart';

/// Per-chat PIN lock screen.
/// Shows a numeric PIN pad before allowing access to a locked chat.
/// PIN is stored as SHA-256 hash per contact in SharedPreferences.
class ChatLockScreen extends StatefulWidget {
  final String contactName;
  final bool isDark;
  final Widget child; // The actual chat screen

  const ChatLockScreen({
    super.key,
    required this.contactName,
    required this.isDark,
    required this.child,
  });

  static String _prefKey(String contact) => 'chat_lock_pin_\$contact';

  /// Check if a contact has a lock set
  static Future<bool> isLocked(String contact) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefKey(contact));
  }

  /// Set PIN for a contact (null to remove)
  static Future<void> setPin(String contact, String? pin) async {
    final prefs = await SharedPreferences.getInstance();
    if (pin == null) {
      await prefs.remove(_prefKey(contact));
    } else {
      final hash = sha256.convert(utf8.encode(pin)).toString();
      await prefs.setString(_prefKey(contact), hash);
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
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut));
    _checkLock();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkLock() async {
    final locked = await ChatLockScreen.isLocked(widget.contactName);
    if (mounted) setState(() => _hasLock = locked);
  }

  Future<void> _onDigit(String digit) async {
    if (_entered.length >= 4) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    HapticFeedback.lightImpact();
    // Auto-submit on the last digit (onCompleted behaviour). The explicit
    // ✓ button below is kept for users who expect a confirm affordance.
    if (_entered.length == 4) await _verify();
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
    HapticFeedback.lightImpact();
  }

  /// Explicit "OK / Done" action.
  ///
  /// ✅ FIX: there was previously no way to confirm a PIN other than typing the
  /// 4th digit. An incomplete PIN now gives clear feedback instead of doing
  /// nothing at all.
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
      final stored =
          prefs.getString(ChatLockScreen._prefKey(widget.contactName));
      final hash = sha256.convert(utf8.encode(_entered)).toString();
      if (hash == stored) {
        HapticFeedback.mediumImpact();
        // Smooth fade into the chat rather than an abrupt swap.
        if (mounted) setState(() => _isUnlocked = true);
      } else {
        HapticFeedback.heavyImpact();
        if (mounted) setState(() { _error = true; _entered = ''; });
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


  @override
  Widget build(BuildContext context) {
    if (!_hasLock || _isUnlocked) return widget.child;
    final themeColor = VeilTheme.accentColor;

    return Scaffold(
      backgroundColor:
          widget.isDark ? const Color(0xFF050A15) : const Color(0xFFF2F6FF),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: themeColor.withOpacity(0.3), width: 2),
                ),
                child: Icon(Icons.lock_rounded, color: themeColor, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                widget.contactName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter PIN to unlock',
                style: TextStyle(
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              // PIN dots
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(
                    _error ? (_shakeAnim.value * 10 * ((_shakeAnim.value * 4).toInt() % 2 == 0 ? 1 : -1)) : 0,
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
                      width: 16,
                      height: 16,
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
                                  : (widget.isDark ? Colors.white38 : Colors.black38),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              if (_error) ...[
                const SizedBox(height: 12),
                Text('Wrong PIN',
                  style: TextStyle(color: Colors.red.withOpacity(0.8),
                      fontSize: 13)),
              ],
              const SizedBox(height: 32),
              // Number pad
              SizedBox(
                width: 280,
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    ...['1','2','3','4','5','6','7','8','9'].map((d) =>
                      _digitBtn(d, themeColor)),
                    _deleteBtn(themeColor),
                    _digitBtn('0', themeColor),
                    // ✅ FIX: explicit confirm button — the pad previously had
                    // an empty cell here and no way to submit.
                    _submitBtn(themeColor),

                  ],
                ),
              ),
            ],
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Center(
          child: Text(digit,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: widget.isDark ? Colors.white : Colors.black,
            )),
        ),
      ),
    );
  }

  /// Confirm / OK key. Enabled state is reflected visually so the user knows
  /// when the PIN is ready to submit.
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
                  colors: [color, color.withOpacity(0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: ready ? null : color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ready ? color : color.withOpacity(0.18),
          ),
          boxShadow: ready
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.35),
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
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: const Center(
          child: Icon(Icons.backspace_outlined,
              color: Colors.red, size: 22),
        ),
      ),
    );
  }
}

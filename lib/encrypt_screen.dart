import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'branding/veil_brand.dart';
import 'services/crypto_service.dart';
import 'veil_components.dart';
import 'veil_feedback.dart';
import 'veil_theme.dart';

class EncryptScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;
  final String sharedKey;

  const EncryptScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
    this.sharedKey = "",
  });

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  final TextEditingController _mainController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final CryptoService _crypto = CryptoService();

  static final RegExp _hexRegex = RegExp(r'^[0-9a-fA-F]+$');

  @override
  void dispose() {
    _mainController.dispose();
    _passController.dispose();
    super.dispose();
  }

  bool get _isLikelyHexPayload {
    final t = _mainController.text.trim();
    return t.length >= 96 && t.length.isEven && _hexRegex.hasMatch(t);
  }

  String get _effectivePass =>
      _passController.text.isNotEmpty ? _passController.text : widget.sharedKey;

  (String, Color) get _keyStrength {
    final p = _effectivePass;
    if (p.isEmpty) return ('NO KEY SET', Colors.grey);
    if (p.length < 6) return ('WEAK KEY', VeilBrand.danger);
    if (p.length < 12) return ('MODERATE KEY', VeilBrand.warning);
    return ('STRONG KEY (${p.length * 6}b+)', VeilBrand.veilTeal);
  }

  Future<void> _handleEncrypt() async {
    final text = _mainController.text;
    final pass = _effectivePass;
    if (text.isEmpty) return;
    if (pass.isEmpty) {
      VeilFeedback.warning(context, 'Enter a password.');
      return;
    }
    final encrypted = await _crypto.encrypt(pass, text);
    if (!mounted) return;
    if (encrypted != null) {
      setState(() {
        _mainController.text = _crypto.bytesToHex(encrypted);
      });
      VeilFeedback.success(context, 'Encrypted with AES-256-GCM!');
    }
  }

  Future<void> _handleDecrypt() async {
    final hex = _mainController.text;
    final pass = _effectivePass;
    if (hex.isEmpty || pass.isEmpty) {
      if (pass.isEmpty) VeilFeedback.warning(context, 'Enter a password.');
      return;
    }
    try {
      final bytes = _crypto.hexToBytes(hex);
      final decrypted = await _crypto.decrypt(pass, bytes);
      if (!mounted) return;
      if (decrypted != null) {
        setState(() {
          _mainController.text = decrypted;
        });
        VeilFeedback.success(context, 'Decrypted & MAC verified!');
      } else {
        VeilFeedback.error(context, 'Wrong Password or tampered MAC tag');
      }
    } catch (_) {
      if (mounted) VeilFeedback.error(context, 'Invalid Hex Data');
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _mainController.text));
    VeilFeedback.info(context, 'Copied');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    setState(() => _mainController.text = data!.text!);
  }

  void _generateKey() {
    final rng = Random.secure();
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%&*';
    final key = List.generate(
      20,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    setState(() => _passController.text = key);
    Clipboard.setData(ClipboardData(text: key));
    VeilFeedback.success(
      context,
      'Generated 20-char key & copied to clipboard',
    );
  }

  Widget _buildTelemetryBar(Color themeColor) {
    final text = _mainController.text.trim();
    final isHex = _isLikelyHexPayload;
    final (strengthLabel, strengthColor) = _keyStrength;

    if (isHex) {
      final totalBytes = text.length ~/ 2;
      final ctBytes = max(0, totalBytes - 48);
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          VeilBadge(
            label: 'AES-256-GCM WIRE HEX',
            icon: Icons.enhanced_encryption_rounded,
            color: VeilBrand.veilTeal,
            isDark: widget.isDark,
          ),
          VeilBadge(
            label: 'SALT 16B • NONCE 16B • MAC 16B',
            icon: Icons.verified_user_outlined,
            color: themeColor,
            isDark: widget.isDark,
          ),
          VeilBadge(
            label: 'CIPHERTEXT: $ctBytes B',
            icon: Icons.data_object_rounded,
            color: VeilBrand.veilIndigo,
            isDark: widget.isDark,
          ),
          VeilBadge(
            label: strengthLabel,
            icon: Icons.key_rounded,
            color: strengthColor,
            isDark: widget.isDark,
          ),
        ],
      );
    }

    final utf8Len = utf8.encode(_mainController.text).length;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        VeilBadge(
          label: 'PLAINTEXT ($utf8Len B)',
          icon: Icons.notes_rounded,
          color: themeColor,
          isDark: widget.isDark,
        ),
        VeilBadge(
          label: 'WIRE EST: ${utf8Len + 48} B',
          icon: Icons.analytics_outlined,
          color: VeilBrand.veilIndigo,
          isDark: widget.isDark,
        ),
        VeilBadge(
          label: strengthLabel,
          icon: Icons.key_rounded,
          color: strengthColor,
          isDark: widget.isDark,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final themeColor = VeilTheme.accentColor;
    final subColor = widget.isDark ? Colors.white54 : Colors.black54;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: VeilHeader(
                    title: "Encrypt",
                    isDark: widget.isDark,
                    icon: Icons.lock_outline,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    widget.isDark ? Icons.wb_sunny : Icons.nightlight_round,
                  ),
                  color: subColor,
                  onPressed: widget.toggleTheme,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height * 0.65),
              child: VeilGlassContainer(
                isDark: widget.isDark,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTelemetryBar(themeColor),
                        const SizedBox(height: 14),
                        VeilTextField(
                          isDark: widget.isDark,
                          label: "Text / Hex",
                          maxLines: 7,
                          controller: _mainController,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _pasteFromClipboard,
                              icon: Icon(
                                Icons.content_paste_rounded,
                                size: 14,
                                color: subColor,
                              ),
                              label: Text(
                                "Paste",
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _copyToClipboard,
                              icon: Icon(Icons.copy, size: 14, color: subColor),
                              label: Text(
                                "Copy",
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ),
                            if (_mainController.text.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _mainController.clear()),
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 14,
                                  color: subColor,
                                ),
                                label: Text(
                                  "Clear",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        VeilTextField(
                          isDark: widget.isDark,
                          label: "Password",
                          isPassword: true,
                          prefixIcon: Icons.vpn_key_outlined,
                          controller: _passController,
                          onChanged: (_) => setState(() {}),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _generateKey,
                            icon: Icon(
                              Icons.auto_fix_high_rounded,
                              size: 15,
                              color: themeColor,
                            ),
                            label: Text(
                              "Generate Secure Key",
                              style: TextStyle(
                                fontSize: 12,
                                color: themeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: VeilButton(
                            isDark: widget.isDark,
                            label: "Encrypt",
                            icon: Icons.lock_rounded,
                            gradient: [
                              themeColor,
                              themeColor.withValues(alpha: 0.7),
                            ],
                            onTap: _handleEncrypt,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: VeilButton(
                            isDark: widget.isDark,
                            label: "Decrypt",
                            icon: Icons.lock_open_rounded,
                            gradient: [
                              themeColor,
                              themeColor.withValues(alpha: 0.7),
                            ],
                            isOutlined: true,
                            onTap: _handleDecrypt,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

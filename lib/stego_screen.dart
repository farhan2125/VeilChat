import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'branding/veil_brand.dart';
import 'services/stego_service.dart';
import 'stego_extract_screen.dart';
import 'veil_components.dart';
import 'veil_feedback.dart';
import 'veil_theme.dart';

/// Screen for embedding secret messages into images using randomized Red-channel
/// LSB steganography with live capacity telemetry.
class StegoScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;

  const StegoScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
  });

  @override
  State<StegoScreen> createState() => _StegoScreenState();
}

class _StegoScreenState extends State<StegoScreen> {
  final StegoService _stegoService = StegoService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  File? _selectedImage;
  StegoImageCapacity? _capacity;
  bool _isProcessing = false;
  String? _capacityWarning;

  @override
  void dispose() {
    _msgController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final cap = _stegoService.inspectImage(file);
      if (!mounted) return;
      setState(() {
        _selectedImage = file;
        _capacity = cap;
        _capacityWarning = null;
      });
      _checkCapacity();
    }
  }

  int get _payloadByteLength => utf8.encode(_msgController.text).length;

  void _checkCapacity() {
    if (_selectedImage == null || _msgController.text.isEmpty) {
      setState(() => _capacityWarning = null);
      return;
    }
    final canFit = _capacity != null
        ? _capacity!.canFitBytes(_payloadByteLength)
        : _stegoService.canEmbed(_selectedImage!, _msgController.text);
    setState(() {
      _capacityWarning = canFit ? null : '⚠️ Message too long for this image';
    });
  }

  void _generateKey() {
    final rng = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final key = List.generate(
      16,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    setState(() => _passController.text = key);
    Clipboard.setData(ClipboardData(text: key));
    VeilFeedback.info(
      context,
      'Generated 16-char stego key & copied to clipboard',
    );
  }

  Future<void> _handleEmbed() async {
    if (_selectedImage == null) {
      VeilFeedback.warning(context, 'Please select a carrier image first');
      return;
    }
    if (_msgController.text.isEmpty) {
      VeilFeedback.warning(context, 'Please enter a secret message');
      return;
    }
    if (_passController.text.isEmpty) {
      VeilFeedback.warning(context, 'Please enter an encryption password');
      return;
    }
    if (_capacityWarning != null) {
      VeilFeedback.error(
        context,
        'Message too long — choose a higher-resolution image or shorter text',
      );
      return;
    }

    setState(() => _isProcessing = true);

    final result = await _stegoService.embedMessage(
      imageFile: _selectedImage!,
      message: _msgController.text,
      password: _passController.text,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.success && result.file != null) {
      _showSuccessDialog(result.file!);
      _msgController.clear();
      _checkCapacity();
    } else {
      VeilFeedback.error(context, result.error ?? 'Embedding failed');
    }
  }

  void _showSuccessDialog(File savedFile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? VeilBrand.veilSlate : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '✅ Stego Payload Embedded',
          style: TextStyle(
            color: widget.isDark ? Colors.white : VeilBrand.veilInk,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                savedFile,
                height: 150,
                width: 150,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Image saved with hidden LSB payload',
              style: TextStyle(
                color: widget.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              savedFile.path.split(Platform.pathSeparator).last,
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark ? Colors.white38 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('EMBED ANOTHER'),
          ),
        ],
      ),
    );
  }

  void _goToExtractScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StegoExtractScreen(
          isDark: widget.isDark,
          toggleTheme: widget.toggleTheme,
        ),
      ),
    );
  }

  Widget _buildCapacityMeter(Color themeColor) {
    final usedBytes = _payloadByteLength;
    final cap = _capacity;
    final maxBytes = cap?.maxPayloadBytes ?? 0;
    final ratio = maxBytes > 0 ? (usedBytes / maxBytes).clamp(0.0, 1.0) : 0.0;
    final barColor = ratio > 0.9
        ? VeilBrand.danger
        : ratio > 0.7
        ? VeilBrand.warning
        : VeilBrand.veilTeal;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (widget.isDark ? Colors.white : Colors.black).withValues(
          alpha: 0.05,
        ),
        borderRadius: BorderRadius.circular(VeilBrand.rMd),
        border: Border.all(
          color: (widget.isDark ? Colors.white : Colors.black).withValues(
            alpha: 0.09,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              VeilBadge(
                label: cap != null
                    ? '${cap.width}×${cap.height} PX'
                    : 'NO CARRIER IMAGE',
                icon: Icons.photo_size_select_actual_outlined,
                color: cap != null ? themeColor : Colors.grey,
                isDark: widget.isDark,
              ),
              VeilBadge(
                label: cap != null
                    ? '$usedBytes / $maxBytes BYTES'
                    : '$usedBytes BYTES PAYLOAD',
                icon: Icons.memory_rounded,
                color: barColor,
                isDark: widget.isDark,
              ),
              VeilBadge(
                label: 'SHA-256 PRNG • RED LSB',
                icon: Icons.verified_user_outlined,
                color: VeilBrand.veilIndigo,
                isDark: widget.isDark,
              ),
            ],
          ),
          if (cap != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: (widget.isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
          if (_capacityWarning != null) ...[
            const SizedBox(height: 8),
            Text(
              _capacityWarning!,
              style: const TextStyle(
                color: VeilBrand.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final themeColor = VeilTheme.accentColor;

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
                    title: 'Steganography',
                    isDark: widget.isDark,
                    icon: Icons.remove_red_eye_outlined,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.visibility_off_rounded,
                        color: themeColor,
                      ),
                      onPressed: _goToExtractScreen,
                      tooltip: 'Extract hidden message',
                    ),
                    IconButton(
                      icon: Icon(
                        widget.isDark ? Icons.wb_sunny : Icons.nightlight_round,
                      ),
                      color: widget.isDark ? Colors.white54 : Colors.black54,
                      onPressed: widget.toggleTheme,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height * 0.7),
              child: VeilGlassContainer(
                isDark: widget.isDark,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 165,
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : const Color(0xFFE0E5EC).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _selectedImage != null
                                ? themeColor.withValues(alpha: 0.45)
                                : (widget.isDark
                                      ? Colors.white10
                                      : Colors.black12),
                          ),
                          image: _selectedImage != null
                              ? DecorationImage(
                                  image: FileImage(_selectedImage!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _selectedImage == null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_rounded,
                                      size: 40,
                                      color: widget.isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'TAP TO SELECT IMAGE',
                                      style: TextStyle(
                                        color: widget.isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                      ),
                    ),
                    _buildCapacityMeter(themeColor),
                    const SizedBox(height: 18),
                    VeilTextField(
                      isDark: widget.isDark,
                      label: 'Secret Message',
                      maxLines: 3,
                      controller: _msgController,
                      onChanged: (_) => _checkCapacity(),
                    ),
                    const SizedBox(height: 15),
                    VeilTextField(
                      isDark: widget.isDark,
                      label: 'Password',
                      isPassword: true,
                      prefixIcon: Icons.lock_clock_outlined,
                      controller: _passController,
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
                          'Generate & Copy Key',
                          style: TextStyle(
                            fontSize: 12,
                            color: themeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _isProcessing
                        ? VeilLoadingIndicator(
                            isDark: widget.isDark,
                            message: 'Embedding randomized LSB payload...',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              VeilButton(
                                isDark: widget.isDark,
                                label: 'EMBED & SAVE',
                                icon: Icons.enhanced_encryption_rounded,
                                gradient: [
                                  themeColor,
                                  themeColor.withValues(alpha: 0.7),
                                ],
                                onTap: _handleEmbed,
                              ),
                              const SizedBox(height: 10),
                              VeilButton(
                                isDark: widget.isDark,
                                label: 'EXTRACT FROM IMAGE',
                                icon: Icons.visibility_off_rounded,
                                isOutlined: true,
                                gradient: [
                                  themeColor,
                                  themeColor.withValues(alpha: 0.7),
                                ],
                                onTap: _goToExtractScreen,
                              ),
                            ],
                          ),
                    const SizedBox(height: 14),
                    Text(
                      'Your message is scattered pseudorandomly across Red-channel LSBs\n'
                      'seeded by SHA-256(password). Lossless PNG preserves every bit.',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDark ? Colors.white38 : Colors.black38,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

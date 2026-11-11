import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'branding/veil_brand.dart';
import 'services/stego_service.dart';
import 'veil_components.dart';
import 'veil_feedback.dart';
import 'veil_theme.dart';

/// Dedicated screen for extracting hidden messages from steganographic images.
class StegoExtractScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;

  const StegoExtractScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
  });

  @override
  State<StegoExtractScreen> createState() => _StegoExtractScreenState();
}

class _StegoExtractScreenState extends State<StegoExtractScreen> {
  final StegoService _stego = StegoService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _passController = TextEditingController();

  File? _selectedImage;
  StegoImageCapacity? _capacity;
  String? _extractedMessage;
  String? _errorMessage;
  bool _isExtracting = false;
  bool _isCopied = false;

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final imgFile = File(file.path);
      final cap = _stego.inspectImage(imgFile);
      if (!mounted) return;
      setState(() {
        _selectedImage = imgFile;
        _capacity = cap;
        _extractedMessage = null;
        _errorMessage = null;
        _isCopied = false;
      });
    }
  }

  Future<void> _extractMessage() async {
    if (_selectedImage == null) {
      VeilFeedback.warning(context, 'Please select an image first');
      return;
    }
    if (_passController.text.isEmpty) {
      VeilFeedback.warning(context, 'Password is required');
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractedMessage = null;
      _errorMessage = null;
      _isCopied = false;
    });

    final result = await _stego.extractMessage(
      imageFile: _selectedImage!,
      password: _passController.text,
    );

    if (mounted) {
      setState(() {
        _isExtracting = false;
        if (result.success && result.message != null) {
          _extractedMessage = result.message!;
          VeilFeedback.success(context, 'Hidden payload extracted!');
        } else {
          _errorMessage = result.error ?? 'Extraction failed';
          VeilFeedback.error(context, _errorMessage!);
        }
      });
    }
  }

  void _copyToClipboard() {
    if (_extractedMessage != null) {
      Clipboard.setData(ClipboardData(text: _extractedMessage!));
      setState(() => _isCopied = true);
      VeilFeedback.success(context, 'Copied to clipboard');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = VeilTheme.accentColor;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: (widget.isDark ? Colors.black : Colors.white).withValues(
                alpha: 0.2,
              ),
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Steganography Extract',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              widget.isDark ? Icons.wb_sunny : Icons.nightlight_round,
              color: widget.isDark ? Colors.white54 : Colors.black54,
            ),
            onPressed: widget.toggleTheme,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 100, 20, 30),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: (widget.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selectedImage != null
                        ? themeColor.withValues(alpha: 0.5)
                        : (widget.isDark ? Colors.white10 : Colors.black12),
                  ),
                  image: _selectedImage != null
                      ? DecorationImage(
                          image: FileImage(_selectedImage!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _selectedImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_rounded,
                            size: 50,
                            color: widget.isDark
                                ? Colors.white30
                                : Colors.black26,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'TAP TO SELECT IMAGE',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.white30
                                  : Colors.black26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            if (_capacity != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  VeilBadge(
                    label: '${_capacity!.width}×${_capacity!.height} PX',
                    icon: Icons.image_search_rounded,
                    color: themeColor,
                    isDark: widget.isDark,
                  ),
                  VeilBadge(
                    label: 'MAX ${_capacity!.maxPayloadBytes} BYTES',
                    icon: Icons.storage_rounded,
                    color: VeilBrand.veilTeal,
                    isDark: widget.isDark,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            VeilTextField(
              isDark: widget.isDark,
              label: 'Password',
              isPassword: true,
              prefixIcon: Icons.lock_outline,
              controller: _passController,
            ),
            const SizedBox(height: 24),
            VeilButton(
              isDark: widget.isDark,
              label: 'EXTRACT HIDDEN MESSAGE',
              icon: Icons.lock_open_rounded,
              gradient: [themeColor, themeColor.withValues(alpha: 0.7)],
              onTap: _extractMessage,
            ),
            const SizedBox(height: 24),
            if (_isExtracting)
              VeilLoadingIndicator(
                isDark: widget.isDark,
                message: 'Scanning Red-channel LSB coordinates...',
              )
            else if (_errorMessage != null)
              VeilErrorCard(
                isDark: widget.isDark,
                message: _errorMessage!,
                onRetry: _extractMessage,
              )
            else if (_extractedMessage != null)
              VeilGlassContainer(
                isDark: widget.isDark,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'HIDDEN MESSAGE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                            letterSpacing: 1,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isCopied ? Icons.check : Icons.copy,
                            color: _isCopied ? VeilBrand.success : themeColor,
                            size: 20,
                          ),
                          onPressed: _copyToClipboard,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (widget.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: themeColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: SelectableText(
                        _extractedMessage!,
                        style: TextStyle(
                          color: widget.isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

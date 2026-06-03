import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/stego_service.dart';

/// Dedicated screen for extracting hidden messages from images.
/// User selects an image, enters password, and sees the extracted secret.
/// Can copy to clipboard or save as note.
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
  String? _extractedMessage;
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
      setState(() {
        _selectedImage = File(file.path);
        _extractedMessage = null;
        _isCopied = false;
      });
    }
  }

  Future<void> _extractMessage() async {
    if (_selectedImage == null) {
      _showError('Please select an image first');
      return;
    }
    if (_passController.text.isEmpty) {
      _showError('Password is required');
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractedMessage = null;
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
        } else {
          _showError(result.error ?? 'Extraction failed');
        }
      });
    }
  }

  void _copyToClipboard() {
    if (_extractedMessage != null) {
      Clipboard.setData(ClipboardData(text: _extractedMessage!));
      setState(() => _isCopied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
              color: (widget.isDark ? Colors.black : Colors.white).withOpacity(0.2),
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
            // Image preview
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: (widget.isDark ? Colors.white : Colors.black)
                      .withOpacity(0.05),
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
                            color: widget.isDark ? Colors.white30 : Colors.black26,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'TAP TO SELECT IMAGE',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark ? Colors.white30 : Colors.black26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Password field
            VeilTextField(
              isDark: widget.isDark,
              label: 'Password',
              isPassword: true,
              prefixIcon: Icons.lock_outline,
              controller: _passController,
            ),
            const SizedBox(height: 30),

            // Extract button
            VeilButton(
              isDark: widget.isDark,
              label: 'EXTRACT HIDDEN MESSAGE',
              gradient: [themeColor, themeColor.withOpacity(0.7)],
              onTap: _extractMessage,
            ),
            const SizedBox(height: 30),

            // Extracted message area
            if (_isExtracting)
              const Center(child: CircularProgressIndicator())
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
                            color: _isCopied ? Colors.green : themeColor,
                            size: 20,
                          ),
                          onPressed: _copyToClipboard,
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (widget.isDark ? Colors.white : Colors.black)
                            .withOpacity(0.05),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: themeColor.withOpacity(0.3),
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
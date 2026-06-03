import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'veil_components.dart';
import 'veil_theme.dart';
import 'stego_extract_screen.dart'; // NEW: dedicated extract screen
import 'services/stego_service.dart';

/// Screen for embedding secret messages into images.
/// - Select image, enter message + password, embed.
/// - Shows capacity warning if message too long.
/// - Save resulting image to device.
/// - Separate button to navigate to extraction screen.
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
  bool _isProcessing = false;
  String? _capacityWarning;

  @override
  void dispose() {
    _msgController.dispose();
    _passController.dispose();
    super.dispose();
  }

  /// Pick an image from gallery
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _capacityWarning = null; // reset warning
      });
      _checkCapacity();
    }
  }

  /// Check if the selected image can hold the current message
  void _checkCapacity() {
    if (_selectedImage == null || _msgController.text.isEmpty) {
      setState(() => _capacityWarning = null);
      return;
    }
    final canFit = _stegoService.canEmbed(_selectedImage!, _msgController.text);
    setState(() {
      _capacityWarning = canFit ? null : '⚠️ Message too long for this image';
    });
  }

  /// Handle embed button
  Future<void> _handleEmbed() async {
    if (_selectedImage == null) {
      _showError('Please select an image');
      return;
    }
    if (_msgController.text.isEmpty) {
      _showError('Please enter a message');
      return;
    }
    if (_passController.text.isEmpty) {
      _showError('Please enter a password');
      return;
    }
    if (_capacityWarning != null) {
      _showError('Message too long – choose a larger image or shorter message');
      return;
    }

    setState(() => _isProcessing = true);

    final result = await _stegoService.embedMessage(
      imageFile: _selectedImage!,
      message: _msgController.text,
      password: _passController.text,
    );

    setState(() => _isProcessing = false);

    if (result.success && result.file != null) {
      // Show success and preview
      _showSuccessDialog(result.file!);
      // Clear message field, keep image for possible further embedding
      _msgController.clear();
    } else {
      _showError(result.error ?? 'Embedding failed');
    }
  }

  void _showSuccessDialog(File savedFile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '✅ Success',
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                savedFile,
                height: 150,
                width: 150,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Image saved with hidden message',
              style: TextStyle(
                color: widget.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            Text(
              savedFile.path.split('/').last,
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
            onPressed: () {
              Navigator.pop(ctx);
              // Keep the image selected for further embedding
            },
            child: const Text('EMBED ANOTHER'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Navigate to the dedicated extraction screen
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final themeColor = VeilTheme.accentColor;

    return SafeArea(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Column(
        children: [
          // Header with theme toggle and EXTRACT button
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
                  // Extract button (navigates to dedicated screen)
                  IconButton(
                    icon: Icon(
                      Icons.visibility_off_rounded,
                      color: themeColor,
                    ),
                    onPressed: _goToExtractScreen,
                    tooltip: 'Extract hidden message',
                  ),
                  // Theme toggle
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

          // Main content
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height * 0.7),
            child: VeilGlassContainer(
              isDark: widget.isDark,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Image picker area
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.black.withOpacity(0.3)
                            : const Color(0xFFE0E5EC).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.isDark
                              ? Colors.white10
                              : Colors.black12,
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
                  const SizedBox(height: 20),

                  // Message field
                  VeilTextField(
                    isDark: widget.isDark,
                    label: 'Secret Message',
                    maxLines: 3,
                    controller: _msgController,
                    onChanged: (_) => _checkCapacity(),
                  ),
                  if (_capacityWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 10),
                      child: Text(
                        _capacityWarning!,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 15),

                  // Password field
                  VeilTextField(
                    isDark: widget.isDark,
                    label: 'Password',
                    isPassword: true,
                    prefixIcon: Icons.lock_clock_outlined,
                    controller: _passController,
                  ),
                  const SizedBox(height: 25),

                  // Embed button
                  _isProcessing
                      ? const Center(child: CircularProgressIndicator())
                      : VeilButton(
                          isDark: widget.isDark,
                          label: 'EMBED & SAVE',
                          gradient: [
                            themeColor,
                            themeColor.withOpacity(0.7),
                          ],
                          onTap: _handleEmbed,
                        ),

                  const SizedBox(height: 16),

                  // Hint text
                  Text(
                    'Your message will be hidden in the image using LSB steganography.\n'
                    'Only someone with the correct password can extract it.',
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
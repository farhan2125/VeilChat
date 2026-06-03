import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/database_service.dart';
import 'services/network_service.dart';

/// Screen to view and edit the current user's profile.
class ProfileScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;

  const ProfileScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final DatabaseService _db = DatabaseService();
  final NetworkService _network = NetworkService();
  final ImagePicker _picker = ImagePicker();

  // Controllers
  final TextEditingController _displayNameCtrl = TextEditingController();
  final TextEditingController _statusCtrl = TextEditingController();
  final TextEditingController _bioCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  String? _avatarPath;
  bool _isLoading = true;
  bool _isEditing = false;
  String? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _network.currentUser;
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _statusCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_currentUser == null) return;
    final profile = await _db.getUserProfile(_currentUser!);
    if (profile != null && mounted) {
      setState(() {
        _displayNameCtrl.text = profile['displayName'] ?? '';
        _statusCtrl.text = profile['status'] ?? '';
        _bioCtrl.text = profile['bio'] ?? '';
        _phoneCtrl.text = profile['phoneNumber'] ?? '';
        _emailCtrl.text = profile['email'] ?? '';
        _avatarPath = profile['avatarPath'];
        _isLoading = false;
      });
    } else {
      // Create default profile with username as display name
      _displayNameCtrl.text = _currentUser!;
      _statusCtrl.text = 'Available';
      setState(() => _isLoading = false);
      await _saveProfile();
    }
  }

  Future<void> _saveProfile() async {
    if (_currentUser == null) return;
    await _db.saveUserProfile(
      accountOwner: _currentUser!,
      displayName: _displayNameCtrl.text.trim(),
      status: _statusCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      avatarPath: _avatarPath,
    );
  }

  Future<void> _sendProfileToServer() async {
    if (_currentUser == null) return;
    final profile = {
      'displayName': _displayNameCtrl.text.trim(),
      'status': _statusCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'phoneNumber': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'avatarPath': _avatarPath,
    };
    NetworkService().sendProfileUpdate(profile);
  }

  Future<void> _pickAvatar() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _avatarPath = file.path);
      await _saveProfile();
      await _sendProfileToServer();
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _avatarPath = null);
    await _saveProfile();
    await _sendProfileToServer();
  }

  void _toggleEdit() {
    setState(() => _isEditing = !_isEditing);
    if (!_isEditing) {
      _saveProfile();
      _sendProfileToServer();
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
          'Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditing ? Icons.check_rounded : Icons.edit_rounded,
              color: themeColor,
            ),
            onPressed: _toggleEdit,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 20, 30),
              child: Column(
                children: [
                  // Avatar section
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: themeColor, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: themeColor.withOpacity(0.3),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 58,
                            backgroundColor: themeColor.withOpacity(0.1),
                            backgroundImage: _avatarPath != null
                                ? FileImage(File(_avatarPath!))
                                : null,
                            child: _avatarPath == null
                                ? Text(
                                    _displayNameCtrl.text.isNotEmpty
                                        ? _displayNameCtrl.text[0].toUpperCase()
                                        : _currentUser![0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: themeColor,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (_isEditing)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: themeColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: widget.isDark ? Colors.black : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                                onPressed: _pickAvatar,
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Profile fields
                  VeilGlassContainer(
                    isDark: widget.isDark,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildInfoField(
                          label: 'Username',
                          value: _currentUser!,
                          icon: Icons.person_outline,
                          editable: false,
                        ),
                        const SizedBox(height: 20),
                        _buildInfoField(
                          label: 'Display Name',
                          value: _displayNameCtrl.text,
                          icon: Icons.badge_outlined,
                          editable: _isEditing,
                          controller: _displayNameCtrl,
                          hint: 'Enter your name',
                        ),
                        const SizedBox(height: 20),
                        _buildInfoField(
                          label: 'Status',
                          value: _statusCtrl.text,
                          icon: Icons.info_outline,
                          editable: _isEditing,
                          controller: _statusCtrl,
                          hint: 'What\'s on your mind?',
                        ),
                        const SizedBox(height: 20),
                        _buildInfoField(
                          label: 'Bio',
                          value: _bioCtrl.text,
                          icon: Icons.article_outlined,
                          editable: _isEditing,
                          controller: _bioCtrl,
                          hint: 'Tell something about yourself',
                          maxLines: 3,
                        ),
                        const Divider(height: 30),
                        _buildInfoField(
                          label: 'Phone',
                          value: _phoneCtrl.text,
                          icon: Icons.phone_outlined,
                          editable: _isEditing,
                          controller: _phoneCtrl,
                          hint: '+1 234 567 890',
                        ),
                        const SizedBox(height: 20),
                        _buildInfoField(
                          label: 'Email',
                          value: _emailCtrl.text,
                          icon: Icons.email_outlined,
                          editable: _isEditing,
                          controller: _emailCtrl,
                          hint: 'user@example.com',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_isEditing)
                    VeilButton(
                      isDark: widget.isDark,
                      label: 'Save Profile',
                      gradient: [themeColor, themeColor.withOpacity(0.7)],
                      onTap: () {
                        _toggleEdit();
                      },
                    ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoField({
    required String label,
    required String value,
    required IconData icon,
    required bool editable,
    TextEditingController? controller,
    String? hint,
    int maxLines = 1,
  }) {
    final themeColor = VeilTheme.accentColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: themeColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: VeilTheme.subText(widget.isDark),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              if (editable && controller != null)
                TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: widget.isDark ? Colors.white30 : Colors.black26,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              else
                Text(
                  value.isEmpty ? 'Not set' : value,
                  style: TextStyle(
                    color: value.isEmpty
                        ? (widget.isDark ? Colors.white38 : Colors.black38)
                        : (widget.isDark ? Colors.white : Colors.black),
                    fontSize: 16,
                    fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
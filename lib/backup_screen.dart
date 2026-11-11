import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/database_service.dart';
import 'services/network_service.dart';

class BackupScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;

  const BackupScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final DatabaseService _db = DatabaseService();
  final NetworkService _network = NetworkService();

  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  int _autoCleanupDays = 30;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final currentUser = _network.currentUser;
    if (currentUser == null) return;
    final stats = await _db.getDatabaseStats(currentUser);
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final backupPath = await _db.backupDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup created: ${backupPath.split('/').last}'),
            backgroundColor: Colors.green,
          ),
        );
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: widget.isDark
                ? const Color(0xFF0F172A)
                : Colors.white,
            title: Text(
              'Backup Created',
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black,
              ),
            ),
            content: Text(
              'Do you want to share the backup file?',
              style: TextStyle(
                color: widget.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('NO'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('SHARE'),
              ),
            ],
          ),
        );
        if (result == true) {
          await Share.shareXFiles([
            XFile(backupPath),
          ], text: 'VeilChat Database Backup');
        }
      }
    } catch (e) {
      _showError('Backup failed: $e');
    } finally {
      setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreBackup() async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      _showError('Storage permission required');
      return;
    }

    setState(() => _isRestoring = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _isRestoring = false);
        return;
      }
      final backupPath = result.files.single.path!;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: widget.isDark
              ? const Color(0xFF0F172A)
              : Colors.white,
          title: Text('Restore Backup?'),
          content: Text(
            'This will REPLACE your current database. All unsynced messages will be lost.\n\nContinue?',
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
              child: const Text('RESTORE', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) {
        setState(() => _isRestoring = false);
        return;
      }

      await _db.close();

      final dbPath = await getDatabasesPath();
      final currentDbPath = path.join(dbPath, 'veilchat_v9.db');

      final backupFile = File(backupPath);
      await backupFile.copy(currentDbPath);

      await _db.initialize();

      await _loadStats();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Database restored successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Restore failed: $e');
    } finally {
      setState(() => _isRestoring = false);
    }
  }

  Future<void> _cleanupCache() async {
    try {
      await _db.cleanupFileCache(daysToKeep: _autoCleanupDays);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cache cleaned (older than $_autoCleanupDays days)'),
            backgroundColor: Colors.green,
          ),
        );
        _loadStats();
      }
    } catch (e) {
      _showError('Cleanup failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
          'Backup & Restore',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 20, 30),
              child: Column(
                children: [
                  // Database stats
                  VeilGlassContainer(
                    isDark: widget.isDark,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                Icons.storage_rounded,
                                color: themeColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Database Statistics',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: widget.isDark
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_stats['messages']} messages, ${_stats['contacts']} contacts',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: VeilTheme.subText(widget.isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        _buildStatRow(
                          'Groups',
                          '${_stats['groups'] ?? 0}',
                          Icons.group,
                        ),
                        _buildStatRow(
                          'Calls',
                          '${_stats['calls'] ?? 0}',
                          Icons.call,
                        ),
                        _buildStatRow(
                          'Cache Size',
                          _formatBytes(_stats['file_cache_size'] ?? 0),
                          Icons.photo_library,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Backup actions
                  VeilGlassContainer(
                    isDark: widget.isDark,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BACKUP',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildActionTile(
                          icon: Icons.backup_rounded,
                          title: 'Create Backup',
                          subtitle: 'Save current database to file',
                          onTap: _createBackup,
                          isLoading: _isBackingUp,
                        ),
                        const Divider(height: 30),
                        _buildActionTile(
                          icon: Icons.restore_rounded,
                          title: 'Restore from Backup',
                          subtitle: 'Replace database with backup file',
                          onTap: _restoreBackup,
                          isLoading: _isRestoring,
                          danger: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Cache management
                  VeilGlassContainer(
                    isDark: widget.isDark,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CACHE MANAGEMENT',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto-cleanup',
                                    style: TextStyle(
                                      color: widget.isDark
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Delete files older than',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: VeilTheme.subText(widget.isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: DropdownButton<int>(
                                value: _autoCleanupDays,
                                dropdownColor: widget.isDark
                                    ? const Color(0xFF0F172A)
                                    : Colors.white,
                                underline: Container(),
                                icon: Icon(
                                  Icons.arrow_drop_down,
                                  color: themeColor,
                                ),
                                items: [7, 14, 30, 60, 90].map((days) {
                                  return DropdownMenuItem(
                                    value: days,
                                    child: Text(
                                      '$days days',
                                      style: TextStyle(
                                        color: widget.isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() => _autoCleanupDays = value!);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        VeilButton(
                          isDark: widget.isDark,
                          label: 'Clean Cache Now',
                          gradient: [
                            themeColor,
                            themeColor.withValues(alpha: 0.7),
                          ],
                          onTap: _cleanupCache,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: VeilTheme.subText(widget.isDark)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: VeilTheme.subText(widget.isDark)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: widget.isDark ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isLoading,
    bool danger = false,
  }) {
    final themeColor = danger ? Colors.red : VeilTheme.accentColor;

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: themeColor,
                      ),
                    )
                  : Icon(icon, color: themeColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger
                          ? Colors.red
                          : (widget.isDark ? Colors.white : Colors.black),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: VeilTheme.subText(widget.isDark),
                    ),
                  ),
                ],
              ),
            ),
            if (!isLoading)
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: themeColor,
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'veil_components.dart';
import 'veil_theme.dart';
import 'profile_screen.dart';
import 'call_history_screen.dart';
import 'backup_screen.dart';
import 'stego_extract_screen.dart';
import 'services/network_service.dart';
import 'crash_logger.dart';
import 'services/group_service.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;
  final VoidCallback refreshApp;
  const SettingsScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
    required this.refreshApp,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notif = true, _readReceipts = true;
  double _volume = 0.7;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted)
      setState(() {
        _notif = p.getBool('notifications') ?? true;
        _readReceipts = p.getBool('read_receipts') ?? true;
        _volume = p.getDouble('volume') ?? 0.7;
      });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('notifications', _notif);
    await p.setBool('read_receipts', _readReceipts);
    await p.setDouble('volume', _volume);
  }

  Future<void> _pickWallpaper() async {
    final f = await _picker.pickImage(source: ImageSource.gallery);
    if (f != null) {
      setState(() {
        VeilTheme.customBgPath = f.path;
        VeilTheme.useCustomBg = true;
      });
      widget.refreshApp();
      if (mounted) showVeilSnack(context, 'Wallpaper updated!');
    }
  }

  Future<void> _showCrashLog() async {
    final log = await CrashLogger().readLog();
    final size = await CrashLogger().getLogSize();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.bug_report_outlined, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              'Crash Log ($size)',
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              log,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: widget.isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await CrashLogger().clearLog();
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                showVeilSnack(context, 'Crash log cleared');
              }
            },
            child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CLOSE',
              style: TextStyle(color: VeilTheme.accentColor),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF0D1B2A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Logout?',
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
        ),
        content: Text(
          'You will be disconnected.',
          style: TextStyle(
            color: widget.isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      GroupService().resetForLogout();
      NetworkService().disconnect();
      if (mounted)
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = NetworkService().currentUser ?? 'User';
    final tc = VeilTheme.accentColor;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                VeilHeader(
                  title: 'Settings',
                  isDark: widget.isDark,
                  icon: Icons.settings_outlined,
                ),
                IconButton(
                  icon: Icon(
                    widget.isDark ? Icons.wb_sunny : Icons.nightlight_round,
                    color: widget.isDark ? Colors.white54 : Colors.black54,
                  ),
                  onPressed: widget.toggleTheme,
                ),
              ],
            ),

            // Profile card
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    isDark: widget.isDark,
                    toggleTheme: widget.toggleTheme,
                  ),
                ),
              ),
              child: VeilGlassContainer(
                isDark: widget.isDark,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tc, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: tc.withValues(alpha: 0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: tc.withValues(alpha: 0.12),
                        child: Text(
                          user[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: tc,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: widget.isDark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                          Text(
                            'Tap to edit profile',
                            style: TextStyle(
                              fontSize: 12,
                              color: VeilTheme.subText(widget.isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 16, color: tc),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Appearance
            VeilGlassContainer(
              isDark: widget.isDark,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VeilSectionLabel('Appearance'),
                  _row(
                    Icons.dark_mode_rounded,
                    'Dark Mode',
                    Switch(
                      value: widget.isDark,
                      onChanged: (_) => widget.toggleTheme(),
                      activeThumbColor: tc,
                    ),
                  ),
                  _div(),
                  Text(
                    'APP THEME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tc,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _themePicker(),
                  _div(),
                  Text(
                    'ACCENT COLOR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tc,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _accentPicker(),
                  _div(),
                  Text(
                    'WALLPAPER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tc,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _wallpaperSection(),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Preferences
            VeilGlassContainer(
              isDark: widget.isDark,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VeilSectionLabel('Preferences'),
                  _row(
                    Icons.notifications_outlined,
                    'Notifications',
                    Switch(
                      value: _notif,
                      onChanged: (v) {
                        setState(() => _notif = v);
                        _savePrefs();
                      },
                      activeThumbColor: tc,
                    ),
                  ),
                  _div(),
                  _row(
                    Icons.done_all_rounded,
                    'Read Receipts',
                    Switch(
                      value: _readReceipts,
                      onChanged: (v) {
                        setState(() => _readReceipts = v);
                        _savePrefs();
                      },
                      activeThumbColor: tc,
                    ),
                  ),
                  _div(),
                  Row(
                    children: [
                      Icon(
                        Icons.volume_up_outlined,
                        color: widget.isDark ? Colors.white54 : Colors.black54,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          activeColor: tc,
                          inactiveColor: tc.withValues(alpha: 0.2),
                          onChanged: (v) {
                            setState(() => _volume = v);
                            _savePrefs();
                          },
                        ),
                      ),
                      Text(
                        '${(_volume * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: VeilTheme.subText(widget.isDark),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tools
            VeilGlassContainer(
              isDark: widget.isDark,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VeilSectionLabel('VeilChat Tools'),
                  _tile(
                    Icons.person_outline_rounded,
                    'Profile',
                    'Edit display name, status & avatar',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          isDark: widget.isDark,
                          toggleTheme: widget.toggleTheme,
                        ),
                      ),
                    ),
                  ),
                  _div(),
                  _tile(
                    Icons.history_rounded,
                    'Call History',
                    'View audio and video call logs',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallHistoryScreen(
                          isDark: widget.isDark,
                          toggleTheme: widget.toggleTheme,
                        ),
                      ),
                    ),
                  ),
                  _div(),
                  _tile(
                    Icons.backup_rounded,
                    'Backup & Restore',
                    'Create backups and manage storage',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BackupScreen(
                          isDark: widget.isDark,
                          toggleTheme: widget.toggleTheme,
                        ),
                      ),
                    ),
                  ),
                  _div(),
                  _tile(
                    Icons.visibility_off_rounded,
                    'Stego Extract',
                    'Extract hidden messages from images',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StegoExtractScreen(
                          isDark: widget.isDark,
                          toggleTheme: widget.toggleTheme,
                        ),
                      ),
                    ),
                    color: Colors.cyan,
                  ),
                  _div(),
                  _tile(
                    Icons.bug_report_outlined,
                    'View Crash Log',
                    'Debug info for troubleshooting',
                    () => _showCrashLog(),
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            VeilButton(
              isDark: widget.isDark,
              label: 'Logout',
              gradient: [Colors.redAccent, Colors.red.shade700],
              icon: Icons.logout_rounded,
              onTap: _logout,
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'VeilChat v1.0.0 • End-to-End Encrypted',
                style: TextStyle(
                  fontSize: 11,
                  color: VeilTheme.dimText(widget.isDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themePicker() {
    final themes = {
      AppTheme.cyberpunk: 'Cyber',
      AppTheme.midnight: 'Midnight',
      AppTheme.rose: 'Rose',
      AppTheme.emerald: 'Emerald',
      AppTheme.sunset: 'Sunset',
      AppTheme.ocean: 'Ocean',
    };
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: themes.entries.map((e) {
          final sel = VeilTheme.currentTheme == e.key;
          final c = widget.isDark
              ? VeilTheme.themePalettes[e.key]![0]
              : VeilTheme.themePalettes[e.key]![1];
          return GestureDetector(
            onTap: () {
              setState(() => VeilTheme.applyTheme(e.key, widget.isDark));
              widget.refreshApp();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.withValues(alpha: sel ? 0.2 : 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel ? c : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : [],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 10,
                      color: sel ? c : VeilTheme.subText(widget.isDark),
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _accentPicker() {
    const colors = [
      Color(0xFF00F0FF),
      Color(0xFFBC13FE),
      Color(0xFF00FF88),
      Color(0xFFFF2D78),
      Color(0xFFFF6B35),
      Color(0xFF5CA1FF),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: colors.map((c) {
        final sel = VeilTheme.accentColor == c;
        return GestureDetector(
          onTap: () {
            setState(() => VeilTheme.accentColor = c);
            widget.refreshApp();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sel ? 42 : 36,
            height: sel ? 42 : 36,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: sel ? c : Colors.transparent, width: 2),
              boxShadow: sel
                  ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)]
                  : [],
            ),
            child: Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _wallpaperSection() {
    final styles = {
      WallpaperStyle.cosmos: 'Cosmos',
      WallpaperStyle.mesh: 'Mesh',
      WallpaperStyle.nebula: 'Nebula',
      WallpaperStyle.circuits: 'Circuits',
      WallpaperStyle.aurora: 'Aurora',
      WallpaperStyle.matrix: 'Matrix',
    };
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: VeilButton(
                isDark: widget.isDark,
                label: 'Upload Wallpaper',
                gradient: [
                  VeilTheme.accentColor,
                  VeilTheme.accentColor.withValues(alpha: 0.7),
                ],
                icon: Icons.add_photo_alternate_outlined,
                onTap: _pickWallpaper,
              ),
            ),
            if (VeilTheme.useCustomBg) ...[
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  setState(() => VeilTheme.useCustomBg = false);
                  widget.refreshApp();
                },
                icon: const Icon(
                  Icons.restore_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: styles.entries.map((e) {
              final sel =
                  VeilTheme.currentWallpaper == e.key && !VeilTheme.useCustomBg;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    VeilTheme.useCustomBg = false;
                    VeilTheme.currentWallpaper = e.key;
                  });
                  widget.refreshApp();
                },
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: (widget.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? VeilTheme.accentColor : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wallpaper_rounded,
                        color: sel ? VeilTheme.accentColor : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 10,
                          color: sel
                              ? VeilTheme.accentColor
                              : VeilTheme.subText(widget.isDark),
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String title, Widget trailing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: VeilTheme.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: VeilTheme.accentColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        trailing,
      ],
    ),
  );

  Widget _tile(
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap, {
    Color? color,
  }) {
    final c = color ?? VeilTheme.accentColor;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: c, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: widget.isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        sub,
        style: TextStyle(color: VeilTheme.subText(widget.isDark), fontSize: 12),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: widget.isDark ? Colors.white30 : Colors.black38,
      ),
      onTap: onTap,
    );
  }

  Widget _div() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Divider(
      color: widget.isDark
          ? Colors.white10
          : Colors.black.withValues(alpha: 0.07),
      height: 1,
    ),
  );
}

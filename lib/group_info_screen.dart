// ─────────────────────────────────────────────────────────────────────────────
//  VeilChat · Group Info & Management  (Task 3)
//
//  A premium replacement for the old cramped "group info" AlertDialog.
//
//  Layout breakdown
//  ┌───────────────────────────────────────────────────────────────┐
//  │ SliverAppBar (expanded 280) · glassmorphic gradient header    │
//  │   • interactive avatar stack (up to 5 members, +N overflow)   │
//  │   • group name + member count + created date                  │
//  │   • Encryption Status Indicator chip (E2EE · ChaCha20)        │
//  ├───────────────────────────────────────────────────────────────┤
//  │ Pinned message banner (if any)                                │
//  ├───────────────────────────────────────────────────────────────┤
//  │ Quick action row: Media · Search · Mute · Wallpaper           │
//  ├───────────────────────────────────────────────────────────────┤
//  │ Options list: Media/Docs Gallery, Mute (custom duration),     │
//  │   Export Chat, Search in Group, Custom Wallpaper, Encryption  │
//  ├───────────────────────────────────────────────────────────────┤
//  │ Participants (StreamBuilder → instant reactive updates)       │
//  │   • Owner / Admin badges, per-member admin menu               │
//  │   • Add participant tile (admins only)                        │
//  ├───────────────────────────────────────────────────────────────┤
//  │ Danger zone: Leave group                                      │
//  └───────────────────────────────────────────────────────────────┘
//
//  Every mutating action goes through GroupService, which mutates the model
//  optimistically and pushes it onto `groupUpdateStream`, so this screen (and
//  the chat list) rebuild instantly — no manual refresh, no stale member rows.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'veil_theme.dart';
import 'veil_feedback.dart';
import 'services/group_service.dart';
import 'services/database_service.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String currentUser;
  final bool isDark;

  /// Called when the user taps "Search in Group" so the chat screen can open
  /// its own in-conversation search UI.
  final VoidCallback? onSearchRequested;

  /// Called when the user picks a new wallpaper for this group.
  final ValueChanged<String?>? onWallpaperChanged;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.currentUser,
    required this.isDark,
    this.onSearchRequested,
    this.onWallpaperChanged,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final GroupService _groups = GroupService();
  final DatabaseService _db = DatabaseService();

  bool _busy = false;

  Color get _accent => VeilTheme.accentColor;
  bool get _dark => widget.isDark;
  Color get _text => _dark ? Colors.white : const Color(0xFF0F172A);
  Color get _subtext => _dark ? Colors.white54 : Colors.black54;
  Color get _surface =>
      (_dark ? Colors.white : Colors.black).withOpacity(_dark ? 0.05 : 0.035);

  // ───────────────────────────── helpers ─────────────────────────────

  Future<T?> _guard<T>(Future<T> Function() action, {String? failureMessage}) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await action();
    } catch (e, st) {
      debugPrint('❌ GroupInfo action failed: $e\n$st');
      if (mounted) {
        VeilFeedback.error(context, failureMessage ?? 'Something went wrong');
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shared confirmation modal with haptic + visual feedback.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    IconData icon = Icons.warning_amber_rounded,
    Color? danger,
  }) async {
    HapticFeedback.mediumImpact();
    final color = danger ?? const Color(0xFFEF4444);
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (_dark ? const Color(0xFF0D1117) : Colors.white)
                    .withOpacity(0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color.withOpacity(0.28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.15),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(height: 14),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _text)),
                  const SizedBox(height: 8),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: _subtext, height: 1.4)),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                                color: _dark ? Colors.white24 : Colors.black12),
                          ),
                        ),
                        child: Text('CANCEL',
                            style: TextStyle(
                                color: _subtext,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.6)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shadowColor: color.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(confirmLabel.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.6)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  // ───────────────────────────── admin actions ─────────────────────────────

  Future<void> _kick(Group group, String member) async {
    final ok = await _confirm(
      title: 'Remove $member?',
      message:
          '$member will lose access to this group and its message history on their device.',
      confirmLabel: 'Remove',
      icon: Icons.person_remove_rounded,
    );
    if (!ok) return;

    final success = await _guard(
      () => _groups.removeMember(group.id, member),
      failureMessage: 'Could not remove $member',
    );
    if (!mounted) return;
    if (success == true) {
      VeilFeedback.success(context, '$member removed from group');
    } else {
      VeilFeedback.error(context, 'Could not remove $member');
    }
  }

  Future<void> _promote(Group group, String member) async {
    final ok = await _confirm(
      title: 'Make $member an admin?',
      message:
          'Admins can add or remove participants and promote other members.',
      confirmLabel: 'Promote',
      icon: Icons.shield_rounded,
      danger: _accent,
    );
    if (!ok) return;

    final success = await _guard(
      () => _groups.promoteToAdmin(group.id, member),
      failureMessage: 'Could not promote $member',
    );
    if (!mounted) return;
    success == true
        ? VeilFeedback.success(context, '$member is now an admin')
        : VeilFeedback.error(context, 'Could not promote $member');
  }

  Future<void> _demote(Group group, String member) async {
    final ok = await _confirm(
      title: 'Dismiss $member as admin?',
      message: '$member will remain a participant but lose admin privileges.',
      confirmLabel: 'Dismiss',
      icon: Icons.remove_moderator_rounded,
    );
    if (!ok) return;

    final success = await _guard(
      () => _groups.demoteAdmin(group.id, member),
      failureMessage: 'Could not dismiss $member',
    );
    if (!mounted) return;
    success == true
        ? VeilFeedback.success(context, '$member is no longer an admin')
        : VeilFeedback.error(context, 'Could not dismiss $member');
  }

  Future<void> _addMember(Group group) async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (_dark ? const Color(0xFF0D1117) : Colors.white)
                    .withOpacity(0.93),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _accent.withOpacity(0.28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [_accent, _accent.withOpacity(0.55)]),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 14),
                  Text('Add participant',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _text)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                    style: TextStyle(color: _text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Username',
                      hintStyle: TextStyle(color: _subtext),
                      prefixIcon:
                          Icon(Icons.alternate_email_rounded, color: _accent, size: 18),
                      filled: true,
                      fillColor: _surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('CANCEL',
                            style: TextStyle(
                                color: _subtext, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('ADD',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (username == null || username.isEmpty) return;
    if (group.members.contains(username)) {
      if (mounted) VeilFeedback.warning(context, '$username is already a member');
      return;
    }

    final success = await _guard(
      () => _groups.addMember(group.id, username),
      failureMessage: 'Could not add $username',
    );
    if (!mounted) return;
    success == true
        ? VeilFeedback.success(context, '$username added to the group')
        : VeilFeedback.error(context, 'Could not add $username');
  }

  Future<void> _leave(Group group) async {
    final isOwner = group.owner == widget.currentUser;
    final ok = await _confirm(
      title: 'Leave "${group.name}"?',
      message: isOwner
          ? 'You are the owner. Leaving removes the group from this device — consider promoting another admin first.'
          : 'You will stop receiving messages from this group on this device.',
      confirmLabel: 'Leave',
      icon: Icons.logout_rounded,
    );
    if (!ok) return;

    final success = await _guard(
      () => _groups.leaveGroup(group.id),
      failureMessage: 'Could not leave the group',
    );
    if (!mounted) return;
    if (success == true) {
      VeilFeedback.success(context, 'You left "${group.name}"');
      Navigator.pop(context, 'left'); // info screen
      Navigator.maybePop(context);    // chat screen
    } else {
      VeilFeedback.error(context, 'Could not leave the group');
    }
  }

  // ───────────────────────────── option actions ─────────────────────────────

  Future<void> _muteSheet(Group group) async {
    HapticFeedback.selectionClick();
    final options = <String, Duration?>{
      'For 8 hours': const Duration(hours: 8),
      'For 1 week': const Duration(days: 7),
      'Always': null, // muted indefinitely
    };

    final muted = _groups.isMutedNow(group);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _sheet(
        title: muted ? 'Notifications muted' : 'Mute notifications',
        children: [
          if (muted)
            _sheetTile(
              icon: Icons.notifications_active_rounded,
              label: 'Unmute notifications',
              color: _accent,
              onTap: () async {
                Navigator.pop(ctx);
                await _groups.setMuted(group.id, null);
                if (mounted) VeilFeedback.success(context, 'Notifications on');
              },
            ),
          ...options.entries.map(
            (e) => _sheetTile(
              icon: Icons.schedule_rounded,
              label: e.key,
              onTap: () async {
                Navigator.pop(ctx);
                final until =
                    e.value == null ? DateTime(2999) : DateTime.now().add(e.value!);
                await _groups.setMuted(group.id, until);
                if (mounted) {
                  VeilFeedback.success(context, 'Muted ${e.key.toLowerCase()}');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMediaGallery(Group group) async {
    HapticFeedback.selectionClick();
    final rows = await _guard(
      () => _db.getGroupMessages(widget.currentUser, group.id, limit: 500),
      failureMessage: 'Could not load media',
    );
    if (!mounted || rows == null) return;

    final media = rows
        .where((m) => const ['IMAGE', 'FILE', 'AUDIO'].contains(m['type']))
        .toList()
        .reversed
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _sheetShell(
          child: Column(
            children: [
              _sheetHandle('Media, links & docs'),
              Expanded(
                child: media.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.perm_media_outlined,
                                size: 44, color: _subtext),
                            const SizedBox(height: 10),
                            Text('No media shared yet',
                                style: TextStyle(color: _subtext, fontSize: 13)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: controller,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: media.length,
                        itemBuilder: (_, i) {
                          final m = media[i];
                          final path = (m['content'] ?? '').toString();
                          final isImage =
                              m['type'] == 'IMAGE' && File(path).existsSync();
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: isImage
                                ? Image.file(File(path), fit: BoxFit.cover)
                                : Container(
                                    color: _surface,
                                    child: Center(
                                      child: Icon(
                                        m['type'] == 'AUDIO'
                                            ? Icons.graphic_eq_rounded
                                            : Icons.insert_drive_file_rounded,
                                        color: _accent,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportChat(Group group) async {
    HapticFeedback.selectionClick();
    final rows = await _guard(
      () => _db.getGroupMessages(widget.currentUser, group.id, limit: 5000),
      failureMessage: 'Export failed',
    );
    if (!mounted || rows == null) return;

    try {
      final buffer = StringBuffer()
        ..writeln('VeilChat — ${group.name}')
        ..writeln('Exported ${DateFormat.yMMMd().add_jm().format(DateTime.now())}')
        ..writeln('Participants: ${group.members.join(', ')}')
        ..writeln('${'─' * 46}');

      for (final m in rows) {
        final ts = DateTime.fromMillisecondsSinceEpoch(
            (m['timestamp'] as num?)?.toInt() ?? 0);
        final type = m['type'] ?? 'TEXT';
        final body = type == 'TEXT'
            ? (m['content'] ?? '')
            : '<$type>';
        buffer.writeln(
            '[${DateFormat('yyyy-MM-dd HH:mm').format(ts)}] ${m['sender']}: $body');
      }

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/veilchat_${group.name.replaceAll(RegExp(r'\W'), '_')}.txt');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles([XFile(file.path)],
          text: 'VeilChat export — ${group.name}');
      if (mounted) VeilFeedback.success(context, 'Chat exported');
    } catch (e) {
      debugPrint('❌ Export failed: $e');
      if (mounted) VeilFeedback.error(context, 'Export failed');
    }
  }

  Future<void> _wallpaperSheet(Group group) async {
    HapticFeedback.selectionClick();
    const presets = <String, IconData>{
      'cosmos': Icons.auto_awesome_rounded,
      'mesh': Icons.grid_4x4_rounded,
      'nebula': Icons.blur_on_rounded,
      'circuits': Icons.memory_rounded,
      'aurora': Icons.waves_rounded,
      'matrix': Icons.terminal_rounded,
    };

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _sheet(
        title: 'Group wallpaper',
        children: [
          for (final e in presets.entries)
            _sheetTile(
              icon: e.value,
              label: e.key[0].toUpperCase() + e.key.substring(1),
              selected: group.wallpaper == e.key,
              onTap: () async {
                Navigator.pop(ctx);
                group.wallpaper = e.key;
                await _db.updateGroup(
                  accountOwner: widget.currentUser,
                  id: group.id,
                  wallpaper: e.key,
                );
                widget.onWallpaperChanged?.call(e.key);
                if (mounted) {
                  setState(() {});
                  VeilFeedback.success(context, 'Wallpaper updated');
                }
              },
            ),
        ],
      ),
    );
  }

  void _showEncryptionInfo(Group group) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _sheet(
        title: 'Encryption',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lock_rounded, color: _accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Messages in this group are end-to-end encrypted with '
                      'XChaCha20-Poly1305. Keys never leave your device.',
                      style: TextStyle(color: _subtext, fontSize: 13, height: 1.5),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _kv('Cipher', 'XChaCha20-Poly1305'),
                _kv('Key exchange', 'X25519'),
                _kv('Steganography', 'LSB image carrier (optional)'),
                _kv('Participants', '${group.members.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k,
                  style: TextStyle(
                      color: _subtext, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  // ───────────────────────────── sheet primitives ─────────────────────────────

  Widget _sheetShell({required Widget child}) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: (_dark ? const Color(0xFF0D1117) : Colors.white)
                  .withOpacity(0.94),
              border: Border(
                  top: BorderSide(color: _accent.withOpacity(0.22), width: 1.2)),
            ),
            child: child,
          ),
        ),
      );

  Widget _sheetHandle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _subtext.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: TextStyle(
                      color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  Widget _sheet({required String title, required List<Widget> children}) =>
      SafeArea(
        top: false,
        child: _sheetShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(title),
              ...children,
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool selected = false,
  }) =>
      ListTile(
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (color ?? _accent).withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color ?? _accent, size: 19),
        ),
        title: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: _text, fontSize: 14.5, fontWeight: FontWeight.w600)),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: _accent, size: 20)
            : null,
      );

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark ? const Color(0xFF05070D) : const Color(0xFFF6F8FF),
      body: StreamBuilder<Group>(
        // ✅ Reactive: kick/promote/add instantly rebuild this screen.
        stream: _groups.groupUpdateStream
            .where((g) => g.id == widget.groupId),
        builder: (context, snapshot) {
          final group = snapshot.data ?? _groups.getGroup(widget.groupId);
          if (group == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_off_rounded, size: 46, color: _subtext),
                  const SizedBox(height: 12),
                  Text('Group unavailable',
                      style: TextStyle(color: _subtext, fontSize: 14)),
                ],
              ),
            );
          }
          return _buildBody(group);
        },
      ),
    );
  }

  Widget _buildBody(Group group) {
    final isAdmin = _groups.isAdmin(group, widget.currentUser);
    final muted = _groups.isMutedNow(group);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Glassmorphic header ──────────────────────────────────────
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: 268,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: _text),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: LayoutBuilder(
            builder: (context, constraints) {
              final collapsed =
                  constraints.maxHeight <= kToolbarHeight + MediaQuery.of(context).padding.top + 12;
              return FlexibleSpaceBar(
                centerTitle: true,
                titlePadding:
                    const EdgeInsets.symmetric(horizontal: 56, vertical: 14),
                title: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: collapsed ? 1 : 0,
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _text, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                background: _header(group),
              );
            },
          ),
        ),

        // ── Pinned message banner ────────────────────────────────────
        if ((group.pinnedMessage ?? '').isNotEmpty)
          SliverToBoxAdapter(child: _pinnedBanner(group)),

        // ── Quick actions ────────────────────────────────────────────
        SliverToBoxAdapter(child: _quickActions(group, muted)),

        // ── Options list ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _section('GROUP OPTIONS', [
            _option(Icons.perm_media_rounded, 'Media, links & docs',
                'Browse everything shared here', () => _openMediaGallery(group)),
            _option(
                muted
                    ? Icons.notifications_off_rounded
                    : Icons.notifications_active_rounded,
                'Mute notifications',
                muted ? 'Currently muted' : 'Custom duration',
                () => _muteSheet(group)),
            _option(Icons.search_rounded, 'Search in group',
                'Find messages fast', () {
              Navigator.pop(context);
              widget.onSearchRequested?.call();
            }),
            _option(Icons.ios_share_rounded, 'Export chat',
                'Save a plain-text transcript', () => _exportChat(group)),
            _option(Icons.wallpaper_rounded, 'Group wallpaper',
                group.wallpaper ?? 'Default', () => _wallpaperSheet(group)),
            _option(Icons.verified_user_rounded, 'Encryption',
                'End-to-end encrypted', () => _showEncryptionInfo(group),
                trailing: _encryptionChip()),
          ]),
        ),

        // ── Participants ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Row(
              children: [
                Text('PARTICIPANTS',
                    style: TextStyle(
                        color: _subtext,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${group.members.length}',
                      style: TextStyle(
                          color: _accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),

        if (isAdmin)
          SliverToBoxAdapter(
            child: _memberCard(
              child: ListTile(
                onTap: () => _addMember(group),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent.withOpacity(0.15),
                    border: Border.all(color: _accent.withOpacity(0.4)),
                  ),
                  child: Icon(Icons.person_add_alt_1_rounded,
                      color: _accent, size: 20),
                ),
                title: Text('Add participant',
                    style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5)),
              ),
            ),
          ),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final member = group.members[index];
              return _memberTile(group, member, isAdmin);
            },
            childCount: group.members.length,
          ),
        ),

        // ── Danger zone ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: _dangerButton(
              icon: Icons.logout_rounded,
              label: 'LEAVE GROUP',
              onTap: _busy ? null : () => _leave(group),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────── header pieces ─────────────────────────────

  Widget _header(Group group) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient veil
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _accent.withOpacity(_dark ? 0.30 : 0.20),
                VeilTheme.neonPurple.withOpacity(_dark ? 0.22 : 0.14),
                Colors.transparent,
              ],
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(color: Colors.transparent),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _avatarStack(group),
                const SizedBox(height: 14),
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _text,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2),
                ),
                const SizedBox(height: 5),
                Text(
                  '${group.members.length} participants · created '
                  '${DateFormat.yMMMd().format(group.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _subtext, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _encryptionChip(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Interactive overlapping avatar stack (max 5 + overflow counter).
  Widget _avatarStack(Group group) {
    const maxVisible = 5;
    final visible = group.members.take(maxVisible).toList();
    final overflow = group.members.length - visible.length;
    const size = 46.0;
    const overlap = 30.0;
    final width = visible.length * overlap + (overflow > 0 ? overlap : 0) + 16;

    return SizedBox(
      height: size + 4,
      width: width.clamp(size, 320).toDouble(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * overlap,
              child: _avatarBubble(visible[i], size, group),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * overlap,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surface,
                  border: Border.all(
                      color: _dark ? Colors.white24 : Colors.black12, width: 2),
                ),
                child: Text('+$overflow',
                    style: TextStyle(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatarBubble(String member, double size, Group group) {
    final isOwner = group.owner == member;
    final isAdmin = group.admins.contains(member);
    return Tooltip(
      message: member + (isOwner ? ' · owner' : isAdmin ? ' · admin' : ''),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: isOwner
                ? [_accent, VeilTheme.neonPurple]
                : [_accent.withOpacity(0.7), _accent.withOpacity(0.35)],
          ),
          border: Border.all(
              color: _dark ? const Color(0xFF05070D) : Colors.white, width: 2.4),
          boxShadow: [
            BoxShadow(color: _accent.withOpacity(0.28), blurRadius: 10),
          ],
        ),
        child: Text(
          member.isEmpty ? '?' : member[0].toUpperCase(),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  Widget _encryptionChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lock_rounded, size: 12, color: Color(0xFF10B981)),
            SizedBox(width: 6),
            Text('END-TO-END ENCRYPTED',
                style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7)),
          ],
        ),
      );

  Widget _pinnedBanner(Group group) => Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin_rounded, size: 16, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PINNED',
                      style: TextStyle(
                          color: _accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Text(group.pinnedMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _text, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _quickActions(Group group, bool muted) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            _quick(Icons.perm_media_rounded, 'Media',
                () => _openMediaGallery(group)),
            _quick(Icons.search_rounded, 'Search', () {
              Navigator.pop(context);
              widget.onSearchRequested?.call();
            }),
            _quick(
                muted
                    ? Icons.notifications_off_rounded
                    : Icons.notifications_active_rounded,
                muted ? 'Muted' : 'Mute',
                () => _muteSheet(group)),
            _quick(Icons.wallpaper_rounded, 'Theme',
                () => _wallpaperSheet(group), last: true),
          ],
        ),
      );

  Widget _quick(IconData icon, String label, VoidCallback onTap,
          {bool last = false}) =>
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: last ? 0 : 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _accent.withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_dark ? 0.28 : 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(icon, color: _accent, size: 20),
                    const SizedBox(height: 6),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _subtext,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: _subtext,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: (_dark ? Colors.white : Colors.black)
                        .withOpacity(0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_dark ? 0.25 : 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(children: children),
            ),
          ],
        ),
      );

  Widget _option(IconData icon, String title, String subtitle, VoidCallback onTap,
          {Widget? trailing}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: _accent, size: 19),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _subtext, fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(Icons.chevron_right_rounded,
                        color: _subtext, size: 20),
              ],
            ),
          ),
        ),
      );

  Widget _memberCard({required Widget child}) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: (_dark ? Colors.white : Colors.black).withOpacity(0.06)),
        ),
        child: child,
      );

  Widget _memberTile(Group group, String member, bool viewerIsAdmin) {
    final isSelf = member == widget.currentUser;
    final isOwner = group.owner == member;
    final isMemberAdmin = group.admins.contains(member);
    final canModerate = viewerIsAdmin && !isSelf && !isOwner;

    return _memberCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isOwner
                      ? [_accent, VeilTheme.neonPurple]
                      : [_accent.withOpacity(0.65), _accent.withOpacity(0.3)],
                ),
              ),
              child: Text(member.isEmpty ? '?' : member[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            if (isOwner || isMemberAdmin)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dark ? const Color(0xFF05070D) : Colors.white,
                  ),
                  child: Icon(
                    isOwner ? Icons.star_rounded : Icons.shield_rounded,
                    size: 11,
                    color: isOwner ? const Color(0xFFF59E0B) : _accent,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(isSelf ? 'You' : member,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
            ),
            if (isOwner || isMemberAdmin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (isOwner ? const Color(0xFFF59E0B) : _accent)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(isOwner ? 'OWNER' : 'ADMIN',
                    style: TextStyle(
                        color: isOwner ? const Color(0xFFF59E0B) : _accent,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
            ],
          ],
        ),
        subtitle: Text('@$member',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _subtext, fontSize: 11.5)),
        trailing: canModerate
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: _subtext, size: 20),
                color: _dark ? const Color(0xFF11172A) : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                onSelected: (value) {
                  switch (value) {
                    case 'promote':
                      _promote(group, member);
                      break;
                    case 'demote':
                      _demote(group, member);
                      break;
                    case 'kick':
                      _kick(group, member);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (!isMemberAdmin)
                    _menuItem('promote', Icons.shield_rounded, 'Make admin', _accent),
                  if (isMemberAdmin && group.owner == widget.currentUser)
                    _menuItem('demote', Icons.remove_moderator_rounded,
                        'Dismiss as admin', const Color(0xFFF59E0B)),
                  _menuItem('kick', Icons.person_remove_rounded,
                      'Remove from group', const Color(0xFFEF4444)),
                ],
              )
            : null,
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
          String value, IconData icon, String label, Color color) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _dangerButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: const Color(0xFFEF4444).withOpacity(0.35)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.8)),
                ),
              ],
            ),
          ),
        ),
      );
}

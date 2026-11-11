import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/group_service.dart';
import 'services/network_service.dart';
import 'group_chat_detail_screen.dart';
import 'services/database_service.dart';

class GroupChatListScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;
  final String sharedKey;

  const GroupChatListScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
    required this.sharedKey,
  });

  @override
  State<GroupChatListScreen> createState() => _GroupChatListScreenState();
}

class _GroupChatListScreenState extends State<GroupChatListScreen>
    with SingleTickerProviderStateMixin {
  final GroupService _groupService = GroupService();
  List<Group> _groups = [];
  bool _isLoading = true;
  String? _currentUser;

  StreamSubscription? _groupsSub;
  StreamSubscription? _groupUpdateSub;
  StreamSubscription? _groupMessageSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _currentUser = NetworkService().currentUser;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initGroups();
    _setupListeners();
  }

  Future<void> _initGroups() async {
    if (_currentUser == null) return;
    await _groupService.loadGroups(_currentUser!);
    if (mounted) {
      setState(() {
        _groups = _groupService.groups;
        _isLoading = false;
      });
    }
  }

  void _setupListeners() {
    _groupsSub = _groupService.groupsStream.listen((groups) {
      if (mounted) {
        setState(() {
          _groups = groups;
        });
      }
    });

    _groupUpdateSub = _groupService.groupUpdateStream.listen((group) {});
    _groupMessageSub = _groupService.groupMessageStream.listen((message) {
      if (mounted)
        setState(() {
          _groups = _groupService.groups;
        });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _groupsSub?.cancel();
    _groupUpdateSub?.cancel();
    _groupMessageSub?.cancel();
    super.dispose();
  }

  void _createGroup() {
    _showCreateGroupDialog();
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    final membersController = TextEditingController();
    final themeColor = VeilTheme.accentColor;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1117), const Color(0xFF161B2E)]
                  : [const Color(0xFFF8F9FF), const Color(0xFFEEF2FF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: themeColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: themeColor.withValues(alpha: 0.15),
                blurRadius: 30,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [themeColor, VeilTheme.neonPurple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: themeColor.withValues(alpha: 0.4),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.group_add_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Create New Group',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start a secure encrypted group chat',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 22),
                // Group name field
                _groupTextField(
                  controller: nameController,
                  label: 'Group name',
                  icon: Icons.group_rounded,
                  isDark: widget.isDark,
                  themeColor: themeColor,
                ),
                const SizedBox(height: 14),
                // Members field
                _groupTextField(
                  controller: membersController,
                  label: 'Add members (comma separated)',
                  icon: Icons.people_rounded,
                  isDark: widget.isDark,
                  themeColor: themeColor,
                  hint: 'alice, bob, charlie',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 12,
                      color: themeColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'You will be added as the group owner',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isDark ? Colors.white30 : Colors.black38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: widget.isDark
                                  ? Colors.white24
                                  : Colors.black12,
                            ),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: widget.isDark
                                ? Colors.white54
                                : Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          final membersStr = membersController.text.trim();
                          if (name.isEmpty) return;

                          final currentUser = _currentUser ?? "";
                          final existingGroups = await DatabaseService()
                              .getGroups(currentUser);
                          if (existingGroups.any((g) => g['name'] == name)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Group with that name already exists!',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          List<String> members = [];
                          if (membersStr.isNotEmpty) {
                            members = membersStr
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                          }

                          Navigator.pop(ctx);
                          final success = await _groupService.createGroup(
                            groupName: name,
                            members: members,
                          );
                          if (success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Group "$name" created'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: themeColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          shadowColor: themeColor.withValues(alpha: 0.4),
                          elevation: 4,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.group_add_rounded, size: 15),
                            SizedBox(width: 6),
                            Text(
                              'Create Group',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ), // SingleChildScrollView
        ),
      ),
    );
  }

  Widget _groupTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    required Color themeColor,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: themeColor.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: themeColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                hintStyle: TextStyle(
                  // Fixed: 'white20' is not a valid member, used 'white24' instead
                  color: isDark ? Colors.white24 : Colors.black26,
                  fontSize: 13,
                ),
                labelStyle: TextStyle(
                  color: themeColor.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = VeilTheme.accentColor;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 20, 25, 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: themeColor.withValues(alpha: 0.3),
                              blurRadius: 15,
                            ),
                          ],
                          border: Border.all(
                            color: themeColor.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.group_rounded,
                          color: themeColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            themeColor,
                            widget.isDark ? Colors.white : Colors.black87,
                            themeColor,
                          ],
                        ).createShader(bounds),
                        child: Text(
                          'Groups',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: widget.isDark,
                    onChanged: (v) => widget.toggleTheme(),
                    activeThumbColor: themeColor,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: themeColor))
                  : _groups.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: _buildEmptyState(),
                    )
                  : RefreshIndicator(
                      color: themeColor,
                      onRefresh: () async {
                        if (_currentUser != null) {
                          await _groupService.loadGroups(_currentUser!);
                        }
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                          left: 15,
                          right: 15,
                          top: 10,
                          bottom: 150,
                        ),
                        itemCount: _groups.length,
                        itemBuilder: (ctx, i) => _buildGroupTile(_groups[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton(
          onPressed: _createGroup,
          backgroundColor: themeColor,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildEmptyState() {
    final themeColor = VeilTheme.accentColor;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.group_add_rounded,
                  size: 60,
                  color: themeColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: VeilTheme.text(widget.isDark),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create a group to start chatting with multiple friends',
              style: TextStyle(
                fontSize: 14,
                color: VeilTheme.subText(widget.isDark),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            VeilButton(
              isDark: widget.isDark,
              label: 'CREATE GROUP',
              gradient: [themeColor, themeColor.withValues(alpha: 0.7)],
              onTap: _createGroup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupTile(Group group) {
    final themeColor = VeilTheme.accentColor;
    final hasUnread = group.unreadCount > 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _groupService.markGroupAsRead(group.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatDetailScreen(
              groupId: group.id,
              groupName: group.name,
              isDark: widget.isDark,
              currentUser: _currentUser ?? '',
              sharedKey: widget.sharedKey,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(15),
        decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 25),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: themeColor.withValues(alpha: 0.1),
                  backgroundImage: group.avatarPath != null
                      ? FileImage(File(group.avatarPath!))
                      : null,
                  child: group.avatarPath == null
                      ? Text(
                          group.name[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isDark ? Colors.black : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '${group.members.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: VeilTheme.text(widget.isDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (group.isMuted)
                        Icon(
                          Icons.volume_off_rounded,
                          size: 16,
                          color: widget.isDark
                              ? Colors.white38
                              : Colors.black38,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    () {
                      final lm = group.lastMessage ?? '';
                      if (lm.isEmpty) return 'No messages yet';
                      if (lm.startsWith('/') || lm.contains('.enc'))
                        return '📁 Media';
                      return lm;
                    }(),
                    style: TextStyle(
                      fontSize: 14,
                      color: VeilTheme.subText(widget.isDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (group.lastMessageTime != null)
                  Text(
                    _formatTimestamp(group.lastMessageTime!),
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                const SizedBox(height: 6),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: themeColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${group.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${date.day}/${date.month}';
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/network_service.dart';
import 'services/database_service.dart';
import 'chat_detail_screen.dart';
import 'chat_lock_screen.dart';
import 'contact_list_screen.dart';

class ChatListScreen extends StatefulWidget {
  final bool isDark;
  final String sharedKey;
  final String username;
  final VoidCallback toggleTheme;

  const ChatListScreen({
    super.key,
    required this.isDark,
    required this.sharedKey,
    required this.username,
    required this.toggleTheme,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final NetworkService _network = NetworkService();
  final DatabaseService _db = DatabaseService();

  List<Map<String, dynamic>> _chatList = [];
  Map<String, String> _onlineStatus = {};
  Timer? _onlineRefreshTimer;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;

  StreamSubscription? _userListSub;
  StreamSubscription? _messageSub;

  @override
  void initState() {
    super.initState();
    _loadChatList();

    // Offline messages save hone ke baad UI ko refresh karega
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _loadChatList();
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _loadChatList();
    });

    _setupListeners();
    // Refresh online status every 30 seconds
    _onlineRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _network.requestUserList(),
    );
  }

  @override
  void dispose() {
    _onlineRefreshTimer?.cancel();
    _searchController.dispose();
    _userListSub?.cancel();
    _messageSub?.cancel();
    super.dispose();
  }

  Future<void> _loadChatList() async {
    if (!mounted) return;
    final lastMessages = await _db.getLastMessages(widget.username);
    final unreadCounts = <String, int>{};
    for (var msg in lastMessages) {
      final contact = msg['contact'] as String;
      unreadCounts[contact] = await _db.getUnreadCount(
        widget.username,
        contact,
      );
    }

    final List<Map<String, dynamic>> list = [];
    for (var msg in lastMessages) {
      final contact = msg['contact'] as String;
      String lastContent = msg['content'] ?? '';
      final lastTime = msg['timestamp'] as int? ?? 0;
      final type = msg['type'] as String? ?? 'TEXT';
      final isMe = msg['isMe'] == 1;

      // PERF: Skip decryption in chat list — show icon-based preview
      // Decryption only happens when opening the actual chat
      String displayText;
      switch (type) {
        case 'IMAGE':
          displayText = '📷 Photo';
          break;
        case 'AUDIO':
          displayText = '🎤 Voice message';
          break;
        case 'FILE':
          displayText = '📁 File';
          break;
        default:
          // Show lock icon for encrypted text - fast, no crypto work
          displayText = lastContent.isNotEmpty ? '🔒 Message' : '';
      }

      // Load contact avatar path from DB
      String? avatarPath;
      final contactData = await _db.getContact(widget.username, contact);
      if (contactData != null) {
        avatarPath = contactData['avatarPath'] as String?;
      }
      list.add({
        'contact': contact,
        'lastMessage': displayText,
        'lastTime': lastTime,
        'type': type,
        'isMe': isMe,
        'status': msg['status'] ?? 'sent',
        'unread': unreadCounts[contact] ?? 0,
        'isOnline': _onlineStatus[contact] == 'Online',
        'avatarPath': avatarPath,
      });
    }

    list.sort((a, b) => b['lastTime'].compareTo(a['lastTime']));

    if (mounted) {
      setState(() {
        _chatList = list;
        _isLoading = false;
      });
    }
  }

  void _setupListeners() {
    _userListSub = _network.userListStream.listen((data) {
      if (data['type'] == 'USER_LIST') {
        final rawUsers = data['users'] as Map? ?? {};
        // Handle both old format (String) and new format (Map with status/lastSeen)
        final statusMap = <String, String>{};
        rawUsers.forEach((k, v) {
          if (v is String)
            statusMap[k.toString()] = v;
          else if (v is Map)
            statusMap[k.toString()] = v['status']?.toString() ?? 'Offline';
        });
        if (mounted) {
          setState(() {
            _onlineStatus = statusMap;
            for (var item in _chatList) {
              item['isOnline'] = statusMap[item['contact']] == 'Online';
            }
          });
        }
      }
    });

    _messageSub = _network.messageStream.listen((data) {
      if (data['type'] != 'TYPING' && data['sender'] != null) {
        debugPrint(
          '📨 New message from ${data['sender']}, reloading chat list',
        );
        _loadChatList();
      }
    });

    _network.sendPacket("GET_USERS", {});
  }

  void _applySearch(String query) {
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _filteredChatList {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return _chatList;
    return _chatList
        .where((chat) => chat['contact'].toLowerCase().contains(query))
        .toList();
  }

  Widget _buildListTick(String status) {
    if (status == 'read') {
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: widget.isDark ? const Color(0xFF00CFFF) : Colors.blue,
      );
    } else if (status == 'delivered') {
      return Icon(
        Icons.done_all_rounded,
        size: 14,
        color: widget.isDark ? Colors.white38 : Colors.black38,
      );
    }
    return Icon(
      Icons.done_rounded,
      size: 14,
      color: widget.isDark ? Colors.white24 : Colors.black26,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = VeilTheme.accentColor;

    return SafeArea(
      child: Column(
        children: [
          // Header
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
                        Icons.shield_moon_rounded,
                        color: themeColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: widget.isDark
                            ? [themeColor, Colors.white, themeColor]
                            : [themeColor, Colors.black87, themeColor],
                      ).createShader(bounds),
                      child: const Text(
                        "VeilChat",
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
                Row(
                  children: [
                    // Contacts button
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContactListScreen(
                            isDark: widget.isDark,
                            toggleTheme: widget.toggleTheme,
                            username: widget.username,
                            sharedKey: widget.sharedKey,
                          ),
                        ),
                      ).then((_) => _loadChatList()),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: themeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          Icons.people_alt_rounded,
                          color: themeColor,
                          size: 22,
                        ),
                      ),
                    ),
                    Switch(
                      value: widget.isDark,
                      onChanged: (v) => widget.toggleTheme(),
                      activeThumbColor: themeColor,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search bar
          Container(
            margin: const EdgeInsets.all(15),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            height: 50,
            decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 15),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  color: widget.isDark ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _applySearch,
                    style: TextStyle(
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: "Search contacts...",
                      hintStyle: TextStyle(
                        color: widget.isDark ? Colors.white54 : Colors.black54,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Chat list
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: themeColor))
                : _filteredChatList.isEmpty
                ? SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 30, bottom: 100),
                      child: _buildEmptyState(),
                    ),
                  )
                : RefreshIndicator(
                    color: themeColor,
                    onRefresh: () async {
                      _network.sendPacket("GET_USERS", {});
                      await _loadChatList();
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: _filteredChatList.length,
                      itemBuilder: (ctx, index) =>
                          _buildChatTile(_filteredChatList[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final themeColor = VeilTheme.accentColor;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 80,
            color: widget.isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 20),
          Text(
            "No conversations yet",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: widget.isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Start a secure chat with an online contact",
            style: TextStyle(
              fontSize: 14,
              color: widget.isDark ? Colors.white30 : Colors.black38,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          VeilButton(
            isDark: widget.isDark,
            label: "FIND CONTACTS",
            gradient: [themeColor, themeColor.withValues(alpha: 0.7)],
            onTap: () async {
              _network.sendPacket("GET_USERS", {});
              try {
                final data = await _network.userListStream.first;
                if (!mounted) return;
                final rawU = data['users'] as Map? ?? {};
                final users = <String, String>{};
                rawU.forEach((k, v) {
                  if (v is String)
                    users[k.toString()] = v;
                  else if (v is Map)
                    users[k.toString()] = v['status']?.toString() ?? 'Offline';
                });
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: widget.isDark
                        ? const Color(0xFF0F172A)
                        : Colors.white,
                    title: Text(
                      'All Contacts',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView(
                        shrinkWrap: true,
                        children: users.entries.map((e) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: themeColor.withValues(
                                alpha: 0.2,
                              ),
                              child: Text(
                                e.key[0].toUpperCase(),
                                style: TextStyle(
                                  color: themeColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              e.key,
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              e.value,
                              style: TextStyle(
                                color: e.value == "Online"
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatDetailScreen(
                                    contactName: e.key,
                                    isDark: widget.isDark,
                                    sharedKey: widget.sharedKey,
                                    myUsername: widget.username,
                                  ),
                                ),
                              ).then((_) {
                                _loadChatList();
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              } catch (e) {
                debugPrint("Failed to get user list: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Could not fetch contacts")),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat) {
    final contact = chat['contact'] as String;
    final lastMessage = chat['lastMessage'] as String;
    final lastTime = chat['lastTime'] as int;
    final unread = chat['unread'] as int;
    final isOnline = chat['isOnline'] as bool;
    final isMe = chat['isMe'] as bool;
    final themeColor = VeilTheme.accentColor;

    String timeStr = '';
    if (lastTime > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(lastTime);
      final now = DateTime.now();
      if (date.day == now.day &&
          date.month == now.month &&
          date.year == now.year) {
        timeStr = DateFormat('HH:mm').format(date);
      } else if (date.year == now.year &&
          date.month == now.month &&
          now.day - date.day == 1) {
        timeStr = 'Yesterday';
      } else {
        timeStr = DateFormat('dd/MM').format(date);
      }
    }

    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        final isLocked = await ChatLockScreen.isLocked(
          contact,
          widget.username,
        );
        if (!context.mounted) return;
        if (isLocked) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatLockScreen(
                contactName: contact,
                myUsername: widget.username,
                isDark: widget.isDark,
                child: ChatDetailScreen(
                  contactName: contact,
                  isDark: widget.isDark,
                  sharedKey: widget.sharedKey,
                  myUsername: widget.username,
                ),
              ),
            ),
          ).then((_) {
            _loadChatList();
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatDetailScreen(
                contactName: contact,
                isDark: widget.isDark,
                sharedKey: widget.sharedKey,
                myUsername: widget.username,
              ),
            ),
          ).then((_) {
            _loadChatList();
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        padding: const EdgeInsets.all(15),
        decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 25),
        child: Row(
          children: [
            Stack(
              children: [
                Hero(
                  tag: "avatar-$contact",
                  child: () {
                    final ap = chat['avatarPath'] as String?;
                    final hasImg =
                        ap != null && ap.isNotEmpty && File(ap).existsSync();
                    return CircleAvatar(
                      radius: 28,
                      backgroundColor: themeColor.withValues(alpha: 0.1),
                      backgroundImage: hasImg
                          ? FileImage(File(ap)) as ImageProvider
                          : null,
                      child: !hasImg
                          ? Text(
                              contact[0].toUpperCase(),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: themeColor,
                              ),
                            )
                          : null,
                    );
                  }(),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF88),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.isDark ? Colors.black : Colors.white,
                          width: 2,
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
                  Text(
                    contact,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: VeilTheme.text(widget.isDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isMe)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _buildListTick(
                            chat['status'] as String? ?? 'sent',
                          ),
                        ),
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: VeilTheme.subText(widget.isDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lastTime > 0)
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                const SizedBox(height: 6),
                if (unread > 0)
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
                      unread > 99 ? '99+' : '$unread',
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
}

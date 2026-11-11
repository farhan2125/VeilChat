import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'veil_theme.dart';
import 'veil_backgrounds.dart';
import 'chat_list_screen.dart';
import 'group_chat_list_screen.dart';
import 'encrypt_screen.dart';
import 'stego_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';
import 'services/network_service.dart';
import 'services/database_service.dart';
import 'services/group_service.dart';
import 'services/notification_service.dart';

class MainScreen extends StatefulWidget {
  final bool isDarkInitial;
  final String sharedKey;
  final String username;

  const MainScreen({
    super.key,
    required this.isDarkInitial,
    required this.sharedKey,
    required this.username,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late bool isDark;
  int _currentIndex = 0;
  StreamSubscription? _callSub;
  StreamSubscription? _networkSub;
  final _secureStorage = const FlutterSecureStorage();
  bool _isReconnecting = false;
  String _reconnectMsg = '';
  // ✅ BUG FIX: prevent duplicate CallScreen pushes if OFFER arrives twice
  bool _incomingCallActive = false;
  bool _appInForeground = true;
  String? _activeChatContact;
  int _chatUnreadCount = 0; // badge on chats tab
  int _groupUnreadCount = 0; // badge on groups tab

  // Lazy screen init - only build screen when first visited
  final Set<int> _visitedScreens = {0}; // Start with chat list (index 0)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isDark = widget.isDarkInitial;
    VeilTheme.accentColor = isDark
        ? const Color(0xFF00F0FF)
        : const Color(0xFFFF59B6);

    _saveKey();
    GroupService().loadGroups(widget.username);
    // Precache background images to avoid decode jank on first render
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheBackgrounds());

    // Listen for reconnect events to show banner
    _networkSub = NetworkService().messageStream.listen((data) {
      if (!mounted) return;
      final type = data['type'];
      if (type == 'RECONNECTING') {
        setState(() {
          _isReconnecting = true;
          _reconnectMsg = 'Reconnecting... (attempt ${data['attempt']})';
        });
      } else if (type == 'RECONNECTED') {
        setState(() {
          _isReconnecting = false;
          _reconnectMsg = '';
        });
      } else if (type == 'RECONNECT_FAILED') {
        setState(() {
          _isReconnecting = false;
          _reconnectMsg = 'Connection lost';
        });
      } else if (['TEXT', 'IMAGE', 'AUDIO', 'FILE'].contains(type)) {
        // Refresh badge counts on new message
        _refreshUnreadCounts();
        // Show notification if app is in background OR user is on a different chat
        final sender = data['sender'] as String?;
        if (sender != null && sender != NetworkService().currentUser) {
          final isOnThisChat =
              _appInForeground &&
              _activeChatContact == sender &&
              _currentIndex == 0;
          if (!isOnThisChat) {
            NotificationService().showMessageNotification(
              sender: sender,
              message: data['content']?.toString() ?? '',
              type: type,
              isDark: isDark,
            );
          }
        }
      }
    });

    _callSub = NetworkService().callStream.listen((data) {
      if (!mounted) return;
      if (data['type'] == 'OFFER') {
        // ✅ FIX: Don't push a second CallScreen if one is already open
        if (_incomingCallActive) return;
        final caller = data['sender'] as String? ?? '';
        if (caller.isEmpty) return;
        final offerData = data['data'] as Map?;
        final sdpStr = offerData?['sdp']?.toString() ?? '';
        final isAudio = !sdpStr.contains('m=video');
        if (!_appInForeground) {
          NotificationService().showIncomingCallNotification(
            caller,
            isDark: isDark,
          );
        }
        _incomingCallActive = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallScreen(
              contactName: caller,
              isIncoming: true,
              isDark: isDark,
              isAudioOnly: isAudio,
              initialOffer: offerData,
            ),
          ),
        ).then((_) {
          // Reset flag when CallScreen pops (call ended)
          if (mounted) setState(() => _incomingCallActive = false);
        });
      }
    });
  }

  Future<void> _saveKey() async {
    if (widget.sharedKey.isNotEmpty) {
      await _secureStorage.write(
        key: 'veilchat_shared_key',
        value: widget.sharedKey,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callSub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    // Clear notifications when user opens app
    if (_appInForeground) {
      NotificationService().cancelAllNotifications();
    }
  }

  Future<void> _refreshUnreadCounts() async {
    if (!mounted) return;
    final db = DatabaseService();
    // Total unread across all contacts
    final chats = await db.getLastMessages(widget.username);
    int chatUnread = 0;
    for (final msg in chats) {
      chatUnread += await db.getUnreadCount(
        widget.username,
        msg['contact'] as String,
      );
    }
    // Group unread - use in-memory groups (no DB query needed)
    final groups = GroupService().groups;
    int groupUnread = 0;
    for (final g in groups) {
      groupUnread += g.unreadCount;
    }
    if (mounted)
      setState(() {
        _chatUnreadCount = chatUnread;
        _groupUnreadCount = groupUnread;
      });
  }

  void _precacheBackgrounds() {
    final images = isDark
        ? [
            'assets/images/chat_dark.jpg',
            'assets/images/group_dark.jpg',
            'assets/images/encrypt_dark.jpg',
            'assets/images/stego_dark.jpg',
            'assets/images/settings_dark.jpg',
          ]
        : [
            'assets/images/chat_light.jpg',
            'assets/images/group_light.jpg',
            'assets/images/encrypt_light.jpg',
            'assets/images/stego_light.jpg',
            'assets/images/settings_light.jpg',
          ];
    for (final img in images) {
      precacheImage(AssetImage(img), context);
    }
  }

  void toggleTheme() {
    setState(() {
      isDark = !isDark;
      VeilTheme.accentColor = isDark
          ? const Color(0xFF00F0FF)
          : const Color(0xFFFF59B6);
    });
  }

  void refreshApp() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      ChatListScreen(
        isDark: isDark,
        sharedKey: widget.sharedKey,
        username: widget.username,
        toggleTheme: toggleTheme,
      ),
      GroupChatListScreen(
        isDark: isDark,
        toggleTheme: toggleTheme,
        sharedKey: widget.sharedKey,
      ),
      EncryptScreen(
        isDark: isDark,
        toggleTheme: toggleTheme,
        sharedKey: widget.sharedKey,
      ),
      StegoScreen(isDark: isDark, toggleTheme: toggleTheme),
      SettingsScreen(
        isDark: isDark,
        toggleTheme: toggleTheme,
        refreshApp: refreshApp,
      ),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: true,
      body: Column(
        children: [
          // Reconnect banner
          if (_isReconnecting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.orange.withValues(alpha: 0.9),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _reconnectMsg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: VeilBackground(
                    key: ValueKey(_currentIndex),
                    isDark: isDark,
                    screenIndex: _currentIndex,
                  ),
                ),
                IndexedStack(
                  index: _currentIndex,
                  children: List.generate(screens.length, (i) {
                    // Only build screen if it has been visited
                    if (!_visitedScreens.contains(i)) {
                      return const SizedBox.shrink();
                    }
                    return screens[i];
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildNavBar(),
      ), // Respects home button on all phones
    );
  }

  Widget _buildNavBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(
                  0,
                  Icons.chat_bubble_outline_rounded,
                  Icons.chat_bubble_rounded,
                ),
                _navItem(1, Icons.group_outlined, Icons.group_rounded),
                _navItem(2, Icons.lock_open_rounded, Icons.lock_rounded),
                _navItem(3, Icons.image_outlined, Icons.image_rounded),
                _navItem(4, Icons.settings_outlined, Icons.settings_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon) {
    final isActive = _currentIndex == index;
    final color = VeilTheme.accentColor;
    // Badge count for chats (0) and groups (1)
    final badgeCount = index == 0
        ? _chatUnreadCount
        : index == 1
        ? _groupUnreadCount
        : 0;
    return GestureDetector(
      onTap: () {
        if (_currentIndex != index)
          setState(() {
            _currentIndex = index;
            _visitedScreens.add(index);
          });
        _refreshUnreadCounts();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: isActive
            ? BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              )
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive
                  ? color
                  : (isDark ? Colors.white30 : Colors.black26),
              size: 24,
            ),
            if (badgeCount > 0)
              Positioned(
                top: -4,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

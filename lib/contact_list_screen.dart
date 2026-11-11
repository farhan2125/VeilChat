import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'chat_detail_screen.dart';
import 'services/network_service.dart';
import 'services/database_service.dart';

/// Full contact list screen showing all registered users.
/// - Shows online/offline status with green dot
/// - Search/filter by username
/// - Tap to open chat directly
/// - Star to favourite
/// - Shows saved contacts vs all registered users in two tabs
class ContactListScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;
  final String username;
  final String sharedKey;

  const ContactListScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
    required this.username,
    required this.sharedKey,
  });

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen>
    with SingleTickerProviderStateMixin {
  final NetworkService _network = NetworkService();
  final DatabaseService _db = DatabaseService();

  Map<String, String> _allUsers = {}; // username -> Online/Offline
  List<Map<String, dynamic>> _savedContacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  StreamSubscription? _userListSub;
  Set<String> _favourites = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();

    // Listen for live online status updates
    _userListSub = _network.userListStream.listen((data) {
      if (!mounted) return;
      if (data['users'] != null) {
        setState(() {
          final rawU = data['users'] as Map? ?? {};
          final parsed = <String, String>{};
          rawU.forEach((k, v) {
            if (v is String)
              parsed[k.toString()] = v;
            else if (v is Map)
              parsed[k.toString()] = v['status']?.toString() ?? 'Offline';
          });
          _allUsers = parsed;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _userListSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Get saved contacts from DB
    final contacts = await _db.getContacts(widget.username);
    _savedContacts = contacts.where((c) => c['isBlocked'] != 1).toList();
    _favourites = {
      for (var c in contacts)
        if (c['isFavorite'] == 1) c['contactName'] as String,
    };

    // Request fresh user list from server
    _network.requestUserList();

    // Wait briefly for user list response
    try {
      final data = await _network.userListStream.first.timeout(
        const Duration(seconds: 5),
      );
      if (mounted) {
        setState(() {
          final rawU = data['users'] as Map? ?? {};
          final parsed = <String, String>{};
          rawU.forEach((k, v) {
            if (v is String)
              parsed[k.toString()] = v;
            else if (v is Map)
              parsed[k.toString()] = v['status']?.toString() ?? 'Offline';
          });
          _allUsers = parsed;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveContact(String contactName) async {
    await _db.saveContact(owner: widget.username, contactName: contactName);
    final contacts = await _db.getContacts(widget.username);
    if (mounted)
      setState(
        () => _savedContacts = contacts
            .where((c) => c['isBlocked'] != 1)
            .toList(),
      );
    showVeilSnack(context, '$contactName saved to contacts');
  }

  Future<void> _toggleFavourite(String contactName) async {
    final isFav = _favourites.contains(contactName);
    await _db.toggleContactFavorite(widget.username, contactName, !isFav);
    setState(() {
      if (isFav)
        _favourites.remove(contactName);
      else
        _favourites.add(contactName);
    });
  }

  void _openChat(String contactName) {
    // Save contact first if not saved
    final isSaved = _savedContacts.any((c) => c['contactName'] == contactName);
    if (!isSaved) _saveContact(contactName);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          contactName: contactName,
          isDark: widget.isDark,
          sharedKey: widget.sharedKey,
          myUsername: widget.username,
        ),
      ),
    );
  }

  List<MapEntry<String, String>> get _filteredAllUsers {
    final q = _searchQuery.toLowerCase();
    return _allUsers.entries
        .where((e) => e.key != widget.username)
        .where((e) => q.isEmpty || e.key.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        // Online first, then alphabetical
        if (a.value == 'Online' && b.value != 'Online') return -1;
        if (b.value == 'Online' && a.value != 'Online') return 1;
        return a.key.compareTo(b.key);
      });
  }

  List<Map<String, dynamic>> get _filteredSaved {
    final q = _searchQuery.toLowerCase();
    final list = _savedContacts
        .where(
          (c) =>
              q.isEmpty ||
              (c['contactName'] as String).toLowerCase().contains(q),
        )
        .toList();
    // Favourites first
    list.sort((a, b) {
      final aFav = _favourites.contains(a['contactName']);
      final bFav = _favourites.contains(b['contactName']);
      if (aFav && !bFav) return -1;
      if (bFav && !aFav) return 1;
      return (a['contactName'] as String).compareTo(b['contactName'] as String);
    });
    return list;
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
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: (widget.isDark ? Colors.black : Colors.white).withValues(
                alpha: 0.25,
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
          'Contacts',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: themeColor),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: themeColor,
          labelColor: themeColor,
          unselectedLabelColor: widget.isDark ? Colors.white38 : Colors.black38,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline_rounded, size: 18),
                  const SizedBox(width: 6),
                  const Text('All'),
                  if (_allUsers.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_allUsers.length - 1}',
                        style: TextStyle(fontSize: 11, color: themeColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bookmark_outline_rounded, size: 18),
                  const SizedBox(width: 6),
                  const Text('Saved'),
                  if (_savedContacts.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_savedContacts.length}',
                        style: TextStyle(fontSize: 11, color: themeColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 110), // AppBar + TabBar height
          // Search bar
          Container(
            margin: const EdgeInsets.fromLTRB(15, 8, 15, 8),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            height: 46,
            decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 14),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.toLowerCase()),
                    style: TextStyle(
                      color: widget.isDark ? Colors.white : Colors.black,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by username...',
                      hintStyle: TextStyle(
                        color: widget.isDark ? Colors.white38 : Colors.black38,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: widget.isDark ? Colors.white38 : Colors.black38,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: themeColor))
                : TabBarView(
                    controller: _tabController,
                    children: [_buildAllUsersTab(), _buildSavedTab()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllUsersTab() {
    final users = _filteredAllUsers;
    final onlineCount = users.where((e) => e.value == 'Online').length;

    if (users.isEmpty) {
      return _buildEmpty(
        icon: Icons.people_outline_rounded,
        title: _searchQuery.isNotEmpty
            ? 'No users found'
            : 'No other users yet',
        subtitle: _searchQuery.isNotEmpty
            ? 'Try a different search'
            : 'When others register, they\'ll appear here',
      );
    }

    return RefreshIndicator(
      color: VeilTheme.accentColor,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 100),
        itemCount: users.length + 1, // +1 for header
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00FF88),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$onlineCount online',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF00FF88),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${users.length} total',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            );
          }
          final entry = users[i - 1];
          return _buildUserTile(
            username: entry.key,
            status: entry.value,
            isSaved: _savedContacts.any((c) => c['contactName'] == entry.key),
          );
        },
      ),
    );
  }

  Widget _buildSavedTab() {
    final saved = _filteredSaved;

    if (saved.isEmpty) {
      return _buildEmpty(
        icon: Icons.bookmark_outline_rounded,
        title: _searchQuery.isNotEmpty
            ? 'No contacts found'
            : 'No saved contacts',
        subtitle: _searchQuery.isNotEmpty
            ? 'Try a different search'
            : 'Tap a user from All tab to start a chat and save them',
      );
    }

    return RefreshIndicator(
      color: VeilTheme.accentColor,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 100),
        itemCount: saved.length,
        itemBuilder: (ctx, i) {
          final contact = saved[i];
          final name = contact['contactName'] as String;
          final status = _allUsers[name] ?? 'Offline';
          return _buildUserTile(
            username: name,
            status: status,
            isSaved: true,
            isFavourite: _favourites.contains(name),
          );
        },
      ),
    );
  }

  Widget _buildUserTile({
    required String username,
    required String status,
    required bool isSaved,
    bool isFavourite = false,
  }) {
    final themeColor = VeilTheme.accentColor;
    final isOnline = status == 'Online';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 20),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: themeColor.withValues(alpha: 0.15),
              child: Text(
                username[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: themeColor,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFF00FF88) : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isDark ? Colors.black : Colors.white,
                    width: 2,
                  ),
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF00FF88,
                            ).withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ]
                      : [],
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text(
              username,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: widget.isDark ? Colors.white : Colors.black,
              ),
            ),
            if (isFavourite) ...[
              const SizedBox(width: 6),
              Icon(Icons.star_rounded, color: Colors.amber, size: 16),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF00FF88) : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 13,
                color: isOnline
                    ? const Color(0xFF00FF88)
                    : (widget.isDark ? Colors.white38 : Colors.black38),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Star / favourite toggle
            IconButton(
              icon: Icon(
                isFavourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavourite
                    ? Colors.amber
                    : (widget.isDark ? Colors.white30 : Colors.black26),
                size: 22,
              ),
              onPressed: () async {
                if (!isSaved) await _saveContact(username);
                await _toggleFavourite(username);
              },
            ),
            // Message button
            Container(
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: themeColor,
                  size: 20,
                ),
                onPressed: () => _openChat(username),
                tooltip: 'Message',
              ),
            ),
          ],
        ),
        onTap: () => _openChat(username),
      ),
    );
  }

  Widget _buildEmpty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final themeColor = VeilTheme.accentColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: themeColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? Colors.white38 : Colors.black38,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

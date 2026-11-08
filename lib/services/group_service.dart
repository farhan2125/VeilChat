import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'network_service.dart';
import 'database_service.dart';

class Group {
  final String id;
  String name;
  final String owner;
  final List<String> members;
  final DateTime createdAt;
  String? avatarPath;
  bool isMuted;
  String? lastMessage;
  int? lastMessageTime;
  int unreadCount;

  /// ✅ Task 3: usernames with admin privileges (the [owner] is always an
  /// implicit admin and is *not* required to be in this list).
  final List<String> admins;

  /// Epoch-ms until which notifications stay muted. `0` = muted indefinitely
  /// (only meaningful when [isMuted] is true).
  int mutedUntil;

  /// Optional per-group chat wallpaper (asset key or file path).
  String? wallpaper;

  /// Currently pinned message text shown in the group header banner.
  String? pinnedMessage;

  Group({
    required this.id,
    required this.name,
    required this.owner,
    required this.members,
    required this.createdAt,
    this.avatarPath,
    this.isMuted = false,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    List<String>? admins,
    this.mutedUntil = 0,
    this.wallpaper,
    this.pinnedMessage,
  }) : admins = admins ?? <String>[];

  /// Everyone who can moderate: owner + explicit admins.
  Set<String> get allAdmins => {owner, ...admins};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'owner': owner,
        'members': members,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'avatarPath': avatarPath,
        'isMuted': isMuted,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'unreadCount': unreadCount,
        'admins': admins,
        'mutedUntil': mutedUntil,
        'wallpaper': wallpaper,
        'pinnedMessage': pinnedMessage,
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        name: json['name'],
        owner: json['owner'],
        members: List<String>.from(json['members']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
        avatarPath: json['avatarPath'],
        isMuted: json['isMuted'] ?? false,
        lastMessage: json['lastMessage'],
        lastMessageTime: json['lastMessageTime'],
        unreadCount: json['unreadCount'] ?? 0,
        admins: json['admins'] == null
            ? <String>[]
            : List<String>.from(json['admins']),
        mutedUntil: json['mutedUntil'] ?? 0,
        wallpaper: json['wallpaper'],
        pinnedMessage: json['pinnedMessage'],
      );

  /// Safely decodes the `admins` column, which is stored as a JSON array.
  static List<String> decodeAdmins(Object? raw) {
    if (raw == null) return <String>[];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return <String>[];
  }
}


class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal() {
    _setupListeners();
  }

  final _groupsController = StreamController<List<Group>>.broadcast();
  final _groupUpdateController = StreamController<Group>.broadcast();
  final _groupMessageController = StreamController<Map<String, dynamic>>.broadcast();

  List<Group> _groups = [];
  StreamSubscription? _messageSub;

  String? _loadedForUser; // guard against repeated loadGroups calls

  Stream<List<Group>> get groupsStream => _groupsController.stream;
  Stream<Group> get groupUpdateStream => _groupUpdateController.stream;
  Stream<Map<String, dynamic>> get groupMessageStream => _groupMessageController.stream;
  List<Group> get groups => List.unmodifiable(_groups);

  Future<void> loadGroups(String currentUser) async {
    // Skip if already loaded for this user (prevents 4x calls on login)
    if (_loadedForUser == currentUser && _groups.isNotEmpty) {
      debugPrint("📂 Groups already loaded for $currentUser, skipping");
      return;
    }
    try {
      final groupMaps = await DatabaseService().getGroups(currentUser);
      _loadedForUser = currentUser;
      debugPrint('📂 Loaded ${groupMaps.length} groups from DB for $currentUser');
      if (groupMaps.isNotEmpty) {
        debugPrint('   Group IDs: ${groupMaps.map((g) => g['id']).toList()}');
      }
      final dbGroups = groupMaps.map((g) => Group(
        id: g['id'],
        name: g['name'],
        owner: g['owner'],
        members: List<String>.from(g['members']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(g['createdAt']),
        avatarPath: g['avatarPath'],
        isMuted: g['isMuted'] == 1,
        lastMessage: g['lastMessage'],
        lastMessageTime: g['lastMessageTime'],
        unreadCount: g['unreadCount'],
        // ✅ hydrate the new admin/mute/wallpaper columns (null-safe)
        admins: Group.decodeAdmins(g['admins']),
        mutedUntil: (g['mutedUntil'] as num?)?.toInt() ?? 0,
        wallpaper: g['wallpaper'] as String?,
        pinnedMessage: g['pinnedMessage'] as String?,
      )).toList();

      final dbMap = {for (var g in dbGroups) g.id: g};

      final merged = <Group>[];

      for (var g in dbGroups) {
        merged.add(g);
      }
      for (var g in _groups) {
        if (!dbMap.containsKey(g.id)) {
          merged.add(g);
        }
      }

      _groups = merged;
      _groupsController.add(_groups);
    } catch (e) {
      debugPrint('❌ Failed to load groups from DB: $e');
    }
  }

  void _setupListeners() {
    _messageSub ??= NetworkService().messageStream.listen(
      _handleNetworkPacket,
      onError: (e) => debugPrint('❌ GroupService packet error: $e'),
    );
    debugPrint('👂 GroupService listener attached');
  }

  void _handleNetworkPacket(Map<String, dynamic> packet) {
    final type = packet['type'];
    debugPrint('📦 GroupService received packet: $type');
    switch (type) {
      case 'GRP_NEW':
        _handleGroupCreated(packet);
        break;
      case 'GRP_INV':
        _handleGroupInvite(packet);
        break;
      case 'GROUP_MEMBER_ADDED':
      case 'GRP_ADD_MEMBER':
        _handleMemberAdded(packet);
        break;
      case 'GROUP_MEMBER_REMOVED':
      case 'GRP_REMOVE_MEMBER':
        _handleMemberRemoved(packet);
        break;
      case 'GRP_MSG':
        _handleGroupMessage(packet);
        break;
      case 'GROUP_UPDATED':
        _handleGroupUpdated(packet);
        break;
      case 'GROUP_DELETED':
        _handleGroupDeleted(packet);
        break;
    }
  }

  void _handleGroupInvite(Map<String, dynamic> data) async {
    debugPrint('📩 GRP_INV received: $data');
    try {
      final group = Group(
        id: data['groupId'],
        name: data['name'],
        owner: data['owner'],
        members: List<String>.from(data['members'] ?? [data['owner']]),
        createdAt: DateTime.now(),
      );
      _groups.add(group);
      _groupsController.add(_groups);
      _groupUpdateController.add(group);
      debugPrint('✅ Group invite accepted: ${group.name} (ID: ${group.id})');
      await DatabaseService().saveGroup(
        accountOwner: NetworkService().currentUser!,
        id: group.id,
        name: group.name,
        owner: group.owner,
        members: group.members,
        createdAt: group.createdAt,
      );
      debugPrint('✅ Group saved to DB: ${group.id}');
    } catch (e) {
      debugPrint('❌ Error handling GRP_INV: $e');
    }
  }

  Future<bool> createGroup({
    required String groupName,
    required List<String> members,
    String? avatarPath,
  }) async {
    try {
      final currentUser = NetworkService().currentUser;
      if (currentUser == null) return false;

      final allMembers = [...members];
      if (!allMembers.contains(currentUser)) allMembers.add(currentUser);

      NetworkService().sendPacket('NEW_GROUP', {
        'name': groupName,
        'members': allMembers,
        'avatarPath': avatarPath,
        'sender': currentUser,
      });

      return true;
    } catch (e) {
      debugPrint('❌ Create group error: $e');
      return false;
    }
  }

  void _handleGroupCreated(Map<String, dynamic> data) async {
    try {
      final group = Group(
        id: data['groupId'],
        name: data['name'],
        owner: data['owner'],
        members: List<String>.from(data['members']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(data['timestamp']),
      );
      _groups.add(group);
      _groupsController.add(_groups);
      _groupUpdateController.add(group);
      debugPrint('✅ Group created: ${group.name} (${group.id})');
      await DatabaseService().saveGroup(
        accountOwner: NetworkService().currentUser!,
        id: group.id,
        name: group.name,
        owner: group.owner,
        members: group.members,
        createdAt: group.createdAt,
      );
      debugPrint('✅ Group saved to DB: ${group.id}');
      await loadGroups(NetworkService().currentUser!);
    } catch (e) {
      debugPrint('❌ Handle GRP_NEW error: $e');
    }
  }

  void _handleMemberAdded(Map<String, dynamic> data) {
    final groupId = data['groupId'];
    final newMember = data['member'] ?? data['username'];
    if (newMember == null) return;
    try {
      final group = _groups.firstWhere((g) => g.id == groupId);
      if (!group.members.contains(newMember)) {
        group.members.add(newMember);
        _groupUpdateController.add(group);
        _groupsController.add(_groups);
        DatabaseService().updateGroup(
          accountOwner: NetworkService().currentUser!,
          id: groupId,
          name: group.name,
          avatarPath: group.avatarPath,
          isMuted: group.isMuted,
          lastMessage: group.lastMessage,
          lastMessageTime: group.lastMessageTime,
          unreadCount: group.unreadCount,
        ).catchError((e) {
          debugPrint('❌ Failed to update group after member added: $e');
        });
      }
    } catch (e) {
      debugPrint('⚠️ Member added for unknown group $groupId');
    }
  }

  void _handleMemberRemoved(Map<String, dynamic> data) {
    final groupId = data['groupId'];
    final removedMember = data['member'] ?? data['username'];
    if (removedMember == null) return;
    final currentUser = NetworkService().currentUser;
    try {
      final group = _groups.firstWhere((g) => g.id == groupId);
      group.members.remove(removedMember);
      _groupUpdateController.add(group);
      _groupsController.add(_groups);
      DatabaseService().updateGroup(
        accountOwner: NetworkService().currentUser!,
        id: groupId,
        name: group.name,
        avatarPath: group.avatarPath,
        isMuted: group.isMuted,
        lastMessage: group.lastMessage,
        lastMessageTime: group.lastMessageTime,
        unreadCount: group.unreadCount,
      ).catchError((e) {
        debugPrint('❌ Failed to update group after member removed: $e');
      });
      if (removedMember == currentUser) {
        _groups.remove(group);
        _groupsController.add(_groups);
        DatabaseService().deleteGroup(NetworkService().currentUser!, groupId).catchError((e) {
          debugPrint('❌ Failed to delete group after leaving: $e');
        });
      }
    } catch (e) {
      debugPrint('⚠️ Member removed for unknown group $groupId');
    }
  }

  // ────────────────────────────────────────────────────────────
  //  GROUP ADMIN CONTROLS (Task 3)
  //
  //  All four actions below were previously either missing or
  //  "fire-and-forget" packets whose result never reached the UI. They now:
  //    1. mutate the local model **optimistically**,
  //    2. push the change through `_groupUpdateController` +
  //       `_groupsController` so every listening widget rebuilds instantly,
  //    3. persist to SQLite, and
  //    4. return a bool so the caller can show a success/error SnackBar.
  // ────────────────────────────────────────────────────────────

  /// Persists the current member/admin state of [group] to SQLite.
  Future<void> _persist(Group group) async {
    final owner = NetworkService().currentUser;
    if (owner == null) return;
    try {
      await DatabaseService().saveGroup(
        accountOwner: owner,
        id: group.id,
        name: group.name,
        owner: group.owner,
        members: group.members,
        createdAt: group.createdAt,
        avatarPath: group.avatarPath,
        isMuted: group.isMuted,
        lastMessage: group.lastMessage,
        lastMessageTime: group.lastMessageTime,
        unreadCount: group.unreadCount,
      );
    } catch (e) {
      debugPrint('❌ _persist(${group.id}) failed: $e');
    }
  }

  /// Broadcasts [group] to all listeners (member list, header, chat list).
  void _emit(Group group) {
    if (!_groupUpdateController.isClosed) _groupUpdateController.add(group);
    if (!_groupsController.isClosed) _groupsController.add(_groups);
  }

  /// True when [username] can perform admin actions in [group].
  bool isAdmin(Group group, String username) =>
      group.owner == username || group.admins.contains(username);

  /// Adds [username] to [groupId]. Reflects immediately in the UI.
  Future<bool> addMember(String groupId, String username) async {
    final group = getGroup(groupId);
    final me = NetworkService().currentUser;
    if (group == null || me == null) return false;
    if (!isAdmin(group, me)) {
      debugPrint('⛔ addMember denied: $me is not an admin of $groupId');
      return false;
    }
    if (group.members.contains(username)) return false;

    group.members.add(username);
    _emit(group); // ✅ instant UI update
    await _persist(group);

    try {
      NetworkService().sendPacket('GRP_ADD_MEMBER', {
        'groupId': groupId,
        'member': username,
        'sender': me,
      });
      return true;
    } catch (e) {
      // Roll back the optimistic mutation on transport failure.
      group.members.remove(username);
      _emit(group);
      await _persist(group);
      debugPrint('❌ addMember failed: $e');
      return false;
    }
  }

  /// Kicks [username] out of [groupId].
  Future<bool> removeMember(String groupId, String username) async {
    final group = getGroup(groupId);
    final me = NetworkService().currentUser;
    if (group == null || me == null) return false;
    if (!isAdmin(group, me)) {
      debugPrint('⛔ removeMember denied: $me is not an admin of $groupId');
      return false;
    }
    if (username == group.owner) {
      debugPrint('⛔ The group owner cannot be removed');
      return false;
    }

    final index = group.members.indexOf(username);
    if (index < 0) return false;

    group.members.removeAt(index);
    final wasAdmin = group.admins.remove(username);
    _emit(group); // ✅ member disappears from the list immediately
    await _persist(group);

    try {
      NetworkService().sendPacket('GRP_REMOVE_MEMBER', {
        'groupId': groupId,
        'member': username,
        'sender': me,
      });
      return true;
    } catch (e) {
      group.members.insert(index, username);
      if (wasAdmin) group.admins.add(username);
      _emit(group);
      await _persist(group);
      debugPrint('❌ removeMember failed: $e');
      return false;
    }
  }

  /// Promotes [username] to admin.
  Future<bool> promoteToAdmin(String groupId, String username) async {
    final group = getGroup(groupId);
    final me = NetworkService().currentUser;
    if (group == null || me == null) return false;
    if (!isAdmin(group, me)) return false;
    if (!group.members.contains(username)) return false;
    if (group.admins.contains(username) || username == group.owner) return false;

    group.admins.add(username);
    _emit(group);
    await _persist(group);

    try {
      NetworkService().sendPacket('GRP_SET_ADMIN', {
        'groupId': groupId,
        'member': username,
        'admin': true,
        'sender': me,
      });
      return true;
    } catch (e) {
      group.admins.remove(username);
      _emit(group);
      debugPrint('❌ promoteToAdmin failed: $e');
      return false;
    }
  }

  /// Demotes [username] back to a regular member.
  Future<bool> demoteAdmin(String groupId, String username) async {
    final group = getGroup(groupId);
    final me = NetworkService().currentUser;
    if (group == null || me == null) return false;
    // Only the owner may demote another admin.
    if (group.owner != me) return false;
    if (username == group.owner) return false;
    if (!group.admins.remove(username)) return false;

    _emit(group);
    await _persist(group);

    try {
      NetworkService().sendPacket('GRP_SET_ADMIN', {
        'groupId': groupId,
        'member': username,
        'admin': false,
        'sender': me,
      });
      return true;
    } catch (e) {
      group.admins.add(username);
      _emit(group);
      debugPrint('❌ demoteAdmin failed: $e');
      return false;
    }
  }

  /// Mutes/unmutes group notifications until [until] (null = unmute).
  Future<bool> setMuted(String groupId, DateTime? until) async {
    final group = getGroup(groupId);
    if (group == null) return false;
    group.isMuted = until != null;
    group.mutedUntil = until?.millisecondsSinceEpoch ?? 0;
    _emit(group);
    await _persist(group);
    return true;
  }

  /// True when the group is currently muted (auto-expires).
  bool isMutedNow(Group group) {
    if (!group.isMuted) return false;
    if (group.mutedUntil == 0) return true; // muted forever
    if (DateTime.now().millisecondsSinceEpoch >= group.mutedUntil) {
      group.isMuted = false;
      group.mutedUntil = 0;
      return false;
    }
    return true;
  }

  /// Leaves [groupId]. Removes the group locally straight away so the user is
  /// never left staring at a chat they no longer belong to.
  Future<bool> leaveGroup(String groupId) async {
    final me = NetworkService().currentUser;
    if (me == null) return false;
    final group = getGroup(groupId);

    try {
      NetworkService().sendPacket('GROUP_LEAVE', {
        'groupId': groupId,
        'sender': me,
      });
    } catch (e) {
      debugPrint('❌ leaveGroup packet failed: $e');
      return false;
    }

    if (group != null) {
      _groups.remove(group);
      if (!_groupsController.isClosed) _groupsController.add(_groups);
      try {
        await DatabaseService().deleteGroup(me, groupId);
        await DatabaseService().deleteGroupMessages(groupId);
      } catch (e) {
        debugPrint('❌ leaveGroup cleanup failed: $e');
      }
    }
    return true;
  }

  void _handleGroupDeleted(Map<String, dynamic> data) {
    final groupId = data['groupId'];
    _groups.removeWhere((g) => g.id == groupId);
    _groupsController.add(_groups);
    DatabaseService().deleteGroup(NetworkService().currentUser!, groupId).catchError((e) {
      debugPrint('❌ Failed to delete group after deletion: $e');
    });
  }

  void _handleGroupUpdated(Map<String, dynamic> data) {
    final groupId = data['groupId'];
    try {
      final group = _groups.firstWhere((g) => g.id == groupId);
      if (data.containsKey('name')) group.name = data['name'];
      if (data.containsKey('avatarPath')) group.avatarPath = data['avatarPath'];
      if (data.containsKey('isMuted')) group.isMuted = data['isMuted'];
      _groupUpdateController.add(group);
      _groupsController.add(_groups);
      DatabaseService().updateGroup(
        accountOwner: NetworkService().currentUser!,
        id: groupId,
        name: group.name,
        avatarPath: group.avatarPath,
        isMuted: group.isMuted,
        lastMessage: group.lastMessage,
        lastMessageTime: group.lastMessageTime,
        unreadCount: group.unreadCount,
      ).catchError((e) {
        debugPrint('❌ Failed to update group after update: $e');
      });
    } catch (e) {
      debugPrint('⚠️ Group update for unknown group $groupId');
    }
  }

  Future<String> _saveGroupMediaToFile(String rawData, String type, String sender) async {
    try {
      if (rawData.startsWith('/')) return rawData; 
      
      final dir = await getApplicationDocumentsDirectory();
      final subDir = Directory('${dir.path}/veil_chat_files');
      if (!await subDir.exists()) await subDir.create(recursive: true);

      String ext = type == 'IMAGE' ? '.jpg' : type == 'AUDIO' ? '.m4a' : '.dat';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${subDir.path}/group_${type.toLowerCase()}_${sender}_$timestamp$ext');

      final cleanData = rawData.replaceAll(RegExp(r'\s'), '');
      
      final isHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanData) && cleanData.length % 2 == 0;
      
      if (isHex) {
        await file.writeAsString(rawData); 
      } else {
        try {
          final bytes = base64Decode(cleanData);
          await file.writeAsBytes(bytes);
        } catch (e) {
          debugPrint('❌ Base64 decode failed, falling back to text: $e');
          await file.writeAsString(rawData); 
        }
      }
      return file.path;
    } catch (e) {
      debugPrint("❌ Failed to save group media: $e");
      return 'ERROR_MEDIA_SAVE_FAILED';
    }
  }

  Future<void> sendMessage({
    required String groupId,
    required String type,
    required String content,
    String? extra,
    Map<String, dynamic>? metadata,
    String? messageId,
  }) async {
    final currentUser = NetworkService().currentUser;
    if (currentUser == null) return;
    
    final msgId = messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    String savedContent = content;
    if (type == 'IMAGE' || type == 'AUDIO' || type == 'FILE') {
      savedContent = await _saveGroupMediaToFile(content, type, currentUser);
    }

    NetworkService().sendPacket('GRP_MSG', {
      'groupId': groupId,
      'type': type,
      'content': content, 
      'extra': extra,
      'metadata': metadata,
      'messageId': msgId,
      'sender': currentUser,
      'timestamp': timestamp,
    });

    await DatabaseService().saveGroupMessage(
      accountOwner: currentUser,
      groupId: groupId,
      sender: currentUser,
      type: type,
      content: savedContent, 
      isMe: true,
      messageId: msgId,
      timestamp: timestamp,
      isHidden: metadata?['isHidden'] ?? 0,
      hiddenKey: metadata?['hiddenKey'],
      metadata: metadata,
    );

    await DatabaseService().updateGroup(
      accountOwner: currentUser,
      id: groupId,
      lastMessage: _previewText(type, savedContent),
      lastMessageTime: timestamp,
    );

    _groupMessageController.add({
      'type': 'LOCAL_UPDATE',
      'groupId': groupId,
      'sender': currentUser,
    });
  }

  Future<void> _handleGroupMessage(Map<String, dynamic> data) async {
    final groupId = data['groupId'];
    final sender = data['sender'];
    final type = data['type'];
    String content = data['content'];
    final timestamp = data['timestamp'];

    if (type == 'IMAGE' || type == 'AUDIO' || type == 'FILE') {
      try {
        content = await _saveGroupMediaToFile(content, type, sender);
      } catch (e) {
        debugPrint('❌ Failed to save group media in handler: $e');
        content = 'ERROR_MEDIA_SAVE_FAILED';
      }
    }

    Group? group;
    try {
      group = _groups.firstWhere((g) => g.id == groupId);
      group.lastMessage = _previewText(type, content);
      group.lastMessageTime = timestamp;

      final currentUser = NetworkService().currentUser;
      if (sender != currentUser) {
        group.unreadCount += 1;
      }

      _groupUpdateController.add(group);
      _groupsController.add(_groups);
    } catch (e) {
      debugPrint('⚠️ Group message for unknown group $groupId - reloading groups...');
      // Group list may not be loaded yet - reload from DB
      final user = NetworkService().currentUser;
      if (user != null) await loadGroups(user);
    }

    final displayData = Map<String, dynamic>.from(data);
    displayData['content'] = content;
    _groupMessageController.add(displayData);

    final currentUser = NetworkService().currentUser;
    if (currentUser != null) {
      if (group != null) {
        await DatabaseService().saveGroup(
          accountOwner: currentUser,
          id: group.id,
          name: group.name,
          owner: group.owner,
          members: group.members,
          createdAt: group.createdAt,
        );
        await DatabaseService().saveGroupMessage(
          accountOwner: currentUser,
          groupId: groupId,
          sender: sender,
          type: type,
          content: content,
          isMe: sender == currentUser,
          messageId: data['messageId'],
          timestamp: timestamp,
          isHidden: data['isHidden'] ?? 0,
          hiddenKey: data['hiddenKey'],
          metadata: data['metadata'] is Map
              ? Map<String, dynamic>.from(data['metadata'])
              : null,
        );
        await DatabaseService().updateGroup(
          accountOwner: currentUser,
          id: groupId,
          lastMessage: (type == 'TEXT') ? content : '📁 Media',
          lastMessageTime: timestamp,
          unreadCount: group.unreadCount,

        );
      } else {
        await DatabaseService().saveGroupMessage(
          accountOwner: currentUser,
          groupId: groupId,
          sender: sender,
          type: type,
          content: content,
          isMe: sender == currentUser,
          messageId: data['messageId'],
          timestamp: timestamp,
          isHidden: data['isHidden'] ?? 0,
          hiddenKey: data['hiddenKey'],
          metadata: data['metadata'] is Map
              ? Map<String, dynamic>.from(data['metadata'])
              : null,
        );
      }
    }
  }

  void markGroupAsRead(String groupId) {
    try {
      final group = _groups.firstWhere((g) => g.id == groupId);
      group.unreadCount = 0;
      _groupUpdateController.add(group);
      _groupsController.add(_groups);
      DatabaseService().markGroupAsRead(NetworkService().currentUser!, groupId).catchError((e) {
        debugPrint('❌ Failed to mark group as read: $e');
      });
    } catch (e) {
      debugPrint('⚠️ Mark read for unknown group $groupId');
    }
  }

  Group? getGroup(String id) {
    try {
      return _groups.firstWhere((g) => g.id == id);
    } catch (e) {
      return null;
    }
  }

  void refreshGroups() {
    NetworkService().sendPacket('GET_GRPS', {
      'sender': NetworkService().currentUser,
    });
  }

  void resetForLogout() {
    _loadedForUser = null;
    _groups.clear();
  }

  void dispose() {
    _messageSub?.cancel();
    _groupsController.close();
    _groupUpdateController.close();
    _groupMessageController.close();
    _groups.clear();
  }
  String _previewText(String type, String content) {
    if (type == 'IMAGE') return '📷 Photo';
    if (type == 'AUDIO') return '🎤 Voice message';
    if (type == 'FILE')  return '📁 File';
    // Never show encrypted hex, file paths, or .enc content
    if (content.startsWith('/') || content.contains('.enc')) return '💬 Message';
    if (content.length > 30 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(content.trim())) return '💬 Message';
    return content;
  }

}
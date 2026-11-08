import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat / group pinning ("move to top of the list").
///
/// ✅ FIX: VeilChat only had **message** pinning (`messages.isPinned`). There
/// was no way to pin a *conversation*, and the chat list sorted purely by
/// `lastTime`, so nothing could ever stay at the top.
///
/// Pins live in SharedPreferences (not SQLite) so they survive a database
/// migration and are restored instantly on cold start without waiting for the
/// DB to open.
class PinService {
  static final PinService _instance = PinService._internal();
  factory PinService() => _instance;
  PinService._internal();

  static const String _chatKey = 'pinned_chats';
  static const String _groupKey = 'pinned_groups';

  /// In-memory mirror so `isPinned()` is synchronous during list building.
  final Set<String> _chats = <String>{};
  final Set<String> _groups = <String>{};
  bool _loaded = false;

  Set<String> get pinnedChats => Set.unmodifiable(_chats);
  Set<String> get pinnedGroups => Set.unmodifiable(_groups);

  /// Loads pins from disk. Safe to call repeatedly — only reads once.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _chats
        ..clear()
        ..addAll(prefs.getStringList(_chatKey) ?? const <String>[]);
      _groups
        ..clear()
        ..addAll(prefs.getStringList(_groupKey) ?? const <String>[]);
      _loaded = true;
    } catch (e) {
      debugPrint('⚠️ PinService.load failed: $e');
      _loaded = true; // don't spin forever on a broken prefs store
    }
  }

  bool isChatPinned(String contact) => _chats.contains(contact);
  bool isGroupPinned(String groupId) => _groups.contains(groupId);

  /// Toggles the pin for [contact]. Returns the new pinned state.
  Future<bool> toggleChat(String contact) async {
    final nowPinned = !_chats.contains(contact);
    nowPinned ? _chats.add(contact) : _chats.remove(contact);
    await _persist(_chatKey, _chats);
    return nowPinned;
  }

  /// Toggles the pin for [groupId]. Returns the new pinned state.
  Future<bool> toggleGroup(String groupId) async {
    final nowPinned = !_groups.contains(groupId);
    nowPinned ? _groups.add(groupId) : _groups.remove(groupId);
    await _persist(_groupKey, _groups);
    return nowPinned;
  }

  /// Sorts [items] so pinned entries float to the top while preserving the
  /// existing recency order inside each bucket.
  ///
  /// [idOf] extracts the key to test, [timeOf] the recency value (desc).
  static void sortPinnedFirst<T>(
    List<T> items, {
    required String Function(T) idOf,
    required int Function(T) timeOf,
    required bool Function(String) isPinned,
  }) {
    items.sort((a, b) {
      final pa = isPinned(idOf(a));
      final pb = isPinned(idOf(b));
      if (pa != pb) return pa ? -1 : 1;
      return timeOf(b).compareTo(timeOf(a));
    });
  }

  Future<void> _persist(String key, Set<String> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, values.toList());
    } catch (e) {
      debugPrint('⚠️ PinService persist failed: $e');
    }
  }
}

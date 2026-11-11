import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists chat wallpapers so they survive navigation AND app restarts.
///
/// Why this exists:
///  - `image_picker` returns a path inside the app *cache* directory, which
///    Android is free to purge at any time. Storing that raw path means the
///    wallpaper silently disappears after a restart.
///  - The previous implementation kept the path only in a static field
///    (`VeilTheme.chatBgPath`), which is lost the moment the process dies and
///    leaks between contacts while the app is alive.
///
/// This service copies the picked image into permanent app storage and records
/// the stable path in SharedPreferences, keyed per contact.
class WallpaperService {
  static final WallpaperService _instance = WallpaperService._internal();
  factory WallpaperService() => _instance;
  WallpaperService._internal();

  static const String _keyPrefix = 'chat_wallpaper_';
  static const String _groupKeyPrefix = 'group_wallpaper_';
  static const String _globalKey = 'global_wallpaper_path';
  static const String _wallpaperDirName = 'wallpapers';

  String _prefKey(String contact) => '$_keyPrefix$contact';

  /// Namespaced key so a group id can never collide with a contact name.
  String groupKey(String groupId) => '$_groupKeyPrefix$groupId';

  /// Returns the saved wallpaper path for [contact], or null when there is
  /// none / the underlying file no longer exists.
  ///
  /// If the stored file has been deleted the stale key is cleaned up so we do
  /// not keep re-checking a dead path on every chat open.
  Future<String?> getChatWallpaper(String contact) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_prefKey(contact));
      if (path == null || path.isEmpty) return null;

      // Bundled asset wallpapers are always valid — no file check needed.
      if (isAssetPath(path)) return path;

      if (await File(path).exists()) return path;

      // Self-heal: the file vanished (cache purge / user deleted it).
      await prefs.remove(_prefKey(contact));
      return null;
    } catch (e) {
      debugPrint('⚠️ getChatWallpaper failed: $e');
      return null;
    }
  }

  /// Copies [sourcePath] into permanent storage and persists it for [contact].
  ///
  /// Returns the new stable path, or null if the copy failed.
  Future<String?> setChatWallpaperFromFile(
    String contact,
    String sourcePath,
  ) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        debugPrint('⚠️ Wallpaper source missing: $sourcePath');
        return null;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${docsDir.path}/$_wallpaperDirName');
      if (!await wallpaperDir.exists()) {
        await wallpaperDir.create(recursive: true);
      }

      // Remove the previous wallpaper file for this contact so we don't leak
      // storage every time the user changes it.
      await _deleteExistingFile(contact);

      final ext = _extensionOf(sourcePath);
      final safeContact = contact.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = '${wallpaperDir.path}/${safeContact}_$timestamp$ext';

      await source.copy(destPath);
      await _persist(contact, destPath);

      debugPrint('✅ Wallpaper stored at $destPath');
      return destPath;
    } catch (e) {
      debugPrint('❌ setChatWallpaperFromFile failed: $e');
      return null;
    }
  }

  /// Persists a bundled asset path (e.g. `assets/images/chat_dark.jpg`).
  Future<bool> setChatWallpaperAsset(String contact, String assetPath) async {
    try {
      await _deleteExistingFile(contact);
      await _persist(contact, assetPath);
      return true;
    } catch (e) {
      debugPrint('❌ setChatWallpaperAsset failed: $e');
      return false;
    }
  }

  /// Removes the wallpaper for [contact] and deletes the stored copy.
  Future<void> clearChatWallpaper(String contact) async {
    try {
      await _deleteExistingFile(contact);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey(contact));
    } catch (e) {
      debugPrint('⚠️ clearChatWallpaper failed: $e');
    }
  }

  // ── group wallpapers ───────────────────────────────────────────────────
  //
  // Groups reuse the exact same copy-to-documents strategy as 1:1 chats; the
  // only difference is the SharedPreferences namespace. This means a group
  // wallpaper survives restarts, reinstall-with-backup and cache purges just
  // like a contact wallpaper does.

  Future<String?> getGroupWallpaper(String groupId) =>
      getChatWallpaper(groupKey(groupId));

  Future<String?> setGroupWallpaperFromFile(
    String groupId,
    String sourcePath,
  ) => setChatWallpaperFromFile(groupKey(groupId), sourcePath);

  Future<bool> setGroupWallpaperAsset(String groupId, String assetPath) =>
      setChatWallpaperAsset(groupKey(groupId), assetPath);

  Future<void> clearGroupWallpaper(String groupId) =>
      clearChatWallpaper(groupKey(groupId));

  // ── global (app-wide) wallpaper ────────────────────────────────────────
  //
  // ✅ FIX: Settings previously stored the raw `image_picker` cache path in a
  // static field only, so the custom background silently vanished on restart
  // or re-login. It now goes through the same permanent-storage pipeline.

  Future<String?> getGlobalWallpaper() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_globalKey);
      if (path == null || path.isEmpty) return null;
      if (isAssetPath(path)) return path;
      if (await File(path).exists()) return path;
      await prefs.remove(_globalKey);
      return null;
    } catch (e) {
      debugPrint('⚠️ getGlobalWallpaper failed: $e');
      return null;
    }
  }

  Future<String?> setGlobalWallpaperFromFile(String sourcePath) async {
    final saved = await setChatWallpaperFromFile('__global__', sourcePath);
    if (saved == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalKey, saved);
    return saved;
  }

  Future<void> clearGlobalWallpaper() async {
    await clearChatWallpaper('__global__');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_globalKey);
  }

  /// True when [path] points at a bundled Flutter asset rather than a file.
  static bool isAssetPath(String path) => path.startsWith('assets/');

  // ── internals ──────────────────────────────────────────────────────────

  Future<void> _persist(String contact, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(contact), path);
  }

  Future<void> _deleteExistingFile(String contact) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getString(_prefKey(contact));
      if (old == null || old.isEmpty || isAssetPath(old)) return;
      final oldFile = File(old);
      if (await oldFile.exists()) await oldFile.delete();
    } catch (_) {
      // Non-fatal — worst case we leave one orphaned file behind.
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot < path.length - 6) return '.jpg';
    return path.substring(dot).toLowerCase();
  }
}

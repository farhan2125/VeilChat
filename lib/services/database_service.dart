import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

/// Local SQLite database service for VeilChat.
/// Version 8: Composite primary key for groups (id + accountOwner) to prevent
///            data overwrites when multiple users share the same device.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _db;
  static bool _initialized = false;

  static const int _version = 9;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    _initialized = true;
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'veilchat_v$_version.db');
    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
      onOpen: _onOpen,
    );
  }

  /// Returns the set of column names currently present on [table].
  /// Returns an empty set when the table does not exist.
  Future<Set<String>> _columnsOf(Database db, String table) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      return rows
          .map((r) => (r['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Called every time the database is opened.
  ///
  /// ✅ LOG FIX: the previous implementation fired ~12 unconditional
  /// `ALTER TABLE` statements on **every** app launch and relied on the thrown
  /// exception to detect "already exists". That produced the wall of
  /// `E/SQLiteLog (1) duplicate column name: …` errors in logcat and burned
  /// main-isolate time during first frame.
  ///
  /// We now introspect the schema once per table with `PRAGMA table_info` and
  /// only issue the ALTERs that are genuinely missing — zero errors, zero
  /// wasted statements.
  Future<void> _onOpen(Database db) async {
    // table -> { column : definition }
    const required = <String, Map<String, String>>{
      'messages': {
        'isHidden': 'INTEGER DEFAULT 0',
        'hiddenKey': 'TEXT',
        'isPinned': 'INTEGER DEFAULT 0',
        'pinnedAt': 'INTEGER',
        'reaction': 'TEXT',
        'extra': 'TEXT',
        'metadata': 'TEXT',
        'status': 'TEXT DEFAULT "sent"',
        'read': 'INTEGER DEFAULT 0',
        'delivered': 'INTEGER DEFAULT 0',
        'messageId': 'TEXT',
      },
      'group_messages': {
        'metadata': 'TEXT',
        'isHidden': 'INTEGER DEFAULT 0',
        'hiddenKey': 'TEXT',
      },
      // Group admin roles (Task 3): persisted as a JSON string array.
      'groups': {
        'admins': 'TEXT',
        'mutedUntil': 'INTEGER DEFAULT 0',
        'wallpaper': 'TEXT',
        'pinnedMessage': 'TEXT',
      },
    };

    int added = 0;
    for (final entry in required.entries) {
      final table = entry.key;
      final existing = await _columnsOf(db, table);
      if (existing.isEmpty) continue; // table not present in this schema

      for (final col in entry.value.entries) {
        if (existing.contains(col.key)) continue;
        try {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN ${col.key} ${col.value}',
          );
          added++;
        } catch (e) {
          // Genuinely unexpected — surface it rather than swallowing blindly.
          debugPrint('⚠️ DB migrate $table.${col.key} failed: $e');
        }
      }
    }

    debugPrint(
      added == 0
          ? '✅ DB onOpen: schema up to date (no migrations needed)'
          : '✅ DB onOpen: applied $added column migration(s)',
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    // await db.execute('PRAGMA journal_mode = WAL');
    // await db.execute('PRAGMA synchronous = NORMAL');
  }

  // ------------------------------------------------------------------------
  //                           CREATE TABLES (v8)
  // ------------------------------------------------------------------------
  Future<void> _onCreate(Database db, int version) async {
    // ----- Messages (1:1) -----
    await db.execute('''
      CREATE TABLE messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountOwner TEXT NOT NULL,
        contact TEXT NOT NULL,
        sender TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        isMe INTEGER NOT NULL,
        reaction TEXT,
        extra TEXT,
        metadata TEXT,
        status TEXT DEFAULT 'sent',
        read INTEGER DEFAULT 0,
        delivered INTEGER DEFAULT 0,
        messageId TEXT,
        isPinned INTEGER DEFAULT 0,
        pinnedAt INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_account_contact ON messages(accountOwner, contact)');
    await db.execute('CREATE INDEX idx_timestamp ON messages(timestamp)');
    await db.execute('CREATE INDEX idx_sender ON messages(sender)');
    await db.execute('CREATE INDEX idx_messageId ON messages(messageId)');

    // ----- Contacts -----
    await db.execute('''
      CREATE TABLE contacts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountOwner TEXT NOT NULL,
        contactName TEXT NOT NULL,
        publicKey TEXT,
        lastSeen INTEGER,
        isBlocked INTEGER DEFAULT 0,
        isFavorite INTEGER DEFAULT 0,
        chatBackground TEXT,
        notificationSettings TEXT,
        fcmToken TEXT,
        UNIQUE(accountOwner, contactName)
      )
    ''');

    // ----- Call Logs -----
    await db.execute('''
      CREATE TABLE call_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountOwner TEXT NOT NULL,
        contact TEXT NOT NULL,
        callType TEXT NOT NULL,
        direction TEXT NOT NULL,
        startTime INTEGER NOT NULL,
        endTime INTEGER,
        duration INTEGER,
        status TEXT NOT NULL,
        notes TEXT
      )
    ''');

    // ----- File Cache -----
    await db.execute('''
      CREATE TABLE file_cache(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filePath TEXT NOT NULL UNIQUE,
        messageId INTEGER,
        contact TEXT,
        fileType TEXT,
        size INTEGER,
        downloadedAt INTEGER,
        accessedAt INTEGER,
        FOREIGN KEY(messageId) REFERENCES messages(id) ON DELETE SET NULL
      )
    ''');

    // ----- GROUPS (v8: composite PK) -----
    await db.execute('''
      CREATE TABLE groups(
        id TEXT NOT NULL,
        accountOwner TEXT NOT NULL,
        name TEXT NOT NULL,
        owner TEXT NOT NULL,
        members TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        avatarPath TEXT,
        isMuted INTEGER DEFAULT 0,
        lastMessage TEXT,
        lastMessageTime INTEGER,
        unreadCount INTEGER DEFAULT 0,
        PRIMARY KEY (id, accountOwner)
      )
    ''');
    await db.execute('CREATE INDEX idx_groups_account ON groups(accountOwner)');

    // ----- GROUP MESSAGES (v8: with accountOwner) -----
    await db.execute('''
      CREATE TABLE group_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        groupId TEXT NOT NULL,
        accountOwner TEXT NOT NULL,
        sender TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        isMe INTEGER NOT NULL,
        status TEXT DEFAULT 'sent',
        read INTEGER DEFAULT 0,
        delivered INTEGER DEFAULT 0,
        messageId TEXT,
        isHidden INTEGER DEFAULT 0,
        hiddenKey TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_group_messages_group ON group_messages(groupId, accountOwner)');
    await db.execute('CREATE INDEX idx_group_messages_timestamp ON group_messages(timestamp)');

    // ----- USER PROFILE (v7) -----
    await db.execute('''
      CREATE TABLE user_profile(
        accountOwner TEXT PRIMARY KEY,
        displayName TEXT,
        status TEXT,
        avatarPath TEXT,
        bio TEXT,
        phoneNumber TEXT,
        email TEXT,
        customJson TEXT,
        updatedAt INTEGER
      )
    ''');
  }

  // ------------------------------------------------------------------------
  //                           UPGRADE PATHS
  // ------------------------------------------------------------------------
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: reaction, extra
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN reaction TEXT');
        await db.execute('ALTER TABLE messages ADD COLUMN extra TEXT');
      } catch (e) {
        debugPrint('Upgrade v2: columns may already exist');
      }
    }
    // v2 → v3: metadata, status, read
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN metadata TEXT');
        await db.execute('ALTER TABLE messages ADD COLUMN status TEXT DEFAULT "sent"');
        await db.execute('ALTER TABLE messages ADD COLUMN read INTEGER DEFAULT 0');
      } catch (e) {
        debugPrint('Upgrade v3: columns may already exist');
      }
    }
    // v3 → v4: delivered, messageId, index
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN delivered INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE messages ADD COLUMN messageId TEXT');
        await db.execute('CREATE INDEX idx_messageId ON messages(messageId)');
      } catch (e) {
        debugPrint('Upgrade v4: columns/index may already exist');
      }
    }
    // v4 → v5: groups and group_messages (base tables)
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE groups(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            owner TEXT NOT NULL,
            members TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            avatarPath TEXT,
            isMuted INTEGER DEFAULT 0,
            lastMessage TEXT,
            lastMessageTime INTEGER,
            unreadCount INTEGER DEFAULT 0,
            accountOwner TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_groups_account ON groups(accountOwner)');
        await db.execute('''
          CREATE TABLE group_messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            groupId TEXT NOT NULL,
            sender TEXT NOT NULL,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            isMe INTEGER NOT NULL,
            status TEXT DEFAULT 'sent',
            read INTEGER DEFAULT 0,
            delivered INTEGER DEFAULT 0,
            messageId TEXT,
            FOREIGN KEY(groupId) REFERENCES groups(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_group_messages_group ON group_messages(groupId)');
        await db.execute('CREATE INDEX idx_group_messages_timestamp ON group_messages(timestamp)');
      } catch (e) {
        debugPrint('Upgrade v5: error creating group tables – $e');
      }
    }
    // v5 → v6: add steganography columns to group_messages
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE group_messages ADD COLUMN isHidden INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE group_messages ADD COLUMN hiddenKey TEXT');
        debugPrint('Upgrade v6: added steganography columns');
      } catch (e) {
        debugPrint('Upgrade v6: columns may already exist – $e');
      }
    }
    // v6 → v7: add user_profile table
    if (oldVersion < 7) {
      try {
        await db.execute('''
          CREATE TABLE user_profile(
            accountOwner TEXT PRIMARY KEY,
            displayName TEXT,
            status TEXT,
            avatarPath TEXT,
            bio TEXT,
            phoneNumber TEXT,
            email TEXT,
            customJson TEXT,
            updatedAt INTEGER
          )
        ''');
        debugPrint('Upgrade v7: added user_profile table');
      } catch (e) {
        debugPrint('Upgrade v7: error creating user_profile table – $e');
      }
    }
    // v7 → v8: fix group overwrites – recreate tables with composite PK
    if (oldVersion < 8) {
      debugPrint('⚠️ Upgrading to v8: dropping old group tables and recreating with composite PK');
      try {
        // Drop old tables
        await db.execute('DROP TABLE IF EXISTS group_messages');
        await db.execute('DROP TABLE IF EXISTS groups');
        // Recreate groups with composite PK
        await db.execute('''
          CREATE TABLE groups(
            id TEXT NOT NULL,
            accountOwner TEXT NOT NULL,
            name TEXT NOT NULL,
            owner TEXT NOT NULL,
            members TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            avatarPath TEXT,
            isMuted INTEGER DEFAULT 0,
            lastMessage TEXT,
            lastMessageTime INTEGER,
            unreadCount INTEGER DEFAULT 0,
            PRIMARY KEY (id, accountOwner)
          )
        ''');
        await db.execute('CREATE INDEX idx_groups_account ON groups(accountOwner)');
        // Recreate group_messages with accountOwner
        await db.execute('''
          CREATE TABLE group_messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            groupId TEXT NOT NULL,
            accountOwner TEXT NOT NULL,
            sender TEXT NOT NULL,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            isMe INTEGER NOT NULL,
            status TEXT DEFAULT 'sent',
            read INTEGER DEFAULT 0,
            delivered INTEGER DEFAULT 0,
            messageId TEXT,
            isHidden INTEGER DEFAULT 0,
            hiddenKey TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_group_messages_group ON group_messages(groupId, accountOwner)');
        await db.execute('CREATE INDEX idx_group_messages_timestamp ON group_messages(timestamp)');
        debugPrint('✅ v8 upgrade completed – groups table recreated');
      } catch (e) {
        debugPrint('❌ v8 upgrade failed: $e');
      }
    }
  }

  // ------------------------------------------------------------------------
  //                           INITIALIZATION
  // ------------------------------------------------------------------------
  Future<void> initialize() async {
    if (!_initialized) await database;
  }

  // ------------------------------------------------------------------------
  //                    MESSAGE OPERATIONS (1:1)
  // ------------------------------------------------------------------------

  Future<int> saveMessage({
    required String owner,
    required String contact,
    required String sender,
    required String type,
    required String content,
    required bool isMe,
    String? extra,
    String? reaction,
    Map<String, dynamic>? metadata,
    String? status,
    bool read = false,
    bool delivered = false,
    String? messageId,
    int isHidden = 0,
    String? hiddenKey,
  }) async {
    final db = await database;

    if (messageId != null) {
      try {
        final existing = await db.query(
          'messages',
          where: 'messageId = ? AND accountOwner = ?',
          whereArgs: [messageId, owner],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          debugPrint('⚠️ Message with id $messageId already exists, skipping insert');
          return existing.first['id'] as int;
        }
      } catch (e) {
        debugPrint('❌ Error checking existing message: $e');
      }
    }

    final metadataJson = metadata != null ? jsonEncode(metadata) : null;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final id = await db.insert('messages', {
        'accountOwner': owner,
        'contact': contact,
        'sender': sender,
        'type': type,
        'content': content,
        'timestamp': now,
        'isMe': isMe ? 1 : 0,
        'reaction': reaction,
        'extra': extra,
        'metadata': metadataJson,
        'status': status ?? (isMe ? 'sent' : 'delivered'),
        'read': read ? 1 : 0,
        'delivered': delivered ? 1 : 0,
        'messageId': messageId,
        'isHidden': isHidden,
        'hiddenKey': hiddenKey,
      });
      return id;
    } catch (e) {
      debugPrint('❌ Database error saving message: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getMessagesForContact(
      String owner,
      String contact, {
      int limit = 100,
      int offset = 0,
    }) async {
      final db = await database;
      try {
        final messages = await db.query(
          'messages',
          where: 'accountOwner = ? AND contact = ?',
          whereArgs: [owner, contact],
          orderBy: 'timestamp ASC',
          limit: limit,
          offset: offset,
        );
        return messages.map((msg) {
          final mutableMsg = Map<String, dynamic>.from(msg);
          if (mutableMsg['metadata'] != null && mutableMsg['metadata'] is String) {
            mutableMsg['metadata'] = _jsonToMap(mutableMsg['metadata'] as String);
          }
          return mutableMsg;
        }).toList();
      } catch (e) {
        debugPrint('⚠️ Database getMessagesForContact error (possibly row too big): $e');
        // Agar row too big ki wajah se crash ho, toh pichli chat ko delete karna behtar hai
        // taake chat open ho sakay.
        if (e.toString().contains("Row too big to fit into CursorWindow")) {
            debugPrint('🗑️ Deleting corrupted large messages to recover chat.');
            await deleteMessagesForContact(owner, contact);
        }
        return []; // Return empty list instead of crashing
      }
    }
  Future<List<Map<String, dynamic>>> getLastMessages(String owner) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT m1.*
      FROM messages m1
      INNER JOIN (
        SELECT contact, MAX(timestamp) as max_timestamp
        FROM messages
        WHERE accountOwner = ?
        GROUP BY contact
      ) m2 ON m1.contact = m2.contact AND m1.timestamp = m2.max_timestamp
      WHERE m1.accountOwner = ?
      ORDER BY m1.timestamp DESC
    ''', [owner, owner]);
    return result;
  }

  Future<int> getUnreadCount(String owner, String contact) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE accountOwner = ? AND contact = ? AND isMe = 0 AND read = 0',
      [owner, contact],
    );
    return (result.isNotEmpty ? result.first['count'] as int? : 0) ?? 0;
  }

  Future<void> markMessagesAsRead(String owner, String contact) async {
    final db = await database;
    await db.update(
      'messages',
      {'read': 1},
      where: 'accountOwner = ? AND contact = ? AND isMe = 0',
      whereArgs: [owner, contact],
    );
  }

  Future<void> markMessageDelivered(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {'delivered': 1},
      where: 'messageId = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markMessageRead(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {'read': 1},
      where: 'messageId = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageReaction(int messageId, String? reaction) async {
    final db = await database;
    await db.update(
      'messages',
      {'reaction': reaction},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageStatus(int messageId, String status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessagesForContact(String owner, String contactName) async {
    final db = await database;
    final messages = await db.query(
      'messages',
      columns: ['content'],
      where: 'accountOwner = ? AND contact = ? AND type IN ("IMAGE", "AUDIO", "FILE")',
      whereArgs: [owner, contactName],
    );
    await db.delete(
      'messages',
      where: 'accountOwner = ? AND contact = ?',
      whereArgs: [owner, contactName],
    );
    for (var msg in messages) {
      try {
        final path = msg['content'] as String;
        if (_isLikelyFilePath(path)) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } catch (e) {
        debugPrint('Failed to delete file: $e');
      }
    }
  }


  Future<void> pinMessage(String messageId, bool pin) async {
    final db = await database;
    await db.update(
      'messages',
      {
        'isPinned': pin ? 1 : 0,
        'pinnedAt': pin ? DateTime.now().millisecondsSinceEpoch : null,
      },
      where: 'messageId = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<Map<String, dynamic>>> getPinnedMessages(
      String owner, String contact) async {
    final db = await database;
    final results = await db.query(
      'messages',
      where: 'accountOwner = ? AND contact = ? AND isPinned = 1',
      whereArgs: [owner, contact],
      orderBy: 'pinnedAt DESC',
    );
    return results.map((m) {
      final mm = Map<String, dynamic>.from(m);
      if (mm['metadata'] != null && mm['metadata'] is String) {
        mm['metadata'] = _jsonToMap(mm['metadata'] as String);
      }
      return mm;
    }).toList();
  }

  Future<void> deleteMessage(int messageId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<Map<String, dynamic>>> searchMessages(String owner, String query) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'accountOwner = ? AND type = "TEXT" AND content LIKE ?',
      whereArgs: [owner, '%$query%'],
      orderBy: 'timestamp DESC',
      limit: 50,
    );
  }

  // ------------------------------------------------------------------------
  //                     CONTACT OPERATIONS
  // ------------------------------------------------------------------------

  Future<void> saveContact({
    required String owner,
    required String contactName,
    String? publicKey,
    int? lastSeen,
    bool isBlocked = false,
    bool isFavorite = false,
    String? chatBackground,
    Map<String, dynamic>? notificationSettings,
    String? fcmToken,
  }) async {
    final db = await database;
    final settingsJson = notificationSettings != null ? jsonEncode(notificationSettings) : null;
    await db.insert(
      'contacts',
      {
        'accountOwner': owner,
        'contactName': contactName,
        'publicKey': publicKey,
        'lastSeen': lastSeen,
        'isBlocked': isBlocked ? 1 : 0,
        'isFavorite': isFavorite ? 1 : 0,
        'chatBackground': chatBackground,
        'notificationSettings': settingsJson,
        'fcmToken': fcmToken,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getContacts(String owner) async {
    final db = await database;
    return await db.query(
      'contacts',
      where: 'accountOwner = ?',
      whereArgs: [owner],
      orderBy: 'contactName ASC',
    );
  }

  Future<Map<String, dynamic>?> getContact(String owner, String contactName) async {
    final db = await database;
    final results = await db.query(
      'contacts',
      where: 'accountOwner = ? AND contactName = ?',
      whereArgs: [owner, contactName],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> updateContactLastSeen(String owner, String contactName, int timestamp) async {
    final db = await database;
    await db.update(
      'contacts',
      {'lastSeen': timestamp},
      where: 'accountOwner = ? AND contactName = ?',
      whereArgs: [owner, contactName],
    );
  }

  Future<void> updateContactFcmToken(String owner, String contactName, String? token) async {
    final db = await database;
    await db.update(
      'contacts',
      {'fcmToken': token},
      where: 'accountOwner = ? AND contactName = ?',
      whereArgs: [owner, contactName],
    );
  }

  Future<void> toggleContactBlock(String owner, String contactName, bool isBlocked) async {
    final db = await database;
    await db.update(
      'contacts',
      {'isBlocked': isBlocked ? 1 : 0},
      where: 'accountOwner = ? AND contactName = ?',
      whereArgs: [owner, contactName],
    );
  }

  Future<void> toggleContactFavorite(String owner, String contactName, bool isFavorite) async {
    final db = await database;
    await db.update(
      'contacts',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'accountOwner = ? AND contactName = ?',
      whereArgs: [owner, contactName],
    );
  }

  Future<void> updateChatBackground(String owner, String contactName, String? backgroundPath) async {
    final db = await database;
    await db.update(
      'contacts',
      {'chatBackground': backgroundPath},
      where: 'accountOwner = ? AND contactName = ?',
      whereArgs: [owner, contactName],
    );
  }

  // ------------------------------------------------------------------------
  //                     CALL LOG OPERATIONS
  // ------------------------------------------------------------------------

  Future<void> saveCallLog({
    required String owner,
    required String contact,
    required String callType,
    required String direction,
    required int startTime,
    int? endTime,
    int? duration,
    required String status,
    String? notes,
  }) async {
    final db = await database;
    await db.insert('call_logs', {
      'accountOwner': owner,
      'contact': contact,
      'callType': callType,
      'direction': direction,
      'startTime': startTime,
      'endTime': endTime,
      'duration': duration,
      'status': status,
      'notes': notes,
    });
  }

  Future<List<Map<String, dynamic>>> getCallLogs(
    String owner,
    String contact, {
    int limit = 50,
  }) async {
    final db = await database;
    return await db.query(
      'call_logs',
      where: 'accountOwner = ? AND contact = ?',
      whereArgs: [owner, contact],
      orderBy: 'startTime DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCallLogs(String owner, {int limit = 100}) async {
    final db = await database;
    return await db.query(
      'call_logs',
      where: 'accountOwner = ?',
      whereArgs: [owner],
      orderBy: 'startTime DESC',
      limit: limit,
    );
  }

  /// Deletes a single call-log row. Used by swipe-to-delete in Call History.
  Future<void> deleteCallLog(int id) async {
    final db = await database;
    try {
      await db.delete('call_logs', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('❌ Failed to delete call log $id: $e');
      rethrow;
    }
  }

  /// Wipes the entire call history for [owner].
  Future<int> clearCallLogs(String owner) async {
    final db = await database;
    try {
      return await db.delete(
        'call_logs',
        where: 'accountOwner = ?',
        whereArgs: [owner],
      );
    } catch (e) {
      debugPrint('❌ Failed to clear call logs: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------------------
  //                     FILE CACHE OPERATIONS
  // ------------------------------------------------------------------------

  Future<void> saveFileToCache({
    required String filePath,
    int? messageId,
    String? contact,
    String? fileType,
    int? size,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'file_cache',
      {
        'filePath': filePath,
        'messageId': messageId,
        'contact': contact,
        'fileType': fileType,
        'size': size,
        'downloadedAt': now,
        'accessedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateFileAccessTime(String filePath) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'file_cache',
      {'accessedAt': now},
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
  }

  Future<void> cleanupFileCache({int daysToKeep = 30}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: daysToKeep)).millisecondsSinceEpoch;
    final oldFiles = await db.query(
      'file_cache',
      where: 'accessedAt < ?',
      whereArgs: [cutoff],
    );
    for (var file in oldFiles) {
      try {
        final path = file['filePath'] as String;
        final fileObj = File(path);
        if (await fileObj.exists()) await fileObj.delete();
      } catch (e) {
        debugPrint('Failed to delete cached file: $e');
      }
    }
    await db.delete(
      'file_cache',
      where: 'accessedAt < ?',
      whereArgs: [cutoff],
    );
  }

  // ------------------------------------------------------------------------
  //                     GROUP OPERATIONS (v8 with composite PK)
  // ------------------------------------------------------------------------

  Future<void> saveGroup({
    required String accountOwner,
    required String id,
    required String name,
    required String owner,
    required List<String> members,
    required DateTime createdAt,
    String? avatarPath,
    bool isMuted = false,
    String? lastMessage,
    int? lastMessageTime,
    int unreadCount = 0,
    List<String>? admins,
    int mutedUntil = 0,
    String? wallpaper,
    String? pinnedMessage,
  }) async {
    final db = await database;
    try {
      debugPrint('💾 Saving group $id for accountOwner $accountOwner');
      await db.insert(
        'groups',
        {
          'id': id,
          'accountOwner': accountOwner,
          'name': name,
          'owner': owner,
          'members': jsonEncode(members),
          'createdAt': createdAt.millisecondsSinceEpoch,
          'avatarPath': avatarPath,
          'isMuted': isMuted ? 1 : 0,
          'lastMessage': lastMessage,
          'lastMessageTime': lastMessageTime,
          'unreadCount': unreadCount,
          'admins': jsonEncode(admins ?? const <String>[]),
          'mutedUntil': mutedUntil,
          'wallpaper': wallpaper,
          'pinnedMessage': pinnedMessage,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Group saved: $id');
    } catch (e) {
      debugPrint('❌ Failed to save group: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getGroups(String accountOwner) async {
    final db = await database;
    final results = await db.query(
      'groups',
      where: 'accountOwner = ?',
      whereArgs: [accountOwner],
      orderBy: 'lastMessageTime DESC',
    );
    debugPrint('📊 getGroups for $accountOwner: found ${results.length} rows');
    if (results.isNotEmpty) {
      debugPrint('   IDs: ${results.map((r) => r['id']).toList()}');
    }
    return results.map((g) {
      final mutableGroup = Map<String, dynamic>.from(g);
      mutableGroup['members'] = jsonDecode(mutableGroup['members'] as String);
      return mutableGroup;
    }).toList();
  }

  Future<Map<String, dynamic>?> getGroup(String accountOwner, String groupId) async {
    final db = await database;
    final results = await db.query(
      'groups',
      where: 'accountOwner = ? AND id = ?',
      whereArgs: [accountOwner, groupId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final mutableGroup = Map<String, dynamic>.from(results.first);
    mutableGroup['members'] = jsonDecode(mutableGroup['members'] as String);
    return mutableGroup;
  }

  Future<void> updateGroup({
    required String accountOwner,
    required String id,
    String? name,
    String? avatarPath,
    bool? isMuted,
    String? lastMessage,
    int? lastMessageTime,
    int? unreadCount,
    List<String>? admins,
    int? mutedUntil,
    String? wallpaper,
    String? pinnedMessage,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (avatarPath != null) updates['avatarPath'] = avatarPath;
    if (isMuted != null) updates['isMuted'] = isMuted ? 1 : 0;
    if (lastMessage != null) updates['lastMessage'] = lastMessage;
    if (lastMessageTime != null) updates['lastMessageTime'] = lastMessageTime;
    if (unreadCount != null) updates['unreadCount'] = unreadCount;
    if (admins != null) updates['admins'] = jsonEncode(admins);
    if (mutedUntil != null) updates['mutedUntil'] = mutedUntil;
    if (wallpaper != null) updates['wallpaper'] = wallpaper;
    if (pinnedMessage != null) updates['pinnedMessage'] = pinnedMessage;

    if (updates.isEmpty) return;
    try {
      await db.update(
        'groups',
        updates,
        where: 'accountOwner = ? AND id = ?',
        whereArgs: [accountOwner, id],
      );
    } catch (e) {
      debugPrint('❌ Failed to update group: $e');
    }
  }

  Future<void> deleteGroup(String accountOwner, String groupId) async {
    final db = await database;
    try {
      await db.delete(
        'groups',
        where: 'accountOwner = ? AND id = ?',
        whereArgs: [accountOwner, groupId],
      );
    } catch (e) {
      debugPrint('❌ Failed to delete group: $e');
    }
  }

  Future<void> incrementGroupUnread(String accountOwner, String groupId) async {
    final db = await database;
    try {
      await db.rawUpdate('''
        UPDATE groups 
        SET unreadCount = unreadCount + 1 
        WHERE accountOwner = ? AND id = ?
      ''', [accountOwner, groupId]);
    } catch (e) {
      debugPrint('❌ Failed to increment unread: $e');
    }
  }

  Future<void> markGroupAsRead(String accountOwner, String groupId) async {
    final db = await database;
    try {
      await db.update(
        'groups',
        {'unreadCount': 0},
        where: 'accountOwner = ? AND id = ?',
        whereArgs: [accountOwner, groupId],
      );
    } catch (e) {
      debugPrint('❌ Failed to mark group as read: $e');
    }
  }

  // ------------------------------------------------------------------------
  //                 GROUP MESSAGE OPERATIONS (v8 with accountOwner)
  // ------------------------------------------------------------------------

  Future<int> saveGroupMessage({
    required String accountOwner,
    required String groupId,
    required String sender,
    required String type,
    required String content,
    required bool isMe,
    String? status,
    bool read = false,
    bool delivered = false,
    String? messageId,
    int? timestamp,
    int isHidden = 0,
    String? hiddenKey,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;

    if (messageId != null) {
      try {
        final existing = await db.query(
          'group_messages',
          where: 'messageId = ? AND accountOwner = ?',
          whereArgs: [messageId, accountOwner],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          debugPrint('⚠️ Group message with id $messageId already exists, skipping insert');
          return existing.first['id'] as int;
        }
      } catch (e) {
        debugPrint('❌ Error checking existing group message: $e');
      }
    }

    final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    try {
      final id = await db.insert('group_messages', {
        'groupId': groupId,
        'accountOwner': accountOwner,
        'sender': sender,
        'type': type,
        'content': content,
        'timestamp': now,
        'isMe': isMe ? 1 : 0,
        'status': status ?? (isMe ? 'sent' : 'delivered'),
        'read': read ? 1 : 0,
        'delivered': delivered ? 1 : 0,
        'messageId': messageId,
        'isHidden': isHidden,
        'hiddenKey': hiddenKey,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
      });
      await updateGroup(
        accountOwner: accountOwner,
        id: groupId,
        lastMessage: content,
        lastMessageTime: now,
      );
      return id;
    } catch (e) {
      debugPrint('❌ Database error saving group message: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMessages(
    String accountOwner,
    String groupId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      'group_messages',
      where: 'groupId = ? AND accountOwner = ?',
      whereArgs: [groupId, accountOwner],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map((m) {
      final mm = Map<String, dynamic>.from(m);
      if (mm['metadata'] != null && mm['metadata'] is String) {
        mm['metadata'] = _jsonToMap(mm['metadata'] as String);
      }
      return mm;
    }).toList();
  }

  Future<void> markGroupMessageDelivered(String messageId) async {
    final db = await database;
    try {
      await db.update(
        'group_messages',
        {'delivered': 1},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Failed to mark group message delivered: $e');
    }
  }

  Future<void> markGroupMessageRead(String messageId) async {
    final db = await database;
    try {
      await db.update(
        'group_messages',
        {'read': 1},
        where: 'messageId = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Failed to mark group message read: $e');
    }
  }

  Future<void> updateGroupMessageHiddenStatus(
    int messageId,
    int isHidden, {
    String? hiddenKey,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{'isHidden': isHidden};
    if (hiddenKey != null) updates['hiddenKey'] = hiddenKey;
    try {
      await db.update(
        'group_messages',
        updates,
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint('❌ Failed to update hidden status: $e');
    }
  }

  Future<void> deleteGroupMessages(String groupId) async {
    final db = await database;
    try {
      await db.delete(
        'group_messages',
        where: 'groupId = ?',
        whereArgs: [groupId],
      );
    } catch (e) {
      debugPrint('❌ Failed to delete group messages: $e');
    }
  }

  // ------------------------------------------------------------------------
  //                     USER PROFILE OPERATIONS (v7)
  // ------------------------------------------------------------------------

  Future<void> saveUserProfile({
    required String accountOwner,
    String? displayName,
    String? status,
    String? avatarPath,
    String? bio,
    String? phoneNumber,
    String? email,
    Map<String, dynamic>? customJson,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'user_profile',
      {
        'accountOwner': accountOwner,
        'displayName': displayName,
        'status': status,
        'avatarPath': avatarPath,
        'bio': bio,
        'phoneNumber': phoneNumber,
        'email': email,
        'customJson': customJson != null ? jsonEncode(customJson) : null,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUserProfile(String accountOwner) async {
    final db = await database;
    final results = await db.query(
      'user_profile',
      where: 'accountOwner = ?',
      whereArgs: [accountOwner],
      limit: 1,
    );
    if (results.isEmpty) return null;
    final profile = Map<String, dynamic>.from(results.first);
    if (profile['customJson'] != null) {
      profile['customJson'] = jsonDecode(profile['customJson'] as String);
    }
    return profile;
  }

  Future<void> updateUserProfile({
    required String accountOwner,
    String? displayName,
    String? status,
    String? avatarPath,
    String? bio,
    String? phoneNumber,
    String? email,
    Map<String, dynamic>? customJson,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (status != null) updates['status'] = status;
    if (avatarPath != null) updates['avatarPath'] = avatarPath;
    if (bio != null) updates['bio'] = bio;
    if (phoneNumber != null) updates['phoneNumber'] = phoneNumber;
    if (email != null) updates['email'] = email;
    if (customJson != null) updates['customJson'] = jsonEncode(customJson);
    updates['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    if (updates.isEmpty) return;
    try {
      await db.update(
        'user_profile',
        updates,
        where: 'accountOwner = ?',
        whereArgs: [accountOwner],
      );
    } catch (e) {
      debugPrint('❌ Failed to update user profile: $e');
    }
  }

  Future<void> deleteUserProfile(String accountOwner) async {
    final db = await database;
    try {
      await db.delete(
        'user_profile',
        where: 'accountOwner = ?',
        whereArgs: [accountOwner],
      );
    } catch (e) {
      debugPrint('❌ Failed to delete user profile: $e');
    }
  }

  // ------------------------------------------------------------------------
  //                     DATABASE MAINTENANCE
  // ------------------------------------------------------------------------

  Future<Map<String, dynamic>> getDatabaseStats(String owner) async {
    final db = await database;
    final msgCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE accountOwner = ?',
      [owner],
    );
    final contactCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM contacts WHERE accountOwner = ?',
      [owner],
    );
    final groupCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM groups WHERE accountOwner = ?',
      [owner],
    );
    final callCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM call_logs WHERE accountOwner = ?',
      [owner],
    );
    final fileSize = await db.rawQuery(
      'SELECT SUM(size) as total FROM file_cache',
    );
    return {
      'messages': (msgCount.first['count'] as int?) ?? 0,
      'contacts': (contactCount.first['count'] as int?) ?? 0,
      'groups': (groupCount.first['count'] as int?) ?? 0,
      'calls': (callCount.first['count'] as int?) ?? 0,
      'file_cache_size': (fileSize.first['total'] as int?) ?? 0,
    };
  }

  Future<String> backupDatabase() async {
    final db = await database;
    await db.execute('VACUUM');
    final dbPath = join(await getDatabasesPath(), 'veilchat_v$_version.db');
    final backupPath = join(
      await getDatabasesPath(),
      'veilchat_backup_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final source = File(dbPath);
    await source.copy(backupPath);
    return backupPath;
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _initialized = false;
    }
  }

  // ------------------------------------------------------------------------
  //                         PRIVATE HELPERS
  // ------------------------------------------------------------------------

  String _mapToJson(Map<String, dynamic> map) {
    try {
      return jsonEncode(map);
    } catch (e) {
      debugPrint('Failed to encode map: $e');
      return '{}';
    }
  }

  Map<String, dynamic> _jsonToMap(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Failed to decode JSON: $e');
      return {};
    }
  }

  bool _isLikelyFilePath(String path) {
    return path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:\\').hasMatch(path) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(path);
  }
}
import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'call_screen.dart';
import 'veil_backgrounds.dart';
import 'chat_lock_screen.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/network_service.dart';
import 'services/crypto_service.dart';
import 'services/database_service.dart';
import 'services/sound_service.dart';
import 'services/file_transfer_service.dart';
import 'services/stego_service.dart';
import 'services/media_service.dart';

class ChatDetailScreen extends StatefulWidget {
  final String contactName;
  final bool isDark;
  final String sharedKey;
  final String myUsername;

  const ChatDetailScreen({
    super.key,
    required this.contactName,
    required this.isDark,
    required this.sharedKey,
    required this.myUsername,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with WidgetsBindingObserver {
  final NetworkService _network = NetworkService();
  final DatabaseService _db = DatabaseService();
  final CryptoService _crypto = CryptoService();
  final SoundService _sound = SoundService();
  final FileTransferService _fileTransfer = FileTransferService();
  final StegoService _stego = StegoService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  bool _isContactTyping = false;
  Timer? _typingDebounce;
  bool _hasSentTyping = false;
  bool _isLoadingMore = false;  // loading older messages
  bool _hasMoreMessages = true; // false when all loaded
  int _messageOffset = 0;       // for pagination
  static const int _pageSize = 50;
  bool _showEmojiPicker = false;
  bool _isLoading = true;
  String? _contactBackgroundPath;

  Timer? _typingTimer;
  Timer? _debounceTimer;

  bool _isRecordingVoice = false;
  int _recordingTime = 0;

  final Map<String, bool> _playingAudioMessages = {};
  final Map<String, Duration> _audioDurations = {};
  final Map<String, Duration> _audioPositions = {};

  StreamSubscription? _messageSub;
  StreamSubscription? _userListSub;
  Timer? _onlineRefreshTimer;
  StreamSubscription? _recordingTimeSub;

  final Map<int, String> _decryptedMediaPaths = {};
  final Set<int> _downloadingMedia = {}; // 🔥 TRACK DOWNLOADS

  // Online, cache, reply, search, avatar state
  bool _isContactOnline = false;
  final Map<String, String> _decryptCache = {};
  Map<String, dynamic>? _replyMsg;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _myAvatarPath;
  String? _contactAvatarPath;
  int _contactLastSeen = 0;
  bool _isContactBlocked = false;
  List<Map<String, dynamic>> _pinnedMessages = [];
  bool _showPinnedPanel = false;
  bool _isChatLocked = false;  // ms timestamp

  final List<String> _emojis = [
    "😀","😂","🤣","😍","🥰","😎","🤔","🤨","😐","😑","😶","🙄","😏",
    "😣","😥","😮","😯","😪","😫","😴","😌","😛","😜","😝","🤤","😒",
    "😓","😔","😕","🙃","🤑","😲","☹️","🙁","😖","😞","😟","😤","😢",
    "😭","😦","😧","😨","😩","🤯","😬","😶‍🌫️","😱","🥵","🥶","😳","🤪",
    "😵","😡","😠","🤬","😷","🤒","🤕","🤢","🤮","🤧","😇","🥳",
    "🥺","🤠","🤡","🤥","🤫","🤭","🧐","🤓","😈","👿","👹","👺","💀",
    "👻","👽","🤖","💩","😺","😸","😹","😻","😼","😽","🙀","😿","😾",
    "❤️","🧡","💛","💚","💙","💜","🖤","💔","❣️","💕","💞","💓","💗",
    "💖","💘","💝","👍","👎","👊","✌️","👌","✋","💪","🙏","☝️","👆",
    "👇","👈","👉","🖕","🖐","🤘","🤟"
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initContactBackground();
    _loadMessages();
    _markMessagesAsRead();
    _setupListeners();
    _scrollController.addListener(_onScroll);
    _loadAvatars();
    _loadPinnedMessages();
    _checkChatLock();
    // ✅ FIX: Request online status immediately and refresh every 10 seconds
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _network.sendPacket('GET_USER_LIST', {});
    });
    _onlineRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _network.isConnected) {
        _network.sendPacket('GET_USER_LIST', {});
      }
    });

    // ✅ FIX: Subscribe to userListStream (USER_LIST goes there, NOT messageStream)
    _userListSub = _network.userListStream.listen((data) {
      if (!mounted) return;
      final rawUsers = data['users'] as Map? ?? {};
      final contactData = rawUsers[widget.contactName];
      bool isOnline = false;
      int lastSeen = 0;
      if (contactData is Map) {
        isOnline = contactData['status'] == 'Online';
        lastSeen = (contactData['lastSeen'] as num?)?.toInt() ?? 0;
      } else if (contactData is String) {
        isOnline = contactData == 'Online';
      }
      if (mounted) setState(() {
        _isContactOnline = isOnline;
        if (lastSeen > 0) _contactLastSeen = lastSeen;
      });
    });
    _focusNode.addListener(_onFocusChange);
    _msgController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgController.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _msgController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _debounceTimer?.cancel();
    _messageSub?.cancel();
    _userListSub?.cancel();
    _onlineRefreshTimer?.cancel();
    _recordingTimeSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markMessagesAsRead();
    }
  }

  Future<void> _initContactBackground() async {
    final contact = await _db.getContact(widget.myUsername, widget.contactName);
    if (contact != null && contact['chatBackground'] != null) {
      if (!mounted) return;
      setState(() {
        _contactBackgroundPath = contact['chatBackground'];
        VeilTheme.chatBgPath = _contactBackgroundPath;
      });
    }
  }

  Future<void> _loadMessages() async {
    // Reset pagination on full reload
    _messageOffset = 0;
    _hasMoreMessages = true;
    final data = await _db.getMessagesForContact(
      widget.myUsername,
      widget.contactName,
      limit: _pageSize,
      offset: 0,
    );
    if (data.length < _pageSize) _hasMoreMessages = false;
    _messageOffset = data.length;

    final futures = data.map((m) async {
      String displayContent = m['content'] ?? '';

      if (m['type'] == 'TEXT' && displayContent.isNotEmpty) {
        try {
          final bytes = _crypto.hexToBytes(displayContent);
          final dec = await _crypto.decrypt(widget.sharedKey, bytes);
          displayContent = dec ?? '🔒 Decryption failed';
        } catch (e) {
          displayContent = '🔒 Encrypted Message';
        }
      }

      return {
        'id': m['id'],
        'messageId': m['messageId'],
        'isPinned': m['isPinned'] ?? 0,
        'content': displayContent,
        'type': m['type'] ?? 'TEXT',
        'isMe': m['isMe'] == 1,
        'time': m['timestamp'],
        'reaction': m['reaction'],
        'status': m['status'] ?? 'sent',
        'read': m['read'] == 1,
        'delivered': m['delivered'] == 1,
        'isHidden': m['isHidden'] ?? 0,
        'hiddenKey': m['hiddenKey'],
        'metadata': m['metadata'],
        'originalPath': m['content'],
      };
    }).toList();

    final processed = await Future.wait(futures);

    final unique = <String, Map<String, dynamic>>{};
    for (var msg in processed) {
      final key = msg['messageId'] ?? msg['time'].toString();
      unique[key] = msg;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a['time'].compareTo(b['time']));

    if (!mounted) return;
    setState(() {
      _messages = deduped;
      _isLoading = false;
    });

    for (var msg in deduped) {
      if (msg['type'] != 'TEXT' && !_decryptedMediaPaths.containsKey(msg['id'])) {
        _decryptMediaFile(msg);
      }
    }
    _scrollToBottom();
  }

  Future<void> _decryptMediaFile(Map<String, dynamic> msg) async {
    final String content = msg['originalPath'] ?? msg['content'] ?? '';
    final int msgId = msg['id'] ?? 0;
    final String type = msg['type'] ?? 'TEXT';

    if (content.isEmpty || content.contains(' ') || content.contains('/')) return;

    // Prevent multiple downloads
    if (_downloadingMedia.contains(msgId)) {
      debugPrint('📥 Already downloading msgId $msgId, skipping');
      return;
    }
    _downloadingMedia.add(msgId);

    debugPrint('📥 _decryptMediaFile for msgId $msgId, serverFilename: $content');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final subDir = Directory('${dir.path}/veil_chat_files');
      if (!await subDir.exists()) await subDir.create(recursive: true);

      // ✅ FIX: safely cast metadata regardless of key type
      final metaRaw = msg['metadata'];
      final metaMap2 = <String, dynamic>{};
      if (metaRaw is Map) {
        metaRaw.forEach((k, v) => metaMap2[k.toString()] = v);
      }
      final origFilename = metaMap2['filename']?.toString() ?? '';
      String ext;
      String saveBase;
      if (origFilename.isNotEmpty) {
        final dotIdx = origFilename.lastIndexOf('.');
        ext = dotIdx >= 0 ? origFilename.substring(dotIdx) : '.dat';
        final safeName = origFilename.replaceAll(RegExp(r'[^\w._-]'), '_');
        saveBase = safeName;
      } else {
        ext = type == 'IMAGE' ? '.jpg' : type == 'AUDIO' ? '.m4a' : '.dat';
        saveBase = 'recv_${msg['messageId'] ?? msgId}$ext';
      }
      final savePath = '${subDir.path}/$saveBase';

      // Check if already decrypted
      if (await File(savePath).exists()) {
        debugPrint('📥 File already exists: $savePath');
        if (mounted) {
          setState(() {
            _decryptedMediaPaths[msgId] = savePath;
            int index = _messages.indexWhere((m) => m['id'] == msgId);
            if (index != -1) _messages[index]['content'] = savePath;
          });
        }
        _downloadingMedia.remove(msgId);
        return;
      }

      // Retry download up to 3 times
      const maxRetries = 3;
      File? downloadedFile;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        debugPrint('📥 Download attempt $attempt for $content');
        final tempEncPath = '$savePath.enc$attempt';
        downloadedFile = await MediaService.downloadEncryptedFile(content, tempEncPath);

        if (downloadedFile != null && await downloadedFile.exists()) {
          int fileSize = await downloadedFile.length();
          if (fileSize < 48) {
            debugPrint('❌ Downloaded file too small ($fileSize bytes), retrying...');
            await downloadedFile.delete();
            downloadedFile = null;
            continue;
          }
          break;
        } else {
          debugPrint('❌ Download attempt $attempt failed');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }
      }

      if (downloadedFile == null) {
        debugPrint('❌ All download attempts failed for $content');
        if (mounted) {
          _showError('Failed to download media. Tap to retry.');
        }
        _downloadingMedia.remove(msgId);
        return;
      }

      // Proceed with decryption
      debugPrint('📥 Downloaded file size: ${await downloadedFile.length()} bytes');
      String hexData = await downloadedFile.readAsString();
      hexData = hexData.trim();
      debugPrint('📥 Hex data length: ${hexData.length} characters');

      try {
        final encryptedBytes = _crypto.hexToBytes(hexData);
        debugPrint('📥 Encrypted bytes length: ${encryptedBytes.length} bytes');
        final decryptedBase64 = await _crypto.decrypt(widget.sharedKey, encryptedBytes);

        if (decryptedBase64 != null) {
          debugPrint('📥 Decryption successful, base64 length: ${decryptedBase64.length}');
          final clearBytes = base64Decode(decryptedBase64);
          debugPrint('📥 Final image bytes length: ${clearBytes.length}');

          final finalFile = File(savePath);
          await finalFile.writeAsBytes(clearBytes);
          await downloadedFile.delete();

          final db = await _db.database;
          await db.update('messages', {'content': finalFile.path}, where: 'id = ?', whereArgs: [msgId]);

          if (mounted) {
            setState(() {
              _decryptedMediaPaths[msgId] = finalFile.path;
              int index = _messages.indexWhere((m) => m['id'] == msgId);
              if (index != -1) _messages[index]['content'] = finalFile.path;
            });
          }
        } else {
          debugPrint('❌ Decryption returned null – wrong key or corrupted data');
          if (mounted) {
            _showError('Decryption failed. Wrong key?');
          }
        }
      } catch (e) {
        debugPrint('❌ Decryption error: $e');
        if (mounted) {
          _showError('Failed to decrypt media');
        }
      }
    } catch (e) {
      debugPrint("Media decryption error: $e");
    } finally {
      _downloadingMedia.remove(msgId);
    }
  }



  Future<void> _loadPinnedMessages() async {
    final pinned = await _db.getPinnedMessages(
        widget.myUsername, widget.contactName);
    if (mounted) setState(() => _pinnedMessages = pinned);
  }


  Future<void> _checkChatLock() async {
    final locked = await ChatLockScreen.isLocked(widget.contactName);
    if (mounted) setState(() => _isChatLocked = locked);
  }

  Future<void> _manageChatLock() async {
    if (_isChatLocked) {
      // Remove lock
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
          title: Text('Remove Lock?',
            style: TextStyle(color: widget.isDark ? Colors.white : Colors.black)),
          content: Text('This chat will no longer require a PIN.',
            style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('REMOVE', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm == true) {
        await ChatLockScreen.setPin(widget.contactName, null);
        setState(() => _isChatLocked = false);
        _showSnack('Chat lock removed', Colors.grey);
      }
    } else {
      // Set new PIN
      _showSetPinDialog();
    }
  }

  void _showSetPinDialog() {
    String pin1 = '';
    String pin2 = '';
    int step = 1;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
            title: Text(
              step == 1 ? 'Enter new PIN' : 'Confirm PIN',
              style: TextStyle(color: widget.isDark ? Colors.white : Colors.black)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Enter a 4-digit PIN to lock this chat.',
                  style: TextStyle(
                    color: widget.isDark ? Colors.white54 : Colors.black45,
                    fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  obscureText: true,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white : Colors.black,
                    letterSpacing: 8, fontSize: 20),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    hintStyle: TextStyle(
                      color: widget.isDark ? Colors.white24 : Colors.black26),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: VeilTheme.accentColor.withOpacity(0.5))),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: VeilTheme.accentColor))),
                  onChanged: (v) {
                    if (step == 1) pin1 = v;
                    else pin2 = v;
                  },
                  onSubmitted: (_) async {
                    if (step == 1 && pin1.length == 4) {
                      setDlg(() => step = 2);
                    } else if (step == 2 && pin2.length == 4) {
                      if (pin1 == pin2) {
                        await ChatLockScreen.setPin(widget.contactName, pin1);
                        if (mounted) {
                          setState(() => _isChatLocked = true);
                          Navigator.pop(ctx);
                          _showSnack('Chat lock set! 🔒', VeilTheme.accentColor);
                        }
                      } else {
                        _showSnack('PINs do not match', Colors.red);
                        Navigator.pop(ctx);
                      }
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadAvatars() async {
    // Load own profile avatar
    final myProfile = await _db.getUserProfile(widget.myUsername);
    if (myProfile != null && mounted) {
      setState(() => _myAvatarPath = myProfile['avatarPath'] as String?);
    }
    // Load contact data from contacts table
    final contact = await _db.getContact(widget.myUsername, widget.contactName);
    if (contact != null && mounted) {
      setState(() {
        _contactAvatarPath = contact['chatBackground'] as String?;
        _isContactBlocked = contact['isBlocked'] == 1;
      });
    }
  }

  void _setupListeners() {
    _messageSub = _network.messageStream.listen((data) {
      if (!mounted) return;
      final type = data['type'];
      final sender = data['sender'];

      // Read receipt — contact read our message
      if (type == 'READ_RECEI') {
        final msgId = data['metadata']?['messageId'] ?? data['messageId'];
        if (msgId != null) {
          _db.markMessageRead(msgId.toString());
          if (mounted) setState(() {
            for (var m in _messages) {
              if (m['messageId'] == msgId.toString() && m['isMe'] == true) {
                m['status'] = 'read';
                m['read'] = true;
              }
            }
          });
        }
        return;
      }

      // Delivered receipt
      if (type == 'DELIVERED_') {
        final msgId = data['metadata']?['messageId'] ?? data['messageId'];
        if (msgId != null) {
          _db.markMessageDelivered(msgId.toString());
          if (mounted) setState(() {
            for (var m in _messages) {
              if (m['messageId'] == msgId.toString() && m['isMe'] == true) {
                if (m['status'] != 'read') m['status'] = 'delivered';
              }
            }
          });
        }
        return;
      }

      // Other person deleted a message for everyone
      if (type == 'DELETE_MSG' && sender == widget.contactName) {
        final delId = data['metadata']?['messageId']?.toString();
        if (delId != null && mounted) {
          setState(() => _messages.removeWhere(
              (m) => m['messageId']?.toString() == delId));
        }
        return;
      }

      // Contact profile update — refresh their avatar
      if (type == 'PROFILE_UPDATE' && sender == widget.contactName) {
        final profile = data['profile'] as Map?;
        if (profile != null) {
          final ap = profile['avatarPath'] as String?;
          if (ap != null && mounted) setState(() => _contactAvatarPath = ap);
        }
        return;
      }

      // USER_LIST is now handled by _userListSub (userListStream)
      if (type == 'USER_LIST') return;

      if (sender == widget.contactName || data['contact'] == widget.contactName) {
        if (type == 'TYPING') {
          _handleIncomingTyping();
        } else {
          _loadMessages();
          if (data['messageId'] != null && type != 'LOCAL_UPDATE') {
            _network.sendDeliveredReceipt(widget.contactName, data['messageId']);
          }
        }
      }
    });

    _recordingTimeSub = _sound.recordingTimeStream.listen((seconds) {
      if (mounted && _isRecordingVoice) {
        setState(() => _recordingTime = seconds);
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    await _db.markMessagesAsRead(widget.myUsername, widget.contactName);
    final unreadMessages = _messages.where((m) => !m['isMe'] && !m['read']).toList();
    for (var msg in unreadMessages) {
      if (msg['messageId'] != null) {
        _network.sendReadReceipt(widget.contactName, msg['messageId']);
        await _db.markMessageRead(msg['messageId']);
      }
    }
    if (!mounted) return;
    setState(() {
      for (var msg in _messages) {
        if (!msg['isMe']) msg['read'] = true;
      }
    });
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty) return;
    _sendSecureData(_msgController.text.trim(), 'TEXT');
    _msgController.clear();
  }

  Future<void> _sendSecureData(
    String plainText,
    String type, {
    Map<String, dynamic>? metadata,
    int isHidden = 0,
    String? hiddenKey,
    String? localFilePath,
  }) async {
    HapticFeedback.lightImpact();
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    String payloadForServer = plainText;
    String payloadForDB = plainText;

    if (type == 'TEXT') {
      final encrypted = await _crypto.encrypt(widget.sharedKey, plainText);
      if (encrypted != null) {
        payloadForServer = _crypto.bytesToHex(encrypted);
        payloadForDB = payloadForServer;
      } else {
        _showError("Encryption failed!");
        return;
      }
    } else {
      debugPrint('📸 Processing media (chat_detail) – content length: ${plainText.length}');

      final encrypted = await _crypto.encrypt(widget.sharedKey, plainText);
      if (encrypted == null) {
        debugPrint('❌ Encryption failed');
        _showError("Media encryption failed!");
        return;
      }
      debugPrint('📸 Encryption successful, encrypted length: ${encrypted.length}');

      String hexData = _crypto.bytesToHex(encrypted);
      debugPrint('📸 Hex length: ${hexData.length}');

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/upload_$messageId.enc');
      await tempFile.writeAsString(hexData);
      debugPrint('📸 Temp file written: ${tempFile.path}');

      _showSnack('Uploading media securely...', Colors.orange);
      String? serverFilename = await MediaService.uploadEncryptedFile(tempFile);
      debugPrint('📸 Server filename: $serverFilename');

      if (serverFilename == null) {
        _showError("Failed to upload media to secure server");
        return;
      }

      payloadForServer = serverFilename;
      payloadForDB = localFilePath ?? plainText;
    }

    _network.sendMessage(
      widget.contactName,
      type,
      payloadForServer,
      metadata: metadata,
      messageId: messageId,
      isHidden: isHidden,
      hiddenKey: hiddenKey,
    );

    int newMsgId = await _db.saveMessage(
      owner: widget.myUsername,
      contact: widget.contactName,
      sender: widget.myUsername,
      type: type,
      content: payloadForDB,
      isMe: true,
      metadata: metadata,
      messageId: messageId,
      status: 'sent',
      isHidden: isHidden,
      hiddenKey: hiddenKey,
    );

    if (!mounted) return;
    setState(() {
      _messages = List<Map<String, dynamic>>.from(_messages);
      _messages.add({
        'id': newMsgId,
        'content': type == 'TEXT' ? plainText : payloadForDB,
        'type': type,
        'isMe': true,
        'time': timestamp,
        'status': 'sent',
        'read': false,
        'delivered': false,
        'messageId': messageId,
        'isHidden': isHidden,
        'hiddenKey': hiddenKey,
      });
    });

    if (type != 'TEXT') {
      _decryptedMediaPaths[newMsgId] = payloadForDB;
    }
    _scrollToBottom();
  }

  void _onTextChanged() {
    if (_debounceTimer?.isActive ?? false) return;
    if (!_hasSentTyping) {
      _hasSentTyping = true;
      _network.sendMessage(widget.contactName, 'TYPING', '');
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(seconds: 2), () {
        _hasSentTyping = false;
      });
    }
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {});
  }

  void _handleIncomingTyping() {
    if (!mounted) return;
    setState(() => _isContactTyping = true);
    _typingTimer?.cancel();
    _typingDebounce?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isContactTyping = false);
    });
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Send to ${widget.contactName}',
              style: TextStyle(
                fontSize: 18,
                color: widget.isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _attachmentBtn(Icons.image, 'Gallery', Colors.purple, _pickImage),
                _attachmentBtn(Icons.camera_alt, 'Camera', Colors.blue, _pickCamera),
                _attachmentBtn(Icons.mic, 'Voice', Colors.red, _startVoiceRecording),
                _attachmentBtn(Icons.attach_file, 'File', Colors.orange, _pickDocument),
                _attachmentBtn(Icons.visibility_off, 'Stego', Colors.cyan, _showStegoDialog),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _attachmentBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: widget.isDark ? Colors.white70 : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (file != null) await _processImage(File(file.path));
  }

  Future<void> _pickCamera() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (file != null) await _processImage(File(file.path));
  }

  Future<void> _processImage(File file) async {
    try {
      _showSnack('Processing image...', Colors.orange);

      final bytes = await file.readAsBytes();

      final dir = await getApplicationDocumentsDirectory();
      final localDir = Directory('${dir.path}/veil_chat_files');
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final localPath = '${localDir.path}/sent_image_$timestamp.jpg';
      final localFile = File(localPath);
      await localFile.writeAsBytes(bytes);

      final base64 = base64Encode(bytes);

      _sendSecureData(base64, 'IMAGE', localFilePath: localPath);
    } catch (e) {
      debugPrint('❌ Image processing error: $e');
      _showError('Failed to process image: ${e.toString()}');
    }
  }

  Future<void> _pickDocument() async {
    final result = await _fileTransfer.pickFile();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path == null) return;
      final base64 = await _fileTransfer.encodeFile(file);

      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/veil_chat_files/sent_file_${file.name}';
      await File(localPath).create(recursive: true);
      await File(localPath).writeAsBytes(base64Decode(base64));

      _sendSecureData(
        base64,
        'FILE',
        localFilePath: localPath,
        metadata: {
          'filename': file.name,
          'size': file.size,
          'mimeType': _fileTransfer.getMimeType(file.name),
        },
      );
    }
  }

  Future<void> _startVoiceRecording() async {
    final started = await _sound.startRecording();
    if (started) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _recordingTime = 0;
      });
      _showRecordingOverlay();
    } else {
      _showError('Microphone permission required');
    }
  }

  void _showRecordingOverlay() {
    int _modalSeconds = 0;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) {
          _sound.recordingTimeStream.listen((s) {
            _modalSeconds = s;
            if (ctx2.mounted) setModal(() {});
          });
          return Container(
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              color: Color(0xE0000000),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  '${(_modalSeconds ~/ 60).toString().padLeft(2, '0')}:${(_modalSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white, fontSize: 36,
                    fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text('Recording...',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _circleBtn(Icons.close, Colors.white, () async {
                      await _sound.cancelRecording();
                      Navigator.pop(ctx2);
                      if (mounted) setState(() {
                        _isRecordingVoice = false;
                        _recordingTime = 0;
                      });
                    }),
                    _circleBtn(Icons.stop, Colors.red, () async {
                      final path = await _sound.stopRecording();
                      Navigator.pop(ctx2);
                      if (path != null) {
                        final base64 = await _sound.convertFileToBase64(path);
                        _sendSecureData(base64, 'AUDIO', localFilePath: path);
                      }
                      if (mounted) setState(() {
                        _isRecordingVoice = false;
                        _recordingTime = 0;
                      });
                    }),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, color: color),
      ),
    );
  }

  void _showStegoDialog() {
    final msgController = TextEditingController();
    final passController = TextEditingController();
    final themeColor = VeilTheme.accentColor;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1B2A), const Color(0xFF1A1040)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFF8F0FF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: themeColor.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: themeColor.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [themeColor, VeilTheme.neonPurple],
                  ),
                  boxShadow: [
                    BoxShadow(color: themeColor.withOpacity(0.4), blurRadius: 16),
                  ],
                ),
                child: const Icon(Icons.image_search_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Hide Message in Image',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your message will be invisibly embedded using LSB steganography',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 20),
              // Secret message field
              _stegoTextField(
                controller: msgController,
                label: 'Secret message',
                icon: Icons.message_rounded,
                maxLines: 3,
                isDark: widget.isDark,
                themeColor: themeColor,
              ),
              const SizedBox(height: 14),
              // Password field
              _stegoTextField(
                controller: passController,
                label: 'Encryption password',
                icon: Icons.key_rounded,
                obscure: true,
                isDark: widget.isDark,
                themeColor: themeColor,
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.white24),
                      ),
                    ),
                    child: Text('Cancel',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white54 : Colors.black45,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (msgController.text.trim().isEmpty) return;
                      if (passController.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
                      if (image == null) return;
                      final result = await _stego.embedMessage(
                        imageFile: File(image.path),
                        message: msgController.text,
                        password: passController.text,
                      );
                      if (result.success && result.file != null) {
                        final bytes = await result.file!.readAsBytes();
                        final base64Str = base64Encode(bytes);
                        _sendSecureData(
                          base64Str,
                          'IMAGE',
                          isHidden: 1,
                          hiddenKey: passController.text,
                          localFilePath: result.file!.path,
                        );
                      } else {
                        _showError(result.error ?? 'Stego embedding failed');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: themeColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                      shadowColor: themeColor.withOpacity(0.4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Embed & Send', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ]),
            ],
          ),
          ), // SingleChildScrollView
        ),
      ),
    );
  }

  /// Reusable styled text field for stego dialogs
  Widget _stegoTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    required Color themeColor,
    int maxLines = 1,
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: themeColor.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 12.0 : 0),
            child: Icon(icon, color: themeColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              maxLines: obscure ? 1 : maxLines,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: themeColor.withOpacity(0.7), fontSize: 13),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Extract hidden message from a stego image
  void _showExtractDialog(Map<String, dynamic> msg) {
    final passController = TextEditingController();
    final themeColor = VeilTheme.accentColor;
    final msgId = msg['id'] ?? 0;
    final path = _decryptedMediaPaths[msgId] ?? msg['content'] ?? '';

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1B2A), const Color(0xFF1A1040)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFF8F0FF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: VeilTheme.neonPurple.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: VeilTheme.neonPurple.withOpacity(0.2),
                blurRadius: 30,
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [VeilTheme.neonPurple, themeColor],
                  ),
                  boxShadow: [
                    BoxShadow(color: VeilTheme.neonPurple.withOpacity(0.4), blurRadius: 16),
                  ],
                ),
                child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Reveal Hidden Message',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter the password used to embed the message',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 20),
              _stegoTextField(
                controller: passController,
                label: 'Password',
                icon: Icons.key_rounded,
                obscure: true,
                isDark: widget.isDark,
                themeColor: VeilTheme.neonPurple,
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                    child: Text('Cancel',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white54 : Colors.black45,
                        fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (passController.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      if (!_isLikelyFilePath(path)) {
                        _showError('Image not downloaded yet. Please wait.');
                        return;
                      }
                      final result = await _stego.extractMessage(
                        imageFile: File(path),
                        password: passController.text.trim(),
                      );
                      if (mounted) {
                        if (result.success && result.message != null) {
                          _showExtractResult(result.message!);
                        } else {
                          _showError(result.error ?? 'Extraction failed — wrong password?');
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: VeilTheme.neonPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                      shadowColor: VeilTheme.neonPurple.withOpacity(0.4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Reveal', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showExtractResult(String message) {
    final themeColor = VeilTheme.accentColor;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1B2A), const Color(0xFF1A1040)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFF8F0FF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              Text('Hidden Message',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                )),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: SelectableText(
                  message,
                  style: TextStyle(
                    fontSize: 15,
                    color: widget.isDark ? Colors.white : Colors.black87,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message));
                      Navigator.pop(ctx);
                      _showSnack('Message copied', Colors.green);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.greenAccent.withOpacity(0.4)),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy_rounded, size: 15, color: Colors.greenAccent),
                        SizedBox(width: 6),
                        Text('Copy', style: TextStyle(color: Colors.greenAccent)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: themeColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }




  Future<void> _togglePin(int index) async {
    final msg = _messages[index];
    final msgId = msg['messageId']?.toString();
    if (msgId == null) return;
    final isPinned = msg['isPinned'] == 1;
    await _db.pinMessage(msgId, !isPinned);
    setState(() {
      _messages[index]['isPinned'] = isPinned ? 0 : 1;
    });
    await _loadPinnedMessages();
    _showSnack(
      isPinned ? 'Message unpinned' : 'Message pinned',
      isPinned ? Colors.grey : VeilTheme.accentColor,
    );
  }

  void _showForwardDialog(Map<String, dynamic> msg) {
    final themeColor = VeilTheme.accentColor;
    // Get available contacts from chat list
    _db.getLastMessages(widget.myUsername).then((contacts) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Forward to...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: contacts.isEmpty
                    ? Center(
                        child: Text('No contacts yet',
                          style: TextStyle(
                            color: widget.isDark ? Colors.white38 : Colors.black38)))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        itemBuilder: (_, i) {
                          final contact = contacts[i]['contact'] as String;
                          if (contact == widget.contactName) return const SizedBox.shrink();
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: themeColor.withOpacity(0.15),
                              child: Text(
                                contact[0].toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: themeColor,
                                ),
                              ),
                            ),
                            title: Text(contact,
                              style: TextStyle(
                                color: widget.isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.w600,
                              )),
                            onTap: () {
                              Navigator.pop(ctx);
                              _forwardMessage(msg, contact);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _forwardMessage(Map<String, dynamic> msg, String toContact) {
    final content = msg['content']?.toString() ?? '';
    if (content.isEmpty) return;
    // Send as new message to the target contact
    // We pass the already-encrypted hex content directly
    _network.sendMessage(
      toContact,
      'TEXT',
      content,
      metadata: {'forwarded': true, 'originalSender': widget.contactName},
    );
    _db.saveMessage(
      owner: widget.myUsername,
      contact: toContact,
      sender: widget.myUsername,
      type: 'TEXT',
      content: content,
      isMe: true,
      metadata: {'forwarded': true, 'originalSender': widget.contactName},
      messageId: DateTime.now().millisecondsSinceEpoch.toString(),
      status: 'sent',
    );
    _showSnack('Forwarded to $toContact', Colors.green);
  }

  Widget _msgActionBtn(BuildContext ctx, IconData icon, String label,
      VoidCallback onTap, {Color? color}) {
    final c2 = color ?? VeilTheme.accentColor;
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); onTap(); },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c2.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: c2, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 11, color: c2)),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(int index, bool forEveryone) async {
    final msg = _messages[index];
    final dbId = msg['id'] as int?;
    final messageId = msg['messageId']?.toString();

    if (dbId == null) return;

    // Delete locally from DB
    await _db.deleteMessage(dbId);

    // If delete for everyone and we sent it, tell the other person
    if (forEveryone && msg['isMe'] == true && messageId != null) {
      _network.sendMessage(
        widget.contactName,
        'DELETE_MSG',
        '',
        metadata: {'messageId': messageId},
      );
    }

    if (mounted) {
      setState(() => _messages.removeAt(index));
      _showSnack(forEveryone ? 'Deleted for everyone' : 'Deleted for you',
          Colors.grey);
    }
  }


  void _onScroll() {
    // Load older messages when scrolled to top
    if (_scrollController.position.pixels <= 80 &&
        !_isLoadingMore &&
        _hasMoreMessages) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;
    setState(() => _isLoadingMore = true);

    final data = await _db.getMessagesForContact(
      widget.myUsername,
      widget.contactName,
      limit: _pageSize,
      offset: _messageOffset,
    );

    if (!mounted) return;

    if (data.isEmpty || data.length < _pageSize) {
      setState(() => _hasMoreMessages = false);
    }

    if (data.isEmpty) {
      setState(() => _isLoadingMore = false);
      return;
    }

    // Decrypt new messages
    final futures = data.map((m) async {
      String displayContent = m['content'] ?? '';
      if (m['type'] == 'TEXT' && displayContent.isNotEmpty) {
        final msgKey = m['messageId']?.toString() ?? m['id'].toString();
        if (_decryptCache.containsKey(msgKey)) {
          displayContent = _decryptCache[msgKey]!;
        } else {
          try {
            final bytes = _crypto.hexToBytes(displayContent);
            final dec = await _crypto.decrypt(widget.sharedKey, bytes);
            displayContent = dec ?? '🔒 Decryption failed';
            if (dec != null) _decryptCache[msgKey] = dec;
          } catch (_) {
            displayContent = '🔒 Encrypted Message';
          }
        }
      }
      return {
        ...m,
        'content': displayContent,
        'isMe': m['isMe'] == 1,
        'read': m['read'] == 1,
      };
    });

    final older = await Future.wait(futures);

    // Save current scroll position so we don't jump
    final prevExtent = _scrollController.position.maxScrollExtent;

    setState(() {
      _messages = [...older, ..._messages];
      _messageOffset += data.length;
      _isLoadingMore = false;
    });

    // Restore scroll position after prepending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final newExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(newExtent - prevExtent);
      }
    });
  }

  void _showReactionMenu(int index) {
    HapticFeedback.heavyImpact();
    final msg = _messages[index];
    final isMe = msg['isMe'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _msgActionBtn(ctx, Icons.reply_rounded, 'Reply', () {
                  setState(() => _replyMsg = msg);
                }),
                _msgActionBtn(ctx, Icons.copy_rounded, 'Copy', () {
                  if (msg['type'] == 'TEXT') {
                    Clipboard.setData(ClipboardData(text: msg['content'] ?? ''));
                    _showSnack('Copied', Colors.grey);
                  }
                }),
                if (msg['type'] == 'TEXT')
                  _msgActionBtn(ctx, Icons.forward_rounded, 'Forward', () {
                    _showForwardDialog(msg);
                  }),
                _msgActionBtn(
                  ctx,
                  msg['isPinned'] == 1
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  msg['isPinned'] == 1 ? 'Unpin' : 'Pin',
                  () => _togglePin(index),
                  color: msg['isPinned'] == 1
                      ? Colors.orangeAccent
                      : VeilTheme.accentColor,
                ),
                _msgActionBtn(ctx, Icons.delete_outline_rounded, 'Delete for me',
                  () => _deleteMessage(index, false), color: Colors.orangeAccent),
                if (isMe)
                  _msgActionBtn(ctx, Icons.delete_forever_rounded, 'Delete for all',
                    () => _deleteMessage(index, true), color: Colors.redAccent),
              ],
            ),
            const Divider(height: 24),
            Text(
              'React',
              style: TextStyle(
                color: widget.isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: ['❤️', '😂', '😮', '😢', '👍', '🔥', '🎉', '😡', '🙏', '💯', '😍', '🤔']
                  .map((emoji) {
                    final isSelected = _messages[index]['reaction'] == emoji;
                    return GestureDetector(
                      onTap: () {
                        final messageId = _messages[index]['id'];
                        if (messageId != null) {
                          // Toggle off if already selected
                          final newVal = isSelected ? null : emoji;
                          _db.updateMessageReaction(messageId, newVal);
                          if (mounted) setState(() => _messages[index]['reaction'] = newVal);
                        }
                        Navigator.pop(ctx);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? VeilTheme.accentColor.withOpacity(0.2)
                              : (widget.isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.black.withOpacity(0.04)),
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(color: VeilTheme.accentColor, width: 1.5)
                              : null,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  })
                  .toList(),
            ),
            if (_messages[index]['reaction'] != null)
              TextButton(
                onPressed: () {
                  final messageId = _messages[index]['id'];
                  if (messageId != null) {
                    _db.updateMessageReaction(messageId, null);
                    if (mounted) {
                      setState(() => _messages[index]['reaction'] = null);
                    }
                  }
                  Navigator.pop(ctx);
                },
                child: Text(
                  'Remove Reaction',
                  style: TextStyle(color: Colors.red.withOpacity(0.8)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF101A26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear Chat?',
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
        ),
        content: Text(
          'This will permanently delete all messages with ${widget.contactName}.',
          style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteMessagesForContact(widget.myUsername, widget.contactName);
      _loadMessages();
      _showSnack('Chat cleared', Colors.green);
    }
  }


  Future<void> _toggleBlockContact() async {
    final isBlocking = !_isContactBlocked;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF101A26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isBlocking ? 'Block ${widget.contactName}?' : 'Unblock ${widget.contactName}?',
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
        ),
        content: Text(
          isBlocking
              ? 'They will not be able to send you messages or call you.'
              : 'They will be able to message and call you again.',
          style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL',
              style: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isBlocking ? 'BLOCK' : 'UNBLOCK',
              style: TextStyle(color: isBlocking ? Colors.red : Colors.green),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.toggleContactBlock(
          widget.myUsername, widget.contactName, isBlocking);
      if (mounted) {
        setState(() => _isContactBlocked = isBlocking);
        _showSnack(
          isBlocking
              ? '${widget.contactName} blocked'
              : '${widget.contactName} unblocked',
          isBlocking ? Colors.red : Colors.green,
        );
      }
    }
  }

  String? _currentPlayingId;

  Future<void> _toggleAudioPlayback(String content, String messageId) async {
    if (_playingAudioMessages[messageId] == true) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _playingAudioMessages[messageId] = false);
      return;
    }
    if (!_isLikelyFilePath(content)) {
      _showError('Audio file not ready yet');
      return;
    }
    try {
      // Stop any currently playing message
      if (_currentPlayingId != null && _currentPlayingId != messageId) {
        await _audioPlayer.stop();
        if (mounted) setState(() => _playingAudioMessages[_currentPlayingId!] = false);
      }
      _currentPlayingId = messageId;

      // Set up listeners once per play action
      _audioPlayer.onDurationChanged.listen((d) {
        if (mounted && _currentPlayingId == messageId) {
          setState(() => _audioDurations[messageId] = d);
        }
      });
      _audioPlayer.onPositionChanged.listen((p) {
        if (mounted && _currentPlayingId == messageId) {
          setState(() => _audioPositions[messageId] = p);
        }
      });
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() {
          _playingAudioMessages[messageId] = false;
          _currentPlayingId = null;
        });
      });

      await _audioPlayer.play(DeviceFileSource(content));
      if (mounted) setState(() => _playingAudioMessages[messageId] = true);
    } catch (e) {
      debugPrint('Audio play error: $e');
      _showError('Failed to play audio: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) setState(() => _showEmojiPicker = false);
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _onEmojiSelected(String emoji) {
    final text = _msgController.text;
    final selection = _msgController.selection;
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    _msgController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  bool _isLikelyFilePath(String path) {
    return path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:\\').hasMatch(path) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(path);
  }

  Future<void> _pickChatWallpaper() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      if (!mounted) return;
      setState(() {
        _contactBackgroundPath = file.path;
        VeilTheme.chatBgPath = file.path;
      });
      await _db.updateChatBackground(
        widget.myUsername,
        widget.contactName,
        file.path,
      );
      _showSnack('Chat wallpaper updated', Colors.green);
    }
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
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: (widget.isDark ? Colors.black : Colors.white).withOpacity(0.2),
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
        title: GestureDetector(
          onTap: () {},
          child: Row(
            children: [
              Hero(
                tag: "avatar-${widget.contactName}",
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: themeColor.withOpacity(0.2),
                  backgroundImage: (_contactAvatarPath != null &&
                          _contactAvatarPath!.isNotEmpty &&
                          File(_contactAvatarPath!).existsSync())
                      ? FileImage(File(_contactAvatarPath!)) as ImageProvider
                      : null,
                  child: (_contactAvatarPath == null ||
                          _contactAvatarPath!.isEmpty ||
                          !File(_contactAvatarPath!).existsSync())
                      ? Text(
                          widget.contactName[0].toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.contactName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (_isContactTyping)
                    _TypingDotsWidget(color: themeColor)
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7, height: 7,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: _isContactOnline
                                ? const Color(0xFF00FF88) : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          _isContactOnline
                              ? 'Online'
                              : _contactLastSeen > 0
                                  ? 'last seen ${_formatLastSeen(_contactLastSeen)}'
                                  : 'Offline',
                          style: TextStyle(
                            fontSize: 11,
                            color: _isContactOnline
                                ? const Color(0xFF00FF88)
                                : (widget.isDark
                                    ? Colors.white38 : Colors.black38),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.call_rounded, color: themeColor),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  contactName: widget.contactName,
                  isIncoming: false,
                  isDark: widget.isDark,
                  isAudioOnly: true,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.videocam_rounded, color: themeColor),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  contactName: widget.contactName,
                  isIncoming: false,
                  isDark: widget.isDark,
                  isAudioOnly: false,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: themeColor),
            onSelected: (val) {
              if (val == 'wallpaper') _pickChatWallpaper();
              if (val == 'clear') _clearChat();
              if (val == 'block') _toggleBlockContact();
              if (val == 'lock') _manageChatLock();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'wallpaper', child: Text('Set Chat Wallpaper')),
              PopupMenuItem(
                value: 'lock',
                child: Row(children: [
                  Icon(
                    _isChatLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                    size: 16,
                    color: VeilTheme.accentColor,
                  ),
                  const SizedBox(width: 8),
                  Text(_isChatLocked ? 'Remove Lock' : 'Lock Chat'),
                ]),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear Chat', style: TextStyle(color: Colors.red)),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  _isContactBlocked ? 'Unblock Contact' : 'Block Contact',
                  style: TextStyle(
                    color: _isContactBlocked ? Colors.green : Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_contactBackgroundPath != null)
            VeilBackground(isDark: widget.isDark, screenIndex: 99)
          else
            RepaintBoundary(
              child: CustomPaint(
                painter: DynamicChatPainter(
                  isDark: widget.isDark,
                  seed: widget.contactName,
                  themeColor: themeColor,
                  style: VeilTheme.currentWallpaper,
                ),
              ),
            ),
          SafeArea(
            bottom: false, // keyboard insets handled by viewInsets
            child: Column(
              children: [
                // Pinned messages banner
                if (_pinnedMessages.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(
                        () => _showPinnedPanel = !_showPinnedPanel),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: themeColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.push_pin_rounded,
                                  color: themeColor, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                '${_pinnedMessages.length} pinned '
                                'message\${_pinnedMessages.length > 1 ? "s" : ""}',
                                style: TextStyle(
                                    color: themeColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Icon(
                                _showPinnedPanel
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: themeColor, size: 16),
                            ],
                          ),
                          if (_showPinnedPanel) ...
                            _pinnedMessages.map((m) => Padding(
                              padding: const EdgeInsets.only(top: 6, left: 8),
                              child: Text(
                                m['content']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: widget.isDark
                                        ? Colors.white70
                                        : Colors.black54),
                              ),
                            )).toList(),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: themeColor))
                      : _messages.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              color: themeColor,
                              onRefresh: () async => _loadMessages(),
                              child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(15, 60, 15, 20),
                              itemCount: (_isSearching && _searchQuery.isNotEmpty
                                  ? _messages.where((m) => (m['content'] ?? '').toString().toLowerCase().contains(_searchQuery)).length
                                  : _messages.length) + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                // Spinner at top when loading older
                                if (_isLoadingMore && i == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Center(child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, color: themeColor))),
                                  );
                                }
                                final idx = _isLoadingMore ? i - 1 : i;
                                final msgs = _isSearching && _searchQuery.isNotEmpty
                                    ? _messages.where((m) => (m['content'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList()
                                    : _messages;
                                if (idx < 0 || idx >= msgs.length) return const SizedBox.shrink();
                                return _buildBubble(msgs[idx], idx);
                              },
                            )),
                ),
                // Blocked banner - shows instead of input when blocked
                if (_isContactBlocked)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block_rounded,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'You blocked ${widget.contactName}',
                          style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _toggleBlockContact,
                          child: const Text('Unblock',
                            style: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                else
                  _buildInputArea(themeColor),
                if (!_isContactBlocked && _showEmojiPicker)
                  _buildEmojiPicker(),
              ],
            ),
          ),
        ],
      ),
    );
  }


  String _formatLastSeen(int ms) {
    if (ms <= 0) return 'recently';
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 60000) return 'just now';
    if (diff < 3600000) {
      final mins = diff ~/ 60000;
      return '$mins min ago';
    }
    if (diff < 86400000) {
      final hrs = diff ~/ 3600000;
      return '$hrs hr ago';
    }
    if (diff < 604800000) {
      final days = diff ~/ 86400000;
      return '$days days ago';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final d = dt.day.toString().padLeft(2,'0');
    final mo = dt.month.toString().padLeft(2,'0');
    return '$d/$mo/${dt.year}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: widget.isDark ? Colors.white30 : Colors.black38,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              color: widget.isDark ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Send your first secure message to ${widget.contactName}',
            style: TextStyle(
              fontSize: 12,
              color: widget.isDark ? Colors.white30 : Colors.black38,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, int index) {
    final isMe = msg['isMe'] == true;
    final isImage = msg['type'] == 'IMAGE';
    final isAudio = msg['type'] == 'AUDIO';
    final isFile = msg['type'] == 'FILE';
    final isHidden = msg['isHidden'] == 1;
    final status = msg['status'] ?? 'sent';
    final dt = DateTime.fromMillisecondsSinceEpoch(msg['time'] ?? 0);
    final messageId = msg['messageId']?.toString() ?? '${msg['time']}_$index';
    final msgId = msg['id'] ?? 0;

    final String content = msg['content'] ?? '';
    final String displayPath = _decryptedMediaPaths[msgId] ?? content;

    final themeColor = VeilTheme.accentColor;

    return GestureDetector(
      onLongPress: () => _showReactionMenu(index),
      onDoubleTap: () {
        if (!isAudio && !isImage && !isFile) {
          Clipboard.setData(ClipboardData(text: content));
          _showSnack('Message copied', Colors.grey);
        }
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: EdgeInsets.all(isImage ? 8 : 14),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
                minWidth: 50,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? themeColor.withOpacity(0.25)
                    : (widget.isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.05)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe ? const Radius.circular(20) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(20),
                ),
                border: Border.all(
                  color: isMe
                      ? themeColor.withOpacity(0.3)
                      : Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (isImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: _buildImageContent(displayPath, index),
                    )
                  else if (isAudio)
                    _buildAudioContent(displayPath, messageId, index)
                  else if (isFile)
                    _buildFileContent(msg, displayPath, index)
                  else
                    Text(
                      content,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),

                  if (isHidden)
                    GestureDetector(
                      onTap: () => _showExtractDialog(msg),
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              themeColor.withOpacity(0.18),
                              VeilTheme.neonPurple.withOpacity(0.14),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: themeColor.withOpacity(0.5), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: themeColor.withOpacity(0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_open_rounded, size: 13, color: themeColor),
                            const SizedBox(width: 5),
                            Text(
                              'Tap to reveal hidden message',
                              style: TextStyle(
                                fontSize: 11,
                                color: themeColor,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('hh:mm a').format(dt),
                        style: TextStyle(
                          color: widget.isDark ? Colors.white38 : Colors.black38,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (isMe)
                        Icon(
                          status == 'read'
                              ? Icons.done_all
                              : status == 'delivered'
                                  ? Icons.done_all
                                  : Icons.done,
                          size: 12,
                          color: status == 'read'
                              ? Colors.blue
                              : (status == 'delivered'
                                  ? Colors.green
                                  : (widget.isDark ? Colors.white38 : Colors.black45)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (msg['reaction'] != null)
              Positioned(
                bottom: -10,
                right: isMe ? 8 : null,
                left: !isMe ? 8 : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.isDark
                          ? Colors.white12
                          : Colors.black12,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg['reaction'],
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(String path, int index) {
    if (path.isNotEmpty && _isLikelyFilePath(path)) {
      return GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(File(path)),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            width: 250,
            height: 250,
            errorBuilder: (_, __, ___) => _errorContainer(),
          ),
        ),
      );
    }
    // Loading / retry state
    return Container(
      width: 250,
      height: 250,
      color: Colors.black12,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _decryptMediaFile(_messages[index]);
              },
              child: const Text('Retry', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorContainer() {
    return Container(
      width: 250,
      height: 250,
      color: Colors.grey[800],
      child: const Center(child: Icon(Icons.broken_image, color: Colors.red)),
    );
  }

  Widget _buildAudioContent(String content, String id, int index) {
    final isPlaying = _playingAudioMessages[id] ?? false;
    final duration = _audioDurations[id] ?? Duration.zero;
    final position = _audioPositions[id] ?? Duration.zero;

    if (!_isLikelyFilePath(content)) {
      return Container(
        width: 250,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _decryptMediaFile(_messages[index]);
              },
              child: const Text('Retry Download', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _toggleAudioPlayback(content, id),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.isDark ? VeilTheme.accentColor : VeilTheme.holoPink,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice message',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        color: widget.isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (_, __) {
            final maxV = duration.inSeconds.toDouble().clamp(1.0, double.infinity);
            final curV = position.inSeconds.toDouble().clamp(0.0, maxV);
            return Slider(
              value: curV, min: 0, max: maxV,
              onChanged: (_) {},
              activeColor: widget.isDark ? VeilTheme.accentColor : VeilTheme.holoPink,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFileContent(Map<String, dynamic> msg, String path, int index) {
    final meta = msg['metadata'];
    final metadata = (meta is Map) ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
    // ✅ FIX: safely get filename from metadata regardless of key type
    final metaSafe = <String, dynamic>{};
    if (metadata is Map) metadata.forEach((k, v) => metaSafe[k.toString()] = v);
    String filename = metaSafe['filename']?.toString() ?? '';
    if (filename.isEmpty && path.contains('/')) {
      filename = path.split('/').last;
    }
    if (filename.isEmpty) filename = 'file';
    // Get real file size
    int size = (metadata['size'] as num?)?.toInt() ?? 0;
    if (size == 0 && _isLikelyFilePath(path)) {
      try { size = File(path).lengthSync(); } catch (_) {}
    }
    final sizeStr = size > 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : size > 0 ? '${(size / 1024).toStringAsFixed(1)} KB' : 'Unknown size';

    if (!_isLikelyFilePath(path)) {
      return Container(
        width: 250,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _decryptMediaFile(msg);
              },
              child: const Text('Retry Download', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
    }

    // Determine file type icon and color
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    final Color fileColor;
    final IconData fileIcon;
    if (['pdf'].contains(ext)) {
      fileColor = const Color(0xFFFF5252);
      fileIcon = Icons.picture_as_pdf_rounded;
    } else if (['doc', 'docx'].contains(ext)) {
      fileColor = const Color(0xFF2196F3);
      fileIcon = Icons.description_rounded;
    } else if (['xls', 'xlsx'].contains(ext)) {
      fileColor = const Color(0xFF4CAF50);
      fileIcon = Icons.table_chart_rounded;
    } else if (['zip', 'rar', '7z'].contains(ext)) {
      fileColor = const Color(0xFFFF9800);
      fileIcon = Icons.folder_zip_rounded;
    } else if (['mp3', 'm4a', 'wav', 'aac'].contains(ext)) {
      fileColor = const Color(0xFF9C27B0);
      fileIcon = Icons.audio_file_rounded;
    } else if (['mp4', 'mov', 'avi'].contains(ext)) {
      fileColor = const Color(0xFFE91E63);
      fileIcon = Icons.video_file_rounded;
    } else {
      fileColor = VeilTheme.accentColor;
      fileIcon = Icons.insert_drive_file_rounded;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withOpacity(0.07)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: fileColor.withOpacity(0.25), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            final file = File(path);
            if (!await file.exists()) {
              _showSnack('File not ready yet', Colors.orange);
              return;
            }
            if (_isImageFile(filename)) {
              if (!mounted) return;
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.black87,
                  insetPadding: EdgeInsets.zero,
                  child: Stack(children: [
                    InteractiveViewer(
                      panEnabled: true, minScale: 0.5, maxScale: 4.0,
                      child: Image.file(file, fit: BoxFit.contain)),
                    Positioned(top: 8, right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context))),
                  ]),
                ),
              );
            } else {
              final result = await OpenFile.open(path);
              if (result.type != ResultType.done) {
                await Share.shareXFiles([XFile(path)], text: 'Shared from VeilChat');
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              // File type icon with colored background
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: fileColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: fileColor.withOpacity(0.3))),
                child: Icon(fileIcon, color: fileColor, size: 22),
              ),
              const SizedBox(width: 12),
              // Filename and size
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filename,
                    style: TextStyle(
                      color: widget.isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(sizeStr,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white38 : Colors.black38,
                        fontSize: 11)),
                    const SizedBox(width: 6),
                    Container(width: 3, height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isDark ? Colors.white24 : Colors.black26)),
                    const SizedBox(width: 6),
                    Text(ext.toUpperCase(),
                      style: TextStyle(
                        color: fileColor, fontSize: 10,
                        fontWeight: FontWeight.bold)),
                  ]),
                ],
              )),
              // Action buttons
              Column(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () async {
                    final file = File(path);
                    if (await file.exists()) {
                      await Share.shareXFiles([XFile(path)], text: 'Shared from VeilChat');
                    }
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: (widget.isDark ? Colors.white : Colors.black).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.share_rounded,
                      size: 15,
                      color: widget.isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  bool _isImageFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  Widget _buildInputArea(Color themeColor) {
    return Padding(
      padding: EdgeInsets.fromLTRB(15, 0, 15,
          MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 30),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded, color: themeColor),
                  onPressed: _showAttachmentMenu,
                ),
                IconButton(
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                    color: themeColor,
                  ),
                  onPressed: _toggleEmojiPicker,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    focusNode: _focusNode,
                    style: TextStyle(
                      color: widget.isDark ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                    maxLines: 5,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(
                        color: widget.isDark ? Colors.white30 : Colors.black38,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) _sendMessage();
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.mic_rounded, color: themeColor),
                  onPressed: _startVoiceRecording,
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: themeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: themeColor.withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF050A15) : const Color(0xFFF2F6FF),
        border: Border(
          top: BorderSide(
            color: widget.isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Emojis',
                  style: TextStyle(
                    color: widget.isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _showEmojiPicker = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _emojis.length,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => _onEmojiSelected(_emojis[i]),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: widget.isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.03),
                  ),
                  child: Center(
                    child: Text(_emojis[i], style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DynamicChatPainter extends CustomPainter {
  final bool isDark;
  final String seed;
  final Color themeColor;
  final WallpaperStyle style;

  const DynamicChatPainter({
    required this.isDark,
    required this.seed,
    required this.themeColor,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed.hashCode);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = isDark ? const Color(0xFF02050A) : const Color(0xFFF8FAFC),
    );

    switch (style) {
      case WallpaperStyle.cosmos:
        _drawCosmos(canvas, size, rng);
        break;
      case WallpaperStyle.mesh:
        _drawMesh(canvas, size, rng);
        break;
      case WallpaperStyle.nebula:
        _drawNebula(canvas, size, rng);
        break;
      case WallpaperStyle.circuits:
        _drawCircuits(canvas, size, rng);
        break;
      case WallpaperStyle.aurora:
        _drawCosmos(canvas, size, rng);
        break;
      case WallpaperStyle.matrix:
        _drawMesh(canvas, size, rng);
        break;
    }
  }

  void _drawCosmos(Canvas canvas, Size size, Random rng) {
    for (int i = 0; i < 6; i++) {
      final orbPaint = Paint()
        ..color = themeColor.withOpacity(isDark ? 0.05 : 0.08)
        ;
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        100 + rng.nextDouble() * 200,
        orbPaint,
      );
    }
  }

  void _drawMesh(Canvas canvas, Size size, Random rng) {
    final p = Paint()
      ..color = themeColor.withOpacity(0.08)
      ..strokeWidth = 1.0;
    for (int i = 0; i < 20; i++) {
      canvas.drawLine(
        Offset(0, rng.nextDouble() * size.height),
        Offset(size.width, rng.nextDouble() * size.height),
        p,
      );
      canvas.drawLine(
        Offset(rng.nextDouble() * size.width, 0),
        Offset(rng.nextDouble() * size.width, size.height),
        p,
      );
    }
  }

  void _drawNebula(Canvas canvas, Size size, Random rng) {
    for (int i = 0; i < 3; i++) {
      final path = Path();
      path.moveTo(0, rng.nextDouble() * size.height);
      path.quadraticBezierTo(
        size.width / 2,
        rng.nextDouble() * size.height,
        size.width,
        rng.nextDouble() * size.height,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = themeColor.withOpacity(0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 180
          ,
      );
    }
  }

  void _drawCircuits(Canvas canvas, Size size, Random rng) {
    final p = Paint()
      ..color = themeColor.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < 12; i++) {
      double x = (rng.nextInt(10) * size.width / 10);
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
      double y = (rng.nextInt(20) * size.height / 20);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// Animated three-dot typing indicator — bounces up and down
class _TypingDotsWidget extends StatefulWidget {
  final Color color;
  const _TypingDotsWidget({required this.color});
  @override
  State<_TypingDotsWidget> createState() => _TypingDotsWidgetState();
}

class _TypingDotsWidgetState extends State<_TypingDotsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              // Each dot has a phase offset
              final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
              final bounce = phase < 0.5
                  ? phase * 2
                  : (1.0 - phase) * 2;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5,
                height: 5,
                transform: Matrix4.translationValues(0, -bounce * 5, 0),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.7 + bounce * 0.3),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

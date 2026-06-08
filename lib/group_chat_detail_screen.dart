import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/group_service.dart';
import 'services/network_service.dart';
import 'services/database_service.dart';
import 'services/crypto_service.dart';
import 'services/sound_service.dart';
import 'services/file_transfer_service.dart';
import 'services/stego_service.dart';
import 'services/media_service.dart';
import 'call_screen.dart';

class GroupChatDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final bool isDark;
  final String currentUser;
  final String sharedKey;

  const GroupChatDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.isDark,
    required this.currentUser,
    required this.sharedKey,
  });

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen>
    with SingleTickerProviderStateMixin {
  final GroupService _groupService = GroupService();
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
  List<String> _members = [];
  bool _isLoading = true;
  bool _isContactTyping = false;
  bool _showEmojiPicker = false;
  late String _currentUser;

  Timer? _typingTimer;
  Timer? _debounceTimer;

  bool _isRecordingVoice = false;
  Map<String, dynamic>? _replyMsg; // swipe-to-reply state
  Set<String> _onlineMembers = {};
  int _recordingTime = 0;

  Map<String, bool> _playingAudioMessages = {};
  Map<String, Duration> _audioDurations = {};
  Map<String, Duration> _audioPositions = {};

  StreamSubscription? _groupMessageSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _recordingTimeSub;
  StreamSubscription? _groupUpdateSub;

  final Map<int, String> _decryptedMediaPaths = {};
  final Set<int> _downloadingMedia = {}; // 🔥 TRACK DOWNLOADS

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
    _currentUser = widget.currentUser;
    if (_currentUser.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return;
    }
    _initGroup();
    _loadMessages();
    _setupListeners();
    // Mark group as read when opening
    _groupService.markGroupAsRead(widget.groupId);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _sendGroupReadReceipt());
    _focusNode.addListener(_onFocusChange);
    _msgController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _msgController.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _debounceTimer?.cancel();
    _groupMessageSub?.cancel();
    _typingSub?.cancel();
    _recordingTimeSub?.cancel();
    _groupUpdateSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }


  void _sendGroupReadReceipt() {
    final user = NetworkService().currentUser;
    if (user == null) return;
    _network.sendPacket('GRP_READ', {
      'groupId': widget.groupId,
      'reader': user,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _initGroup() async {
    final group = await _db.getGroup(_currentUser, widget.groupId);
    if (group != null && mounted) {
      setState(() {
        _members = List<String>.from(group['members']);
      });
    }
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    final messages = await _db.getGroupMessages(
      _currentUser,
      widget.groupId,
      limit: 200,
    );

    final unique = <String, Map<String, dynamic>>{};
    for (var msg in messages) {
      final key = msg['messageId'] ?? msg['timestamp'].toString();
      var modifiableMsg = Map<String, dynamic>.from(msg);

      String currentType = modifiableMsg['type'] ?? 'TEXT';
      String contentStr = modifiableMsg['content']?.toString() ?? '';

      bool isMe = modifiableMsg['isMe'] == 1 || modifiableMsg['isMe'] == true;
      modifiableMsg['isMe'] = isMe; // FIX: normalize to bool so _buildBubble works

      // An explicit media type must NEVER be treated as text — otherwise an
      // AUDIO/IMAGE/FILE message whose content is a server .enc filename ends
      // up shown as plain text (the raw filename) for several seconds.
      final bool isExplicitMedia =
          currentType == 'IMAGE' || currentType == 'AUDIO' || currentType == 'FILE';

      if (!isExplicitMedia &&
          (currentType == 'TEXT' || currentType == 'GRP_MSG') &&
          contentStr.isNotEmpty &&
          !isMe &&
          !_isLikelyFilePath(contentStr)) {
        try {
          final bytes = _crypto.hexToBytes(contentStr);
          final decrypted = await _crypto.decrypt(widget.sharedKey, bytes);
          if (decrypted != null) {
            modifiableMsg['content'] = decrypted;
            contentStr = decrypted;
            modifiableMsg['type'] = 'TEXT';
            currentType = 'TEXT';
          } else {
            modifiableMsg['content'] = '🔒 Decryption failed';
          }
        } catch (e) {
          // Not hex data, leave as is
        }
      }

      // Classify only generic GRP_MSG/TEXT messages by their content shape.
      if (!isExplicitMedia && (currentType == 'GRP_MSG' || currentType == 'TEXT')) {
        if (contentStr.contains('.jpg') || contentStr.contains('.png') || contentStr.contains('.jpeg')) {
          modifiableMsg['type'] = 'IMAGE';
        } else if (contentStr.contains('.m4a') || contentStr.contains('.mp3')) {
          modifiableMsg['type'] = 'AUDIO';
        } else if (contentStr.contains('grp_recv_') && (contentStr.contains('.dat') || contentStr.contains('.jpg') || contentStr.contains('.png'))) {
          modifiableMsg['type'] = 'IMAGE';
        }
      }

      unique[key] = modifiableMsg;
    }

    final deduped = unique.values.toList()
      ..sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));

    if (mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(deduped);
        _isLoading = false;
      });
      _scrollToBottom();
    }

    for (int i = 0; i < _messages.length; i++) {
      final type = _messages[i]['type'] ?? 'TEXT';
      final content = _messages[i]['content'] ?? '';

      if (type != 'TEXT' && !_isLikelyFilePath(content) && content.isNotEmpty) {
        _downloadGroupMedia(_messages[i], i);
      }
    }
  }

  Future<void> _downloadGroupMedia(Map<String, dynamic> msg, int index) async {
    final String serverFilename = msg['content'] ?? '';
    final int msgId = msg['id'] ?? 0;
    final String type = msg['type'] ?? 'TEXT';

    if (serverFilename.isEmpty || serverFilename.contains(' ') || serverFilename.contains('/')) return;

    if (_downloadingMedia.contains(msgId)) {
      debugPrint('📥 Already downloading msgId $msgId, skipping');
      return;
    }
    _downloadingMedia.add(msgId);

    debugPrint('📥 _downloadGroupMedia for msgId $msgId, serverFilename: $serverFilename');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final subDir = Directory('${dir.path}/veil_chat_files');
      if (!await subDir.exists()) await subDir.create(recursive: true);

      // Restore original filename/extension from metadata when available.
      final metaRaw = msg['metadata'];
      final metaMap = <String, dynamic>{};
      if (metaRaw is Map) {
        metaRaw.forEach((k, v) => metaMap[k.toString()] = v);
      }
      final origFilename = metaMap['filename']?.toString() ?? '';
      String saveBase;
      if (origFilename.isNotEmpty) {
        final safeName = origFilename.replaceAll(RegExp(r'[^\w._-]'), '_');
        saveBase = 'grp_recv_${msg['messageId'] ?? msgId}_$safeName';
      } else {
        final ext = type == 'IMAGE' ? '.jpg' : type == 'AUDIO' ? '.m4a' : '.dat';
        saveBase = 'grp_recv_${msg['messageId'] ?? msgId}$ext';
      }
      final savePath = '${subDir.path}/$saveBase';

      if (await File(savePath).exists()) {
        debugPrint('📥 File already exists: $savePath');
        if (mounted) {
          setState(() {
            _messages[index]['content'] = savePath;
            _decryptedMediaPaths[msgId] = savePath;
          });
        }
        _downloadingMedia.remove(msgId);
        return;
      }

      const maxRetries = 3;
      File? downloadedFile;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        debugPrint('📥 Download attempt $attempt for $serverFilename');
        final tempEncPath = '$savePath.enc$attempt';
        downloadedFile = await MediaService.downloadEncryptedFile(serverFilename, tempEncPath);

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
        debugPrint('❌ All download attempts failed for $serverFilename');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download media. Tap to retry.'), backgroundColor: Colors.orange),
          );
        }
        _downloadingMedia.remove(msgId);
        return;
      }

      debugPrint('📥 Downloaded file size: ${await downloadedFile.length()} bytes');
      String hexData = await downloadedFile.readAsString();
      hexData = hexData.trim();

      final encryptedBytes = _crypto.hexToBytes(hexData);
      debugPrint('📥 Encrypted bytes length: ${encryptedBytes.length} bytes');
      final decryptedBase64 = await _crypto.decrypt(widget.sharedKey, encryptedBytes);

      if (decryptedBase64 != null) {
        debugPrint('📥 Decryption successful, base64 length: ${decryptedBase64.length}');
        final clearBytes = base64Decode(decryptedBase64);
        debugPrint('📥 Final media bytes length: ${clearBytes.length}');

        final finalFile = File(savePath);
        await finalFile.writeAsBytes(clearBytes);
        await downloadedFile.delete();

        final db = await _db.database;
        await db.update('group_messages', {'content': finalFile.path}, where: 'id = ?', whereArgs: [msgId]);

        if (mounted) {
          setState(() {
            _messages[index]['content'] = finalFile.path;
            _decryptedMediaPaths[msgId] = finalFile.path;
          });
        }
      } else {
        debugPrint('❌ Decryption returned null – wrong key or corrupted data');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Decryption failed. Wrong key?'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Group Media download error: $e");
    } finally {
      _downloadingMedia.remove(msgId);
    }
  }

  void _setupListeners() {
    _groupMessageSub = _groupService.groupMessageStream.listen((data) {
      if (!mounted) return;
      if (data['groupId'] == widget.groupId) {
        // ✅ FIX: reload and scroll to bottom so new message is immediately visible
        _loadMessages().then((_) {
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 120), () {
              if (mounted && _scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        });
      }
    });

    _typingSub = _network.messageStream.listen((data) {
      if (!mounted) return;
      // Track online members
      if (data['sender'] != null) {
        setState(() => _onlineMembers.add(data['sender'].toString()));
      }
      // Group read receipt
      if (data['type'] == 'GRP_READ' &&
          data['groupId'] == widget.groupId) {
        final reader = data['reader']?.toString() ?? '';
        if (reader.isNotEmpty && reader != _currentUser) {
          setState(() => _onlineMembers.add(reader));
        }
        return;
      }
      // Remote group message delete
      if (data['type'] == 'GRP_DELETE_MSG' &&
          data['groupId'] == widget.groupId) {
        final delId = data['messageId']?.toString();
        if (delId != null) {
          setState(() => _messages.removeWhere(
              (m) => m['messageId']?.toString() == delId));
        }
        return;
      }
      if (data['type'] == 'GROUP_TYPING' &&
          data['groupId'] == widget.groupId &&
          data['sender'] != _currentUser) {
        _handleIncomingTyping();
      }
    });

    _recordingTimeSub = _sound.recordingTimeStream.listen((seconds) {
      if (mounted && _isRecordingVoice) {
        setState(() => _recordingTime = seconds);
      }
    });

    // Live-refresh the member list when members are added/removed.
    _groupUpdateSub = _groupService.groupUpdateStream.listen((group) {
      if (!mounted) return;
      if (group.id == widget.groupId) {
        setState(() => _members = List<String>.from(group.members));
      }
    });
  }

  Future<void> _sendSecureData(
    String content,
    String type, {
    Map<String, dynamic>? metadata,
    int isHidden = 0,
    String? hiddenKey,
    String? localFilePath,
  }) async {
    HapticFeedback.lightImpact();
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    String payloadForServer = content;
    String payloadForDB = localFilePath ?? content;

    if (type == 'TEXT') {
      final encrypted = await _crypto.encrypt(widget.sharedKey, content);
      if (encrypted != null) {
        payloadForServer = _crypto.bytesToHex(encrypted);
      } else {
        _showError("Encryption failed!");
        return;
      }
    } else if (localFilePath != null) {
      debugPrint('📸 Processing media file: $localFilePath');

      File localFile = File(localFilePath);
      if (!await localFile.exists()) {
        debugPrint('❌ File does not exist: $localFilePath');
        _showError("File not found!");
        return;
      }

      List<int> bytes = await localFile.readAsBytes();
      debugPrint('📸 File size: ${bytes.length} bytes');

      String base64String = base64Encode(bytes);
      debugPrint('📸 Base64 length: ${base64String.length}');

      final encrypted = await _crypto.encrypt(widget.sharedKey, base64String);
      if (encrypted == null) {
        debugPrint('❌ Encryption returned null');
        _showError("Media encryption failed!");
        return;
      }
      debugPrint('📸 Encryption successful');

      String hexData = _crypto.bytesToHex(encrypted);
      debugPrint('📸 Hex length: ${hexData.length}');

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/grp_upload_$messageId.enc');
      await tempFile.writeAsString(hexData);
      debugPrint('📸 Temp file written: ${tempFile.path}');

      _showSnack('Uploading secure media...', Colors.orange);
      String? serverFilename = await MediaService.uploadEncryptedFile(tempFile);
      debugPrint('📸 Server response: $serverFilename');

      if (serverFilename == null) {
        debugPrint('❌ Upload returned null filename');
        _showError("Failed to upload media to secure server");
        return;
      }

      payloadForServer = serverFilename;
      payloadForDB = localFilePath;
    }

    _network.sendPacket('GRP_MSG', {
      'groupId': widget.groupId,
      'type': type,
      'content': payloadForServer,
      'extra': null,
      'metadata': metadata,
      'messageId': messageId,
      'sender': _currentUser,
      'timestamp': timestamp,
      'isHidden': isHidden,
      'hiddenKey': hiddenKey,
    });

    int newMsgId = await _db.saveGroupMessage(
      accountOwner: _currentUser,
      groupId: widget.groupId,
      sender: _currentUser,
      type: type,
      content: payloadForDB,
      isMe: true,
      messageId: messageId,
      timestamp: timestamp,
      isHidden: isHidden,
      hiddenKey: hiddenKey,
      metadata: metadata,
    );

    if (mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(_messages);
        _messages.add({
          'id': newMsgId,
          'content': payloadForDB,
          'type': type,
          'isMe': true,
          'sender': _currentUser,
          'timestamp': timestamp,
          'status': 'sent',
          'read': false,
          'delivered': false,
          'messageId': messageId,
          'isHidden': isHidden,
          'hiddenKey': hiddenKey,
          'metadata': metadata,
        });
        if (type != 'TEXT') {
          _decryptedMediaPaths[newMsgId] = payloadForDB;
        }
      });
      _scrollToBottom();
    }
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty) return;
    _sendSecureData(_msgController.text.trim(), 'TEXT');
    _msgController.clear();
  }

  void _onTextChanged() {
    if (_debounceTimer?.isActive ?? false) return;
    _network.sendPacket('GRP_TYPING', {
      'groupId': widget.groupId,
      'sender': _currentUser,
    });
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {});
  }

  void _handleIncomingTyping() {
    if (!mounted) return;
    setState(() => _isContactTyping = true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isContactTyping = false);
    });
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
    if (_focusNode.hasFocus) {
      setState(() => _showEmojiPicker = false);
    }
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  String _formatTimestamp(int timestamp) {
    return DateFormat('hh:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
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
              'Send to Group',
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

  bool _isLikelyFilePath(String path) {
    return path.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 30,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (file != null) await _processImage(File(file.path));
  }

  Future<void> _pickCamera() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 30,
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
      final localPath = '${localDir.path}/grp_sent_image_$timestamp.jpg';
      final localFile = File(localPath);
      await localFile.writeAsBytes(bytes);

      final base64 = base64Encode(bytes);

      _sendSecureData(base64, 'IMAGE', localFilePath: localPath);
    } catch (e) {
      debugPrint('❌ Group image processing error: $e');
      _showError('Failed to process image: ${e.toString()}');
    }
  }

  Future<void> _pickDocument() async {
    final result = await _fileTransfer.pickFile();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/veil_chat_files/grp_sent_${file.name}';
      await File(localPath).create(recursive: true);
      await File(file.path!).copy(localPath);

      _sendSecureData(
        '',
        'FILE',
        localFilePath: localPath,
        metadata: {
          'filename': file.name,
          'size': file.size,
          'mimeType': _fileTransfer.getMimeType(file.name),
        },
      );
      // NOTE: do NOT Navigator.pop here — it was kicking the user out of the
      // group chat after sending a file.
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
    StreamSubscription? modalSub;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) {
          // Subscribe only once (not on every rebuild) to avoid leaking subs.
          modalSub ??= _sound.recordingTimeStream.listen((s) {
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
                      await modalSub?.cancel();
                      modalSub = null;
                      Navigator.pop(ctx2);
                      if (mounted) setState(() {
                        _isRecordingVoice = false;
                        _recordingTime = 0;
                      });
                    }),
                    _circleBtn(Icons.stop, Colors.red, () async {
                      final path = await _sound.stopRecording();
                      await modalSub?.cancel();
                      modalSub = null;
                      Navigator.pop(ctx2);
                      if (path != null) {
                        final audioBase64 = await _sound.convertFileToBase64(path);
                        if (audioBase64.isNotEmpty) {
                          _sendSecureData(audioBase64, 'AUDIO', localFilePath: path);
                        } else {
                          _showError('Voice recording failed');
                        }
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
            boxShadow: [BoxShadow(color: themeColor.withOpacity(0.15), blurRadius: 30)],
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [themeColor, VeilTheme.neonPurple]),
                  boxShadow: [BoxShadow(color: themeColor.withOpacity(0.4), blurRadius: 16)],
                ),
                child: const Icon(Icons.image_search_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text('Hide Message in Image',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text('Invisibly embedded using LSB steganography',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12,
                  color: widget.isDark ? Colors.white38 : Colors.black38)),
              const SizedBox(height: 20),
              _stegoTextField(controller: msgController, label: 'Secret message',
                icon: Icons.message_rounded, maxLines: 3,
                isDark: widget.isDark, themeColor: themeColor),
              const SizedBox(height: 14),
              _stegoTextField(controller: passController, label: 'Encryption password',
                icon: Icons.key_rounded, obscure: true,
                isDark: widget.isDark, themeColor: themeColor),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Colors.white24))),
                    child: Text('Cancel', style: TextStyle(
                      color: widget.isDark ? Colors.white54 : Colors.black45,
                      fontWeight: FontWeight.w600)),
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
                        _sendSecureData('', 'IMAGE',
                          isHidden: 1, hiddenKey: passController.text,
                          localFilePath: result.file!.path);
                      } else {
                        _showError(result.error ?? 'Stego embedding failed');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: themeColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      shadowColor: themeColor.withOpacity(0.4), elevation: 4),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Embed & Send', style: TextStyle(fontWeight: FontWeight.bold)),
                      ]),
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
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: themeColor.withOpacity(0.7), fontSize: 13),
                border: InputBorder.none),
            ),
          ),
        ],
      ),
    );
  }

  void _showExtractDialog(Map<String, dynamic> msg) {
    final passController = TextEditingController();
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
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1B2A), const Color(0xFF1A1040)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFF8F0FF)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: VeilTheme.neonPurple.withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: VeilTheme.neonPurple.withOpacity(0.2), blurRadius: 30)],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [VeilTheme.neonPurple, VeilTheme.accentColor]),
                  boxShadow: [BoxShadow(color: VeilTheme.neonPurple.withOpacity(0.4), blurRadius: 16)],
                ),
                child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 14),
              Text('Reveal Hidden Message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text('Enter the password used to hide the message', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12,
                  color: widget.isDark ? Colors.white38 : Colors.black38)),
              const SizedBox(height: 20),
              _stegoTextField(controller: passController, label: 'Password',
                icon: Icons.key_rounded, obscure: true,
                isDark: widget.isDark, themeColor: VeilTheme.neonPurple),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Colors.white24))),
                    child: Text('Cancel', style: TextStyle(
                      color: widget.isDark ? Colors.white54 : Colors.black45,
                      fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (passController.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      if (!_isLikelyFilePath(path)) {
                        _showError('Image not downloaded yet.');
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      shadowColor: VeilTheme.neonPurple.withOpacity(0.4), elevation: 4),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Reveal', style: TextStyle(fontWeight: FontWeight.bold)),
                      ]),
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
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1B2A), const Color(0xFF0D2010)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFEEFFF4)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              Text('Hidden Message',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3))),
                child: SelectableText(message,
                  style: TextStyle(fontSize: 15, height: 1.5,
                    color: widget.isDark ? Colors.white : Colors.black87)),
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
                        side: BorderSide(color: Colors.greenAccent.withOpacity(0.4)))),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy_rounded, size: 15, color: Colors.greenAccent),
                        SizedBox(width: 6),
                        Text('Copy', style: TextStyle(color: Colors.greenAccent))]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: themeColor, foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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

  void _showReactionMenu(int index) {
    HapticFeedback.heavyImpact();
    final msg = _messages[index];
    final isMe = msg['sender'] == _currentUser;
    final themeColor = VeilTheme.accentColor;

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
            // Drag handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _grpActionBtn(ctx, Icons.reply_rounded, 'Reply', () {
                  setState(() => _replyMsg = msg);
                }),
                if (msg['type'] == 'TEXT')
                  _grpActionBtn(ctx, Icons.copy_rounded, 'Copy', () {
                    Clipboard.setData(ClipboardData(text: msg['content'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')));
                  }),
                if (msg['type'] == 'TEXT')
                  _grpActionBtn(ctx, Icons.forward_rounded, 'Forward', () {
                    _showGroupForwardDialog(msg);
                  }),
                _grpActionBtn(ctx, Icons.delete_outline_rounded, 'Delete for me',
                  () => _deleteGroupMessage(index, false),
                  color: Colors.orangeAccent),
                if (isMe)
                  _grpActionBtn(ctx, Icons.delete_forever_rounded, 'Delete for all',
                    () => _deleteGroupMessage(index, true),
                    color: Colors.redAccent),
              ],
            ),
            const Divider(height: 24),
            // Emoji reactions
            Text('React', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              color: widget.isDark ? Colors.white54 : Colors.black45)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: ['❤️', '😂', '😮', '😢', '👍', '🔥', '🎉', '😡', '🙏', '💯', '😍', '🤔']
                  .map((emoji) {
                    final isSelected = _messages[index]['reaction'] == emoji;
                    return GestureDetector(
                      onTap: () {
                        final messageId = _messages[index]['messageId'];
                        if (messageId != null) {
                          final newVal = isSelected ? null : emoji;
                          _network.sendPacket('GROUP_REACTION', {
                            'groupId': widget.groupId,
                            'messageId': messageId,
                            'reaction': newVal,
                            'sender': _currentUser,
                          });
                          if (mounted) setState(() => _messages[index]['reaction'] = newVal);
                        }
                        Navigator.pop(ctx);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? themeColor.withOpacity(0.2)
                              : (widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04)),
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected ? Border.all(color: themeColor, width: 1.5) : null,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grpActionBtn(BuildContext ctx, IconData icon, String label,
      VoidCallback onTap, {Color? color}) {
    final c = color ?? VeilTheme.accentColor;
    return GestureDetector(
      onTap: () { Navigator.pop(ctx); onTap(); },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 10, color: c)),
        ],
      ),
    );
  }

  Future<void> _deleteGroupMessage(int index, bool forEveryone) async {
    final msg = _messages[index];
    final dbId = msg['id'] as int?;
    final messageId = msg['messageId']?.toString();
    if (dbId == null) return;

    // Delete from local DB
    final db = DatabaseService();
    await db.database.then((d) => d.delete(
      'group_messages', where: 'id = ?', whereArgs: [dbId]));

    // Delete for everyone via server
    if (forEveryone && msg['sender'] == _currentUser && messageId != null) {
      _network.sendPacket('GRP_DELETE_MSG', {
        'groupId': widget.groupId,
        'messageId': messageId,
        'sender': _currentUser,
      });
    }

    if (mounted) {
      setState(() => _messages.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(forEveryone ? 'Deleted for everyone' : 'Deleted for you'),
        backgroundColor: Colors.grey));
    }
  }

  void _showGroupForwardDialog(Map<String, dynamic> msg) {
    final themeColor = VeilTheme.accentColor;
    DatabaseService().getLastMessages(_currentUser).then((contacts) {
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
              Text('Forward to...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (_, i) {
                    final contact = contacts[i]['contact'] as String;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: themeColor.withOpacity(0.15),
                        child: Text(contact[0].toUpperCase(),
                          style: TextStyle(color: themeColor, fontWeight: FontWeight.bold))),
                      title: Text(contact,
                        style: TextStyle(
                          color: widget.isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(ctx);
                        NetworkService().sendMessage(contact, 'TEXT', msg['content'] ?? '',
                          metadata: {'forwarded': true, 'originalSender': msg['sender']});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Forwarded to $contact'),
                            backgroundColor: Colors.green));
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

  void _showGroupInfo() {
    final themeColor = VeilTheme.accentColor;
    final grpObj = GroupService().getGroup(widget.groupId);
    final groupOwner = grpObj?.owner ?? '';
    final isOwner = _currentUser == groupOwner;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1117), const Color(0xFF161B2E)]
                  : [const Color(0xFFF8F9FF), const Color(0xFFEEF2FF)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: themeColor.withOpacity(0.25), width: 1.5),
            boxShadow: [BoxShadow(color: themeColor.withOpacity(0.12), blurRadius: 40)],
          ),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [themeColor.withOpacity(0.12), VeilTheme.neonPurple.withOpacity(0.08)]),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Row(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [themeColor, VeilTheme.neonPurple]),
                      boxShadow: [BoxShadow(color: themeColor.withOpacity(0.4), blurRadius: 12)],
                    ),
                    child: Center(
                      child: Text(widget.groupName[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.groupName,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                          color: widget.isDark ? Colors.white : Colors.black87)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.people_rounded, size: 13, color: themeColor),
                        const SizedBox(width: 4),
                        Text('${_members.length} members',
                          style: TextStyle(fontSize: 12, color: themeColor)),
                      ]),
                    ]),
                  ),
                  if (isOwner)
                    GestureDetector(
                      onTap: () { Navigator.pop(ctx); _showAddMemberDialog(); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [themeColor.withOpacity(0.8), themeColor]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: themeColor.withOpacity(0.3), blurRadius: 8)],
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_add_rounded, color: Colors.black, size: 14),
                          SizedBox(width: 5),
                          Text('Add', style: TextStyle(color: Colors.black,
                            fontSize: 12, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                ]),
              ),
              // Member list
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _members.length,
                  itemBuilder: (ctx2, i) {
                    final m = _members[i];
                    final isOnline = _onlineMembers.contains(m);
                    final isThisOwner = m == groupOwner;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: (widget.isDark ? Colors.white : Colors.black).withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isThisOwner
                              ? themeColor.withOpacity(0.3)
                              : Colors.transparent),
                      ),
                      child: Row(children: [
                        Stack(children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isThisOwner
                                ? themeColor.withOpacity(0.2)
                                : (widget.isDark ? Colors.white12 : Colors.black.withOpacity(0.08)),
                            child: Text(m[0].toUpperCase(),
                              style: TextStyle(
                                color: isThisOwner ? themeColor : (widget.isDark ? Colors.white70 : Colors.black54),
                                fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                color: isOnline ? const Color(0xFF00FF88) : Colors.grey.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: widget.isDark ? const Color(0xFF0D1117) : Colors.white,
                                  width: 2)),
                            ),
                          ),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m, style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14,
                              color: widget.isDark ? Colors.white : Colors.black87)),
                            Row(children: [
                              if (isThisOwner) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: themeColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8)),
                                  child: Text('Owner',
                                    style: TextStyle(fontSize: 9, color: themeColor,
                                      fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.grey.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8)),
                                child: Text(isOnline ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isOnline ? Colors.greenAccent : Colors.grey,
                                    fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ],
                        )),
                        if (isOwner && m != _currentUser)
                          GestureDetector(
                            onTap: () { Navigator.pop(ctx); _confirmRemoveMember(m); },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.person_remove_rounded,
                                color: Colors.redAccent, size: 17),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
              ),
              // Footer actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: widget.isDark ? Colors.white24 : Colors.black12))),
                      child: Text('Close',
                        style: TextStyle(
                          color: widget.isDark ? Colors.white60 : Colors.black54,
                          fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(ctx); _confirmLeaveGroup(); },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: Colors.red.withOpacity(0.15),
                        foregroundColor: Colors.redAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.red, width: 0.8))),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.exit_to_app_rounded, size: 15),
                          SizedBox(width: 6),
                          Text('Leave Group', style: TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          ), // SingleChildScrollView
        ),
      ),
    );
  }

  void _showAddMemberDialog() {
    final controller = TextEditingController();
    final themeColor = VeilTheme.accentColor;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: widget.isDark
                  ? [const Color(0xFF0D1117), const Color(0xFF161B2E)]
                  : [const Color(0xFFF8F9FF), const Color(0xFFEEF2FF)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: themeColor.withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: themeColor.withOpacity(0.15), blurRadius: 30)],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [themeColor, themeColor.withOpacity(0.6)]),
                  boxShadow: [BoxShadow(color: themeColor.withOpacity(0.35), blurRadius: 14)],
                ),
                child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 14),
              Text('Add Member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text('Invite someone to join this group', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12,
                  color: widget.isDark ? Colors.white38 : Colors.black38)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: (widget.isDark ? Colors.white : Colors.black).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: themeColor.withOpacity(0.2))),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(children: [
                  Icon(Icons.person_search_rounded, color: themeColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : Colors.black87, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Enter username',
                        hintStyle: TextStyle(
                          color: widget.isDark ? Colors.white30 : Colors.black38),
                        border: InputBorder.none,
                        labelStyle: TextStyle(color: themeColor.withOpacity(0.7))),
                    ),
                  ),
                ]),
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
                        side: BorderSide(color: widget.isDark ? Colors.white24 : Colors.black12))),
                    child: Text('Cancel', style: TextStyle(
                      color: widget.isDark ? Colors.white54 : Colors.black45,
                      fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final username = controller.text.trim();
                      if (username.isNotEmpty) {
                        _network.sendPacket('GRP_ADD_MEMBER', {
                          'groupId': widget.groupId,
                          'member': username,
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(children: [
                              const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text('Added $username to group'),
                            ]),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: themeColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      shadowColor: themeColor.withOpacity(0.4), elevation: 4),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add_rounded, size: 15),
                        SizedBox(width: 6),
                        Text('Add Member', style: TextStyle(fontWeight: FontWeight.bold)),
                      ]),
                  ),
                ),
              ]),
            ],
          ),
        ),
    ),
    );
  }

  void _confirmRemoveMember(String member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
        title: Text('Remove $member?',
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black)),
        content: Text('Remove $member from the group?',
          style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              _network.sendPacket('GRP_REMOVE_MEMBER', {
                'groupId': widget.groupId,
                'member': member,
              });
              Navigator.pop(ctx);
            },
            child: const Text('REMOVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave "${widget.groupName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              _groupService.leaveGroup(widget.groupId);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('LEAVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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

  String? _currentPlayingId;

  Future<void> _toggleAudioPlayback(String content, String id) async {
    if (_playingAudioMessages[id] == true) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _playingAudioMessages[id] = false);
      return;
    }
    if (!_isLikelyFilePath(content)) {
      _showError('Audio not ready yet - please wait');
      return;
    }
    try {
      if (_currentPlayingId != null && _currentPlayingId != id) {
        await _audioPlayer.stop();
        if (mounted) setState(() => _playingAudioMessages[_currentPlayingId!] = false);
      }
      _currentPlayingId = id;
      _audioPlayer.onDurationChanged.listen((d) {
        if (mounted && _currentPlayingId == id) setState(() => _audioDurations[id] = d);
      });
      _audioPlayer.onPositionChanged.listen((p) {
        if (mounted && _currentPlayingId == id) setState(() => _audioPositions[id] = p);
      });
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() {
          _playingAudioMessages[id] = false;
          _currentPlayingId = null;
        });
      });
      await _audioPlayer.play(DeviceFileSource(content));
      if (mounted) setState(() => _playingAudioMessages[id] = true);
    } catch (e) {
      debugPrint('Group audio error: $e');
      _showError('Failed to play audio: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

  void _onEmojiSelected(String emoji) {
    final text = _msgController.text;
    final selection = _msgController.selection;
    final newText = text.replaceRange(
      selection.start >= 0 ? selection.start : text.length,
      selection.end >= 0 ? selection.end : text.length,
      emoji,
    );
    _msgController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (selection.start >= 0 ? selection.start : text.length) + emoji.length,
      ),
    );
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
          onTap: _showGroupInfo,
          child: Row(
            children: [
              Hero(
                tag: 'group-${widget.groupId}',
                child: CircleAvatar(
                  backgroundColor: themeColor.withOpacity(0.2),
                  child: Text(
                    widget.groupName[0].toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: widget.isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    if (_isContactTyping)
                      Text(
                        'someone is typing...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: themeColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: themeColor),
            onSelected: (value) {
              if (value == 'info') _showGroupInfo();
              if (value == 'leave') _confirmLeaveGroup();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'info', child: Text('Group Info')),
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave Group', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _GroupChatBackgroundPainter(
              isDark: widget.isDark,
              seed: widget.groupId,
              themeColor: themeColor,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: themeColor))
                      : _messages.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(15, 60, 15, 20),
                              itemCount: _messages.length,
                              itemBuilder: (ctx, i) => _buildBubble(_messages[i], i),
                            ),
                ),
                _buildInputArea(themeColor),
                if (_showEmojiPicker) _buildEmojiPicker(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 60,
            color: widget.isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 20),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              color: widget.isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Be the first to say hello!',
            style: TextStyle(
              fontSize: 14,
              color: widget.isDark ? Colors.white30 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, int index) {
    final isMe = msg['isMe'] == true || msg['isMe'] == 1;
    final type = msg['type'] ?? 'TEXT';
    final content = msg['content'] ?? '';
    final isImage = type == 'IMAGE';
    final isAudio = type == 'AUDIO';
    final isFile = type == 'FILE';
    final isHidden = msg['isHidden'] == 1;
    final sender = msg['sender'] ?? 'Unknown';
    final timestamp = msg['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
    final messageId = msg['messageId']?.toString() ?? '${timestamp}_$index';
    final msgId = msg['id'] ?? 0;
    final displayPath = _decryptedMediaPaths[msgId] ?? content;
    final themeColor = VeilTheme.accentColor;

    return GestureDetector(
      onLongPress: () => _showReactionMenu(index),
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
                minWidth: 80,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? themeColor.withOpacity(0.2)
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
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        sender,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                        ),
                      ),
                    ),
                  if (isImage)
                    _buildImageContent(displayPath, index)
                  else if (isAudio)
                    _buildAudioContent(displayPath, messageId, index)
                  else if (isFile)
                    _buildFileContent(msg, index)
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
                        _formatTimestamp(timestamp),
                        style: TextStyle(
                          color: widget.isDark ? Colors.white38 : Colors.black38,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.done_all,
                            size: 12,
                            color: widget.isDark ? Colors.white30 : Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (msg['reaction'] != null)
              Positioned(
                bottom: -5,
                right: isMe ? 0 : null,
                left: !isMe ? 0 : null,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(msg['reaction'], style: const TextStyle(fontSize: 12)),
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
          borderRadius: BorderRadius.circular(12),
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
    // Loading/downloading state
    return Container(
      width: 220,
      height: 180,
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF1A2332)
            : const Color(0xFFEEF0F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: VeilTheme.accentColor.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined,
            size: 40,
            color: widget.isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 10),
          SizedBox(
            width: 80,
            child: LinearProgressIndicator(
              backgroundColor: VeilTheme.accentColor.withOpacity(0.1),
              color: VeilTheme.accentColor,
              minHeight: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text('Downloading...',
            style: TextStyle(
              fontSize: 11,
              color: widget.isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _downloadGroupMedia(_messages[index], index),
            child: Text('Retry',
              style: TextStyle(
                fontSize: 11,
                color: VeilTheme.accentColor,
                decoration: TextDecoration.underline)),
          ),
        ],
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
                _downloadGroupMedia(_messages[index], index);
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
          Slider(
            value: position.inSeconds.toDouble(),
            min: 0,
            max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
            onChanged: (_) {},
            activeColor: widget.isDark ? VeilTheme.accentColor : VeilTheme.holoPink,
          ),
        ],
      ),
    );
  }

  Widget _buildFileContent(Map<String, dynamic> msg, int index) {
    final metadata = msg['metadata'] ?? {};
    final meta2 = (metadata is Map) ? metadata : {};
    String filename = (meta2['filename'] as String?) ?? '';
    final content2 = msg['content']?.toString() ?? '';
    if (filename.isEmpty && content2.contains('/')) filename = content2.split('/').last;
    if (filename.isEmpty) filename = 'file';
    int size = (meta2['size'] as num?)?.toInt() ?? 0;
    final String sizeStr = size > 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : size > 0 ? '${(size / 1024).toStringAsFixed(1)} KB' : 'Unknown size';

    final String content = msg['content'] ?? '';

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
                _downloadGroupMedia(msg, index);
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
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_rounded,
            color: widget.isDark ? VeilTheme.accentColor : VeilTheme.holoPink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sizeStr,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white60 : Colors.black54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Open - image opens in-app, others open with native app
          IconButton(
            icon: Icon(
              _isImageFile(filename) ? Icons.open_in_full_rounded : Icons.open_in_new_rounded,
              color: widget.isDark ? VeilTheme.accentColor : VeilTheme.holoPink,
            ),
            onPressed: () async {
              final file = File(content);
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
                    child: Stack(
                      children: [
                        InteractiveViewer(
                          panEnabled: true, minScale: 0.5, maxScale: 4.0,
                          child: Image.file(file, fit: BoxFit.contain),
                        ),
                        Positioned(
                          top: 8, right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                final result = await OpenFile.open(content);
                if (result.type != ResultType.done) {
                  await Share.shareXFiles([XFile(file.path)], text: 'Shared from VeilChat');
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () async {
              final file = File(content);
              if (await file.exists()) {
                await Share.shareXFiles([XFile(file.path)], text: 'Shared from VeilChat');
              } else {
                _showSnack('File not found', Colors.red);
              }
            },
          ),
        ],
      ),
    );
  }

  bool _isImageFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  Widget _buildInputArea(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
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
                      hintText: 'Type a message...',
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

class _GroupChatBackgroundPainter extends CustomPainter {
  final bool isDark;
  final String seed;
  final Color themeColor;

  _GroupChatBackgroundPainter({
    required this.isDark,
    required this.seed,
    required this.themeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = isDark ? const Color(0xFF02050A) : const Color(0xFFF8FAFC),
    );
    final rng = Random(seed.hashCode);
    for (int i = 0; i < 6; i++) {
      final orbPaint = Paint()
        ..color = themeColor.withOpacity(isDark ? 0.03 : 0.05)
        ;
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        80.0 + rng.nextDouble() * 150,
        orbPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
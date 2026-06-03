import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  Socket? _socket;
  String? _currentUser;
  bool _isDisposed = false;
  bool _isConnected = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  // Stored credentials for auto-reconnect
  String? _lastIp;
  int? _lastPort;
  String? _lastPassword;
  bool _manualDisconnect = false;
  bool _isDisconnecting = false; // guard against double-call
  final _secureStorage = const FlutterSecureStorage();

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _userListController = StreamController<Map<String, dynamic>>.broadcast();
  final _callController = StreamController<Map<String, dynamic>>.broadcast();
  final _fileTransferController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get userListStream => _userListController.stream;
  Stream<Map<String, dynamic>> get callStream => _callController.stream;
  Stream<Map<String, dynamic>> get fileTransferStream => _fileTransferController.stream;

  Completer<Map<String, dynamic>>? _authCompleter;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  DateTime? _connectionTime;

  bool get isConnected => _socket != null && _isConnected;
  String? get currentUser => _currentUser;

  Future<Map<String, dynamic>> connectAndAuth(
    String ip,
    int port,
    String username,
    String password,
    bool isRegister, {
    bool allowSelfSigned = true,
  }) async {
    try {
      if (_socket != null) disconnect();

      debugPrint("🔌 Connecting to TCP server $ip:$port...");

      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 10));
      _isConnected = true;
      _currentUser = username;
      // Store for auto-reconnect
      _lastIp = ip;
      _lastPort = port;
      _lastPassword = password;
      _manualDisconnect = false;
      _reconnectAttempts = 0;

      _listen();
      _authCompleter = Completer<Map<String, dynamic>>();

      _bytesSent = 0;
      _bytesReceived = 0;
      _connectionTime = DateTime.now();

      _sendPacket(
        isRegister ? "REGISTER" : "LOGIN",
        {
          "username": username,
          "password": password,
          "device": Platform.isAndroid
              ? "Android"
              : Platform.isIOS
                  ? "iOS"
                  : "Desktop",
          "version": "1.0.0",
        },
      );

      final response = await _authCompleter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () {
        return {"status": "FAIL", "msg": "Authentication timeout"};
      });

      if (response['status'] == 'SUCCESS') {
        _isConnected = true;
        debugPrint("✅ Authenticated as $username (TCP)");
        _startPingTimer(); // Keep connection alive
        return {"success": true, "msg": response['msg']};
      } else {
        _currentUser = null;
        disconnect();
        return {"success": false, "msg": response['msg']};
      }
    } on SocketException catch (e) {
      _currentUser = null;
      disconnect();
      return {"success": false, "msg": "Connection failed: ${e.message}"};
    } on TimeoutException {
      _currentUser = null;
      disconnect();
      return {"success": false, "msg": "Connection timeout"};
    } catch (e) {
      _currentUser = null;
      disconnect();
      return {"success": false, "msg": "Connection error: $e"};
    }
  }

  void _sendPacket(String type, Map<String, dynamic> jsonMap) {
    if (_socket == null || !_isConnected) {
      debugPrint("📤 Cannot send: socket not connected");
      return;
    }
    try {
      final jsonStr = jsonEncode(jsonMap);
      final payload = utf8.encode(jsonStr);
      final typeHead = type.padRight(10).substring(0, 10);
      final lenHead = payload.length.toString().padRight(10).substring(0, 10);
      final packet = [
        ...utf8.encode(typeHead),
        ...utf8.encode(lenHead),
        ...payload,
      ];
      _socket!.add(packet);
      
      _bytesSent += packet.length;
    } on SocketException catch (e) {
      debugPrint("📤 SocketException in send: $e");
    } catch (e) {
      debugPrint("📤 Send error: $e");
    }
  }

  void sendPacket(String type, Map<String, dynamic> jsonMap) => _sendPacket(type, jsonMap);

  void _listen() {
    final buffer = <int>[];
    _socket!.listen(
      (data) {
        try {
          buffer.addAll(data);
          _bytesReceived += data.length;
          while (buffer.length >= 20) {
            final type = utf8.decode(buffer.sublist(0, 10)).trim();
            final len = int.tryParse(utf8.decode(buffer.sublist(10, 20)).trim()) ?? 0;
            if (len <= 0 || buffer.length < 20 + len) break;
            final jsonStr = utf8.decode(buffer.sublist(20, 20 + len));
            buffer.removeRange(0, 20 + len);
            Future.microtask(() {
              try {
                _handlePacket(type, jsonDecode(jsonStr));
              } catch (e) {
                debugPrint("❌ JSON decode error: $e");
              }
            });
          }
        } catch (e) {
          debugPrint("❌ Listener error: $e");
          buffer.clear();
        }
      },
      onDone: () {
        debugPrint("📡 Socket closed by server");
        _isConnected = false;
        _socket = null;
        _pingTimer?.cancel();
        if (!_manualDisconnect) _scheduleReconnect();
        else disconnect();
      },
      onError: (e) {
        debugPrint("❌ Socket error: $e");
        _isConnected = false;
        _socket = null;
        _pingTimer?.cancel();
        if (!_manualDisconnect) _scheduleReconnect();
        else disconnect();
      },
      cancelOnError: true,
    );
  }

  void _handlePacket(String type, Map<String, dynamic> data) {
    if (type == 'AUTH_RES') {
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.complete(data);
      }
      return;
    }
    if (type == 'USER_LIST') {
      _userListController.add(data);
      return;
    }
    const callSignals = {'OFFER', 'ANSWER', 'ICE', 'END'};
    if (callSignals.contains(type)) {
      _callController.add({...data, 'type': type});
      return;
    }
    if (type == 'FILE_PROGRESS') {
      _fileTransferController.add({...data, 'type': type});
      return;
    }
    if (type == 'PROFILE_UPDATE') {
      _messageController.add({...data, 'type': type});
      return;
    }

    final sender = data['sender'] ?? "Unknown";
    final content = data['content'] ?? "";

    const persistTypes = {'TEXT', 'IMAGE', 'AUDIO', 'FILE'};
    if (_currentUser != null && persistTypes.contains(type)) {
      Future.microtask(() async {
        // Extract isHidden and hiddenKey from incoming packet
        // These come through as metadata or top-level fields
        final meta = data['metadata'] as Map? ?? {};
        final isHidden = (data['isHidden'] ?? meta['isHidden'] ?? 0) as int;
        final hiddenKey = (data['hiddenKey'] ?? meta['hiddenKey'])?.toString();

        await DatabaseService().saveMessage(
          owner: _currentUser!,
          contact: sender,
          sender: sender,
          type: type,
          content: content,
          isMe: false,
          extra: data['extra'],
          metadata: data['metadata'],
          messageId: data['messageId'],
          status: 'delivered',
          isHidden: isHidden,
          hiddenKey: hiddenKey,
        );
        _messageController.add({...data, 'type': type});
      });
    } else {
      _messageController.add({...data, 'type': type});
    }
  }

  void sendReadReceipt(String toUser, String messageId) {
    sendMessage(toUser, "READ_RECEI", "", metadata: {"messageId": messageId});
  }

  void sendDeliveredReceipt(String toUser, String messageId) {
    sendMessage(toUser, "DELIVERED_", "", metadata: {"messageId": messageId});
  }

  void requestUserList() => _sendPacket("GET_USERS", {});

  Future<void> sendMessage(
    String toUser,
    String type,
    String content, {
    String? extra,
    Map<String, dynamic>? metadata,
    String? messageId,
    int isHidden = 0,
    String? hiddenKey,
  }) async {
    if (_socket == null || _currentUser == null || !_isConnected) {
      debugPrint("❌ Cannot send: not connected");
      return;
    }

    final packet = {
      "to_user": toUser,
      "content": content,
      "sender": _currentUser,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      if (extra != null) "extra": extra,
      if (metadata != null) "metadata": metadata,
      if (messageId != null) "messageId": messageId,
      if (isHidden != 0) "isHidden": isHidden,
      if (hiddenKey != null) "hiddenKey": hiddenKey,
    };

    _sendPacket(type, packet);

    // 🔥 NOTE: Sender side ki Database saving ab chat_detail_screen mein hoti hai
    // taake "local file path" easily track kiya ja sake. Double saving se bachne ke liye 
    // yahan se saveMessage nikal diya gaya hai.
  }

  void sendCallSignal(String toUser, String signalType, dynamic data) {
    if (_socket == null || _currentUser == null || !_isConnected) return;
    _sendPacket(signalType, {
      "to_user": toUser,
      "sender": _currentUser,
      "data": data,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
    debugPrint("📞 Sent $signalType to $toUser");
  }

  void sendIceCandidate(String toUser, Map<String, dynamic> candidate) {
    sendCallSignal(toUser, 'ICE', candidate);
  }

  void sendFileProgress(String toUser, String fileId, int bytesTransferred, int totalBytes) {
    if (_socket == null || _currentUser == null || !_isConnected) return;
    _sendPacket("FILE_PROGRESS", {
      "to_user": toUser,
      "sender": _currentUser,
      "file_id": fileId,
      "bytes_transferred": bytesTransferred,
      "total_bytes": totalBytes,
      "progress": (bytesTransferred / totalBytes) * 100,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
  }

  Map<String, dynamic> getConnectionStats() {
    return {
      "connected": _socket != null && _isConnected,
      "current_user": _currentUser,
      "bytes_sent": _bytesSent,
      "bytes_received": _bytesReceived,
      "connection_duration": _connectionTime != null
          ? DateTime.now().difference(_connectionTime!).inSeconds
          : 0,
      "connected_since": _connectionTime,
    };
  }

  Future<bool> pingServer() async {
    if (_socket == null || !_isConnected) return false;
    try {
      _sendPacket("PING", {"timestamp": DateTime.now().millisecondsSinceEpoch});
      return true;
    } catch (e) {
      return false;
    }
  }


  void _startPingTimer() {
    _pingTimer?.cancel();
    // Send PING every 30 seconds to keep connection alive
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket != null && _isConnected) {
        try {
          _sendPacket('PING', {'timestamp': DateTime.now().millisecondsSinceEpoch});
        } catch (e) {
          debugPrint('Ping failed: $e');
        }
      }
    });
  }


  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    if (_lastIp == null || _lastPort == null || _currentUser == null || _lastPassword == null) {
      debugPrint('🔄 No credentials stored — cannot reconnect');
      return;
    }
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('🔄 Max reconnect attempts reached — giving up');
      // Notify UI that connection is permanently lost
      if (!_messageController.isClosed) {
        _messageController.add({
          'type': 'RECONNECT_FAILED',
          'msg': 'Connection lost. Please restart the app.',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return;
    }

    _reconnectAttempts++;
    // Exponential backoff: 2s, 4s, 8s, 16s, 30s max
    final delaySeconds = (_reconnectAttempts <= 5)
        ? (2 * _reconnectAttempts).clamp(2, 30)
        : 30;

    debugPrint('🔄 Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)...');

    // Notify UI so it can show "Reconnecting..." banner
    if (!_messageController.isClosed) {
      _messageController.add({
        'type': 'RECONNECTING',
        'attempt': _reconnectAttempts,
        'delay': delaySeconds,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_manualDisconnect || _isConnected) return;
      debugPrint('🔄 Attempting reconnect...');
      try {
        _socket = await Socket.connect(
          _lastIp!, _lastPort!,
          timeout: const Duration(seconds: 10),
        );
        _isConnected = true;
        _listen();
        _authCompleter = Completer<Map<String, dynamic>>();

        _sendPacket('LOGIN', {
          'username': _currentUser!,
          'password': _lastPassword!,
          'device': 'Android',
          'version': '1.0.0',
        });

        final response = await _authCompleter!.future
            .timeout(const Duration(seconds: 10), onTimeout: () {
          return {'status': 'FAIL', 'msg': 'Auth timeout'};
        });

        if (response['status'] == 'SUCCESS') {
          _reconnectAttempts = 0;
          _manualDisconnect = false;
          _isDisconnecting = false;
          _startPingTimer();
          debugPrint('✅ Reconnected as $_currentUser');
          if (!_messageController.isClosed) {
            _messageController.add({
              'type': 'RECONNECTED',
              'msg': 'Connection restored',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          }
        } else {
          debugPrint('❌ Reconnect auth failed: ${response['msg']}');
          _isConnected = false;
          _socket?.destroy();
          _socket = null;
          _scheduleReconnect();
        }
      } catch (e) {
        debugPrint('❌ Reconnect failed: $e');
        _isConnected = false;
        try { _socket?.destroy(); } catch (_) {}
        _socket = null;
        _scheduleReconnect();
      }
    });
  }

  void disconnect() {
    if (_isDisconnecting) return; // prevent double-call
    _isDisconnecting = true;
    debugPrint("🔌 Disconnecting...");
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _pingTimer?.cancel();
    _pingTimer = null;
    _isConnected = false;
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete({"status": "FAIL", "msg": "Socket closed"});
    }

    try {
      _socket?.destroy();
    } catch (e) {
      debugPrint("Error destroying socket: $e");
    }

    _socket = null;
    _currentUser = null;
    _connectionTime = null;
    _isDisconnecting = false; // allow future reconnects

    if (!_messageController.isClosed) {
      _messageController.add({
        "type": "DISCONNECT",
        "msg": "Disconnected from server",
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  void sendProfileUpdate(Map<String, dynamic> profileData) {
    if (_socket == null || _currentUser == null || !_isConnected) {
      debugPrint("❌ Cannot send profile update: not connected");
      return;
    }

    _sendPacket("PROFILE_UPDATE", {
      "sender": _currentUser,
      "profile": profileData,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
    
    debugPrint("📤 Sent PROFILE_UPDATE to server");
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    disconnect();
    _messageController.close();
    _userListController.close();
    _callController.close();
    _fileTransferController.close();
  }
}
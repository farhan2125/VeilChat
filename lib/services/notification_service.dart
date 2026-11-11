import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import '../main.dart';

/// Top-level function required for background notification taps.
@pragma('vm:entry-point')
void _notificationTapHandler(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  try {
    final data = jsonDecode(payload);
    final String? sender = data['sender'];
    final String? isDarkStr = data['isDark']?.toString();
    final bool isDark = isDarkStr != 'false';

    if (sender != null) {
      // Navigate to the right screen based on type
      final String type = data['type'] ?? 'TEXT';
      if (type == 'call') {
        // Call notification - just open app
        return;
      }
      // Navigate to chat screen
      navigatorKey.currentState?.pushNamed(
        '/chat',
        arguments: {
          'contactName': sender,
          'isDark': isDark,
          'sharedKey': '',
          'myUsername': '',
        },
      );
    }
  } catch (e) {
    debugPrint('❌ Notification tap error: $e');
  }
}

/// Singleton service for local (in-device) notifications.
/// Works without Firebase - fires whenever a message arrives
/// while the app is in the background or screen is off.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Track notification IDs per sender so we update instead of stacking
  final Map<String, int> _notificationIds = {};
  int _nextId = 100;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _notificationTapHandler,
        onDidReceiveBackgroundNotificationResponse: _notificationTapHandler,
      );

      await _createAndroidChannel();
      await _requestPermission();

      _isInitialized = true;
      debugPrint('✅ NotificationService initialized');
    } catch (e) {
      debugPrint('❌ NotificationService init error: $e');
    }
  }

  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      'veilchat_messages',
      'VeilChat Messages',
      description: 'New message notifications from VeilChat',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // Separate channel for calls - higher priority
    const callChannel = AndroidNotificationChannel(
      'veilchat_calls',
      'VeilChat Calls',
      description: 'Incoming call notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(callChannel);
  }

  Future<void> _requestPermission() async {
    final status = await Permission.notification.request();
    if (status.isDenied) {
      debugPrint('⚠️ Notification permission denied');
    }
  }

  /// Show a message notification.
  /// Groups messages from same sender so they don't stack.
  Future<void> showMessageNotification({
    required String sender,
    required String message,
    String type = 'TEXT',
    bool isDark = true,
  }) async {
    if (!_isInitialized) return;

    // Clean the message - never show encrypted hex
    String displayMsg = message;
    // If it looks like hex/encrypted, replace with friendly text
    if (displayMsg.length > 20 &&
        RegExp(r'^[0-9a-f]+$').hasMatch(displayMsg.trim())) {
      displayMsg = type == 'IMAGE'
          ? '📷 Photo'
          : type == 'AUDIO'
          ? '🎤 Voice message'
          : type == 'FILE'
          ? '📎 File'
          : '💬 New message';
    } else if (displayMsg.contains('/data/user/') ||
        displayMsg.contains('/storage/')) {
      displayMsg = type == 'IMAGE'
          ? '📷 Photo'
          : type == 'AUDIO'
          ? '🎤 Voice message'
          : type == 'FILE'
          ? '📎 File'
          : '💬 New message';
    }
    // Get or create ID for this sender
    _notificationIds[sender] ??= _nextId++;
    final id = _notificationIds[sender]!;

    // Build body text based on message type
    String body;
    switch (type) {
      case 'IMAGE':
        body = '📷 Sent a photo';
        break;
      case 'AUDIO':
        body = '🎤 Sent a voice message';
        break;
      case 'FILE':
        body = '📁 Sent a file';
        break;
      default:
        // Decrypt preview not possible here - show generic text
        body = message.length > 60 ? '${message.substring(0, 60)}...' : message;
        // If it looks like hex (encrypted), show generic
        if (body.length > 20 &&
            RegExp(r'^[0-9a-fA-F]+$').hasMatch(body.replaceAll(' ', ''))) {
          body = '🔒 New encrypted message';
        }
    }

    final payload = jsonEncode({
      'sender': sender,
      'type': type,
      'isDark': isDark,
    });

    final androidDetails = AndroidNotificationDetails(
      'veilchat_messages',
      'VeilChat Messages',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
      icon: '@mipmap/ic_launcher',
      // Group notifications per sender
      groupKey: 'veilchat_$sender',
      setAsGroupSummary: false,
    );

    await _notifications.show(
      id,
      sender,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  /// Show incoming call notification.
  Future<void> showIncomingCallNotification(
    String caller, {
    bool isDark = true,
  }) async {
    if (!_isInitialized) return;
    final payload = jsonEncode({
      'sender': caller,
      'type': 'call',
      'isDark': isDark,
    });
    const androidDetails = AndroidNotificationDetails(
      'veilchat_calls',
      'VeilChat Calls',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      icon: '@mipmap/ic_launcher',
    );
    await _notifications.show(
      1,
      '📞 Incoming Call',
      '$caller is calling...',
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  Future<void> cancelNotification(String sender) async {
    final id = _notificationIds[sender];
    if (id != null) await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    _notificationIds.clear();
  }
}

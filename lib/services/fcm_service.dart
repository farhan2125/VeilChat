import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'network_service.dart';
import '../main.dart';

/// Top-level background handler — must be outside class
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService().showMessageNotification(
    sender: message.data['sender'] ?? message.notification?.title ?? 'VeilChat',
    message: message.notification?.body ?? '',
    isDark: true,
  );
}

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal(); // NO Firebase calls here — safe

  // Lazy — only created after Firebase.initializeApp()
  FirebaseMessaging? _fcm;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      // 1. Init Firebase first — MUST be before any FirebaseMessaging call
      await Firebase.initializeApp();

      // 2. Now safe to access FirebaseMessaging
      _fcm = FirebaseMessaging.instance;

      // 3. Request permission
      final settings = await _fcm!.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('⚠️ FCM permission not granted');
        return;
      }

      // 4. Get token and send to server
      await _refreshToken();

      // 5. Token refresh listener
      _fcm!.onTokenRefresh.listen(_sendTokenToServer);

      // 6. Foreground messages
      FirebaseMessaging.onMessage.listen(_handleForeground);

      // 7. Background handler (static top-level)
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // 8. App opened from terminated state via notification
      final initial = await _fcm!.getInitialMessage();
      if (initial != null) _navigateFromMessage(initial);

      // 9. App opened from background via notification
      FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromMessage);

      _isInitialized = true;
      debugPrint('✅ FcmService initialized');
    } catch (e) {
      // Fails gracefully — local notifications still work
      debugPrint('⚠️ FCM init failed (ok if emulator): $e');
    }
  }

  Future<void> _refreshToken() async {
    try {
      final token = await _fcm?.getToken();
      if (token != null) await _sendTokenToServer(token);
    } catch (e) {
      debugPrint('❌ FCM token error: $e');
    }
  }

  Future<void> _sendTokenToServer(String token) async {
    final user = NetworkService().currentUser;
    if (user != null) {
      NetworkService().sendPacket('UPDATE_FCM_TOKEN', {
        'username': user,
        'fcm_token': token,
      });
      debugPrint('📲 FCM token sent to server');
    }
  }

  void _handleForeground(RemoteMessage message) {
    NotificationService().showMessageNotification(
      sender: message.data['sender'] ?? message.notification?.title ?? 'VeilChat',
      message: message.notification?.body ?? '',
      isDark: true,
    );
  }

  void _navigateFromMessage(RemoteMessage message) {
    final sender = message.data['sender'];
    if (sender != null) {
      navigatorKey.currentState?.pushNamed('/chat', arguments: {
        'contactName': sender,
        'isDark': true,
        'sharedKey': '',
        'myUsername': '',
      });
    }
  }

  Future<void> deleteToken() async {
    try {
      await _fcm?.deleteToken();
    } catch (e) {
      debugPrint('❌ FCM deleteToken: $e');
    }
  }
}

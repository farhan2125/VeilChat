import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/notification_service.dart';
import 'crash_logger.dart';
import 'services/fcm_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'chat_detail_screen.dart';
import 'group_chat_detail_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final secureStorage = const FlutterSecureStorage();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init crash logger first — catches all subsequent errors
  await CrashLogger.init();
  await NotificationService().init();
  // FCM init (requires google-services.json - fails gracefully if not set up)
  await FcmService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeilChat',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      navigatorKey: navigatorKey,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
      ),
      routes: {
        '/': (context) => const LoginScreen(),
        '/main': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return MainScreen(isDarkInitial: args['isDark'] ?? true, sharedKey: args['sharedKey'] ?? '', username: args['username'] ?? '');
        },
        '/chat': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return FutureBuilder<String?>(
            future: secureStorage.read(key: 'veilchat_shared_key'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              return ChatDetailScreen(
                contactName: args['contactName'] as String,
                isDark: args['isDark'] as bool? ?? true,
                sharedKey: snapshot.data ?? '',
                myUsername: args['myUsername'] as String? ?? '',
              );
            },
          );
        },
        '/group': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return FutureBuilder<String?>(
            future: secureStorage.read(key: 'veilchat_shared_key'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              return GroupChatDetailScreen(
                groupId: args['groupId'] as String,
                groupName: args['groupName'] as String,
                isDark: args['isDark'] as bool? ?? true,
                currentUser: args['myUsername'] as String? ?? '',
                sharedKey: snapshot.data ?? '',
              );
            },
          );
        },
      },
    );
  }
}

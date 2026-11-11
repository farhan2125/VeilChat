import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veilchat_new/branding/veil_brand.dart';
import 'package:veilchat_new/chat_lock_screen.dart';
import 'package:veilchat_new/encrypt_screen.dart';
import 'package:veilchat_new/stego_screen.dart';
import 'package:veilchat_new/veil_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Veil Design System Component Tests', () {
    testWidgets('VeilButton renders label and triggers onTap', (
      WidgetTester tester,
    ) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VeilButton(
              isDark: true,
              label: 'Submit',
              gradient: VeilBrand.primaryGradient,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('SUBMIT'), findsOneWidget);
      await tester.tap(find.text('SUBMIT'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('VeilBadge renders telemetry label and icon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VeilBadge(
              label: 'AES-256-GCM WIRE HEX',
              icon: Icons.enhanced_encryption_rounded,
              color: VeilBrand.veilTeal,
              isDark: true,
            ),
          ),
        ),
      );

      expect(find.text('AES-256-GCM WIRE HEX'), findsOneWidget);
      expect(find.byIcon(Icons.enhanced_encryption_rounded), findsOneWidget);
    });

    testWidgets('EncryptScreen displays live telemetry and key generator', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EncryptScreen(
              isDark: true,
              toggleTheme: () {},
              sharedKey: 'MasterSecretKey123!',
            ),
          ),
        ),
      );

      expect(find.text('PLAINTEXT (0 B)'), findsOneWidget);
      expect(find.text('WIRE EST: 48 B'), findsOneWidget);
      expect(find.text('Generate Secure Key'), findsOneWidget);
    });

    testWidgets('StegoScreen displays live capacity telemetry badges', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StegoScreen(isDark: true, toggleTheme: () {})),
        ),
      );

      expect(find.text('NO CARRIER IMAGE'), findsOneWidget);
      expect(find.text('SHA-256 PRNG • RED LSB'), findsOneWidget);
      expect(find.text('Generate & Copy Key'), findsOneWidget);
    });

    testWidgets('VeilEmptyState renders title, description and action', (
      WidgetTester tester,
    ) async {
      bool actionTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VeilEmptyState(
              isDark: true,
              icon: Icons.chat_bubble_outline,
              title: 'Empty Inbox',
              description: 'You have no messages.',
              actionLabel: 'New Chat',
              onAction: () => actionTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Empty Inbox'), findsOneWidget);
      expect(find.text('You have no messages.'), findsOneWidget);
      expect(find.text('NEW CHAT'), findsOneWidget);

      await tester.tap(find.text('NEW CHAT'));
      await tester.pumpAndSettle();
      expect(actionTriggered, isTrue);
    });

    testWidgets('VeilLoadingIndicator displays indicator and message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VeilLoadingIndicator(
              isDark: true,
              message: 'Connecting to secure server...',
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Connecting to secure server...'), findsOneWidget);
    });

    testWidgets('VeilErrorCard displays error and triggers retry', (
      WidgetTester tester,
    ) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VeilErrorCard(
              isDark: true,
              message: 'Network connection failed',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Network connection failed'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);

      await tester.tap(find.text('RETRY'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('VeilAvatar displays fallback initial letter', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: VeilAvatar(name: 'Alice', radius: 24)),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('ChatLockScreen renders on small screen without overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: ChatLockScreen(
            contactName: 'alice',
            myUsername: 'bob',
            isDark: true,
            child: Text('Unlocked Chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    test(
      'ChatLockScreen.isLocked defaults to false and purges legacy keys',
      () async {
        SharedPreferences.setMockInitialValues({
          'chat_lock_pin_\$contact': 'oldhash',
        });
        final locked = await ChatLockScreen.isLocked('alice', 'bob');
        expect(locked, isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('chat_lock_pin_\$contact'), isFalse);
      },
    );
  });
}

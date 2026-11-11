import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilchat_new/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LoginScreen smoke test renders essential UI elements', (
    WidgetTester tester,
  ) async {
    // Build LoginScreen in a test harness
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Allow async initializations (SharedPreferences, animations)
    await tester.pump();

    // Verify key UI elements render
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.byType(TextField),
      findsAtLeastNWidgets(2),
    ); // username & password fields
  });
}

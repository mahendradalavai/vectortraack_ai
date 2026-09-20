import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/app/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const awarenessChannel = MethodChannel('kitten/app_awareness');

  setUp(() {
    // Mock the secure storage platform channel for widget testing
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      storageChannel,
      (MethodCall methodCall) async => null,
    );

    // App awareness has no native side in a widget test; answer it explicitly
    // rather than leaving the call unanswered.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      awarenessChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'hasUsageAccess') return false;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(awarenessChannel, null);
  });

  testWidgets('KittenApp launches, shows home page with chat input, and navigates to settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KittenApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The home page should display the app title.
    expect(find.textContaining('Kitten AI'), findsOneWidget);

    // The greeting text should be visible.
    expect(find.textContaining("I'm your Kitten"), findsOneWidget);

    // A settings button should exist.
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // The mic/talk button should exist.
    expect(find.text('Talk'), findsOneWidget);

    // The chat text field should be present.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Chat with Kitten...'), findsOneWidget);

    // Tap Settings button
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Settings screen should be visible
    expect(find.text('Settings'), findsOneWidget);

    // AI Provider section should be displayed
    expect(find.text('AI Provider & Brain'), findsOneWidget);
    expect(find.text('Groq Cloud (OpenAI-compatible)'), findsOneWidget);
    expect(find.text('Test Connection'), findsOneWidget);
  });
}

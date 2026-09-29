import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/overlay/models/overlay_app_context.dart';
import 'package:kitten/core/overlay/services/floating_overlay_controller.dart';
import 'package:kitten/core/overlay/services/floating_overlay_service.dart';
import 'package:kitten/features/home/presentation/pages/home_page.dart';

/// A stand-in for the native overlay that can hand apps over on demand.
class FakeFloatingOverlayService implements FloatingOverlayService {
  void Function(OverlayAppContext context)? openingHandler;
  OverlayAppContext? pending;
  int acknowledgements = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasOverlayPermission() async => true;

  @override
  Future<bool> openOverlaySettings() async => true;

  @override
  Future<bool> startFloatingKitten() async => true;

  @override
  Future<bool> stopFloatingKitten() async => true;

  @override
  Future<bool> isFloatingKittenRunning() async => false;

  @override
  void handleAppOpenings(void Function(OverlayAppContext context)? handler) {
    openingHandler = handler;
  }

  @override
  Future<OverlayAppContext?> takePendingAppContext() async {
    final context = pending;
    pending = null;
    return context;
  }

  @override
  Future<void> acknowledgeAppContext() async => acknowledgements++;

  void push(OverlayAppContext context) => openingHandler?.call(context);
}

const _instagram = OverlayAppContext(
  packageName: 'com.instagram.android',
  label: 'Instagram',
  line: 'Instagram? What are we doing here?',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const awarenessChannel = MethodChannel('kitten/app_awareness');
  const permissionsChannel = MethodChannel('kitten/permissions');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          storageChannel,
          (MethodCall methodCall) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          awarenessChannel,
          (MethodCall methodCall) async =>
              methodCall.method == 'hasUsageAccess' ? false : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          permissionsChannel,
          (MethodCall methodCall) async =>
              methodCall.method == 'hasMicrophonePermission' ? false : true,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(awarenessChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
  });

  Future<void> pumpHome(
    WidgetTester tester,
    FloatingOverlayController overlay,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(overlayController: overlay)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a tap that cold-starts Kitten opens the chat in context', (
    tester,
  ) async {
    final service = FakeFloatingOverlayService()..pending = _instagram;
    final overlay = FloatingOverlayController(service: service);

    await pumpHome(tester, overlay);

    expect(find.text('Instagram? What are we doing here?'), findsOneWidget);

    overlay.dispose();
  });

  testWidgets('an app handed over while Kitten runs starts the conversation', (
    tester,
  ) async {
    final service = FakeFloatingOverlayService();
    final overlay = FloatingOverlayController(service: service);

    await pumpHome(tester, overlay);
    expect(find.text('Instagram? What are we doing here?'), findsNothing);

    service.push(_instagram);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Instagram? What are we doing here?'), findsOneWidget);

    overlay.dispose();
  });

  testWidgets('the same hand-off twice still reads as one line', (
    tester,
  ) async {
    final service = FakeFloatingOverlayService();
    final overlay = FloatingOverlayController(service: service);

    await pumpHome(tester, overlay);

    // One hand-off can be pushed twice when the platform repeats itself.
    service.push(_instagram);
    service.push(_instagram);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Instagram? What are we doing here?'), findsOneWidget);
    expect(service.acknowledgements, 2);

    overlay.dispose();
  });
}

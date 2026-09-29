import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kitten/app/app.dart';
import 'package:kitten/core/awareness/services/app_awareness_controller.dart';
import 'package:kitten/core/awareness/services/method_channel_app_awareness_service.dart';

/// These run on a real device, because usage stats have no host-side stand-in.
///
/// Before running them, grant usage access to Kitten:
///   adb shell appops set com.example.kitten GET_USAGE_STATS allow
/// and open some other app shortly beforehand, so there is a foreground app to
/// report.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('app awareness on device', () {
    testWidgets('the platform channel reports access and the last used app', (
      tester,
    ) async {
      final service = MethodChannelAppAwarenessService();

      expect(service.isSupported, isTrue);
      expect(
        await service.hasUsageAccess(),
        isTrue,
        reason:
            'grant it with: adb shell appops set com.example.kitten '
            'GET_USAGE_STATS allow',
      );

      final app = await service.foregroundApp();
      expect(app, isNotNull, reason: 'open another app first');
      expect(app!.packageName, isNotEmpty);
      // Kitten must never report itself as the app the user is using.
      expect(app.packageName, isNot('com.example.kitten'));

      // Printed so a run says what it actually detected.
      debugPrint(
        'app awareness detected: ${app.packageName} '
        '(as "${app.displayName}")',
      );
    });

    testWidgets('the controller turns that into prompt context', (
      tester,
    ) async {
      final controller = AppAwarenessController(
        service: MethodChannelAppAwarenessService(),
      );

      final enabled = await controller.enable(openSettingsIfMissing: false);
      expect(enabled, isTrue);
      expect(controller.enabled, isTrue);
      expect(controller.currentApp, isNotNull);

      final context = controller.buildPromptContext();
      expect(context, isNotNull);
      expect(context, contains(controller.currentApp!.displayName));

      await controller.disable();
      expect(controller.buildPromptContext(), isNull);

      controller.dispose();
    });

    testWidgets('the Settings switch reflects the real permission state', (
      tester,
    ) async {
      await tester.pumpWidget(const KittenApp());
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byTooltip('Settings'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final switchTile = find.widgetWithText(SwitchListTile, 'App Awareness');
      await tester.scrollUntilVisible(
        switchTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      // Access is already granted, so the screen should say so truthfully
      // before the user touches anything. The finder is scoped to the Usage
      // Access tile because the Floating Kitten permission tile also reads
      // "Granted" as soon as overlay access is allowed, and a bare
      // find.text('Granted') would match either one.
      final usageTile = find.widgetWithText(ListTile, 'Usage Access');
      await tester.scrollUntilVisible(
        usageTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(
        find.descendant(of: usageTile, matching: find.text('Granted')),
        findsOneWidget,
      );

      // Scrolling down to Usage Access pushed the switch out of the viewport,
      // where the list has since disposed it, so bring it back before tapping.
      await tester.scrollUntilVisible(
        switchTile,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      await tester.tap(switchTile);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.textContaining('Kitten knows which app you were last using'),
        findsOneWidget,
      );
      expect(find.text('Last app seen'), findsOneWidget);
    });
  });
}

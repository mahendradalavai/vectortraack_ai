import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kitten/app/app.dart';
import 'package:kitten/core/overlay/services/floating_overlay_controller.dart';
import 'package:kitten/core/overlay/services/method_channel_floating_overlay_service.dart';

/// Run after granting overlay access on the emulator:
/// adb shell appops set com.example.kitten SYSTEM_ALERT_WINDOW allow
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('floating overlay starts, reports running, and stops', (
    tester,
  ) async {
    await tester.pumpWidget(const KittenApp());
    await tester.pump(const Duration(milliseconds: 500));

    final service = MethodChannelFloatingOverlayService();
    final controller = FloatingOverlayController(service: service);

    expect(service.isSupported, isTrue);
    expect(
      await service.hasOverlayPermission(),
      isTrue,
      reason:
          'grant it with: adb shell appops set com.example.kitten '
          'SYSTEM_ALERT_WINDOW allow',
    );

    await controller.refresh();
    // A reboot or unlock restores the overlay when it was enabled before, so the
    // test must not assume it starts stopped. Clear anything already running.
    if (controller.isRunning) {
      await controller.stop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await controller.refresh();
    }
    expect(controller.isRunning, isFalse);

    expect(await controller.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await controller.refresh();
    expect(controller.isRunning, isTrue);

    expect(await controller.stop(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await controller.refresh();
    expect(controller.isRunning, isFalse);

    // The app hand-off rides the same channel. Nothing has been handed over in
    // a test run, so this proves the call answers instead of failing: whether
    // the cat really hands an app over is checked by hand on the device.
    expect(await controller.takePendingAppContext(), isNull);

    controller.dispose();
  });
}

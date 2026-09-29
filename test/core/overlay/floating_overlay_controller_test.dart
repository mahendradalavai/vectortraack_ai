import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/overlay/models/overlay_app_context.dart';
import 'package:kitten/core/overlay/services/floating_overlay_controller.dart';
import 'package:kitten/core/overlay/services/floating_overlay_service.dart';

class FakeFloatingOverlayService implements FloatingOverlayService {
  FakeFloatingOverlayService({
    this.supported = true,
    this.permission = false,
    this.startResult = true,
    this.stopResult = true,
  });

  final bool supported;
  bool permission;
  bool running = false;
  bool startResult;
  bool stopResult;

  /// The receiver the controller registered, if any.
  void Function(OverlayAppContext context)? openingHandler;

  /// A hand-off waiting to be taken, standing in for the platform's stash.
  OverlayAppContext? pending;

  int acknowledgements = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasOverlayPermission() async => permission;

  @override
  Future<bool> openOverlaySettings() async => true;

  @override
  Future<bool> startFloatingKitten() async {
    if (startResult) running = true;
    return startResult;
  }

  @override
  Future<bool> stopFloatingKitten() async {
    if (stopResult) running = false;
    return stopResult;
  }

  @override
  Future<bool> isFloatingKittenRunning() async => running;

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

  /// Stands in for the native side handing an app over while Kitten runs.
  void push(OverlayAppContext context) => openingHandler?.call(context);
}

void main() {
  group('FloatingOverlayController', () {
    test('starts disabled and refreshes native state', () async {
      final service = FakeFloatingOverlayService();
      final controller = FloatingOverlayController(service: service);

      expect(controller.hasPermission, isFalse);
      expect(controller.isRunning, isFalse);

      await controller.refresh();

      expect(controller.hasPermission, isFalse);
      expect(controller.isRunning, isFalse);
    });

    test('denied permission prevents starting and reports an error', () async {
      final controller = FloatingOverlayController(
        service: FakeFloatingOverlayService(),
      );

      final started = await controller.start();

      expect(started, isFalse);
      expect(controller.isRunning, isFalse);
      expect(controller.lastError, contains('permission'));
    });

    test('starts and stops only after native state changes', () async {
      final service = FakeFloatingOverlayService(permission: true);
      final controller = FloatingOverlayController(service: service);

      expect(await controller.start(), isTrue);
      expect(controller.isRunning, isTrue);

      expect(await controller.stop(), isTrue);
      expect(controller.isRunning, isFalse);
    });

    test('handles native start and stop failures', () async {
      final service = FakeFloatingOverlayService(
        permission: true,
        startResult: false,
        stopResult: false,
      );
      final controller = FloatingOverlayController(service: service);

      expect(await controller.start(), isFalse);
      expect(controller.lastError, contains('started'));

      service.startResult = true;
      expect(await controller.start(), isTrue);
      service.stopResult = false;
      expect(await controller.stop(), isFalse);
      expect(controller.lastError, contains('stopped'));
    });
  });

  group('FloatingOverlayController app hand-off', () {
    const instagram = OverlayAppContext(
      packageName: 'com.instagram.android',
      label: 'Instagram',
      line: 'Instagram? What are we doing here?',
    );

    test('hands a pushed app to listeners and acknowledges it', () async {
      final service = FakeFloatingOverlayService();
      final controller = FloatingOverlayController(service: service);
      final received = <OverlayAppContext>[];
      final subscription = controller.appOpenings.listen(received.add);

      service.push(instagram);
      await Future<void>.delayed(Duration.zero);

      expect(received, [instagram]);
      expect(
        service.acknowledgements,
        1,
        reason: 'the stashed copy must not seed the chat a second time',
      );

      await subscription.cancel();
      controller.dispose();
    });

    test('takes an early hand-off once, then reports nothing', () async {
      final service = FakeFloatingOverlayService()..pending = instagram;
      final controller = FloatingOverlayController(service: service);

      expect(await controller.takePendingAppContext(), instagram);
      expect(await controller.takePendingAppContext(), isNull);
      expect(service.acknowledgements, greaterThan(0));

      controller.dispose();
    });

    test('stops listening to the platform once disposed', () {
      final service = FakeFloatingOverlayService();
      final controller = FloatingOverlayController(service: service);

      expect(service.openingHandler, isNotNull);
      controller.dispose();
      expect(service.openingHandler, isNull);
    });
  });

  group('OverlayAppContext', () {
    test('reads a platform payload and prefers the platform line', () {
      final context = OverlayAppContext.fromChannel(const {
        'packageName': 'com.instagram.android',
        'label': 'Instagram',
        'line': 'Instagram? What are we doing here?',
      });

      expect(context, isNotNull);
      expect(context!.displayName, 'Instagram');
      expect(context.openingLine, 'Instagram? What are we doing here?');
    });

    test('names an app whose label Android withheld', () {
      final context = OverlayAppContext.fromChannel(const {
        'packageName': 'com.spotify.music',
        'label': '',
        'line': '',
      });

      expect(context!.displayName, 'Music');
      expect(context.openingLine, 'Music? What are we doing here?');
    });

    test('rejects a payload without a package name', () {
      expect(OverlayAppContext.fromChannel(null), isNull);
      expect(OverlayAppContext.fromChannel('Instagram'), isNull);
      expect(
        OverlayAppContext.fromChannel(const {'packageName': '  '}),
        isNull,
      );
    });
  });
}

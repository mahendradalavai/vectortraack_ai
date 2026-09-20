import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/awareness/models/foreground_app.dart';
import 'package:kitten/core/awareness/services/app_awareness_controller.dart';
import 'package:kitten/core/awareness/services/app_awareness_service.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

class FakeAppAwarenessService implements AppAwarenessService {
  FakeAppAwarenessService({
    this.supported = true,
    this.usageAccess = true,
    this.app,
  });

  bool supported;
  bool usageAccess;
  ForegroundApp? app;

  int openSettingsCount = 0;
  int foregroundCallCount = 0;
  bool disposed = false;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> hasUsageAccess() async => supported && usageAccess;

  @override
  Future<void> openUsageAccessSettings() async => openSettingsCount++;

  @override
  Future<ForegroundApp?> foregroundApp() async {
    foregroundCallCount++;
    return app;
  }

  @override
  void dispose() => disposed = true;
}

class FakeAwarenessStorage extends SecureStorageService {
  FakeAwarenessStorage({this.stored});

  bool? stored;
  int saveCount = 0;

  @override
  Future<bool?> getAppAwarenessEnabled() async => stored;

  @override
  Future<void> saveAppAwarenessEnabled(bool enabled) async {
    saveCount++;
    stored = enabled;
  }
}

const _chrome = ForegroundApp(packageName: 'com.android.chrome', label: 'Chrome');
const _maps = ForegroundApp(packageName: 'com.google.android.apps.maps');

/// Lets pending microtasks and timer callbacks settle.
Future<void> _settle([int ms = 5]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('AppAwarenessController', () {
    test('starts disabled with nothing known', () {
      final controller = AppAwarenessController(
        service: FakeAppAwarenessService(usageAccess: false),
        storage: FakeAwarenessStorage(),
      );

      expect(controller.enabled, isFalse);
      expect(controller.currentApp, isNull);
      expect(controller.lastError, isNull);
      expect(controller.isSupported, isTrue);

      controller.dispose();
    });

    test('enable() is impossible on an unsupported platform', () async {
      final service = FakeAppAwarenessService(supported: false);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
      );

      final enabled = await controller.enable();

      expect(enabled, isFalse);
      expect(controller.enabled, isFalse);
      expect(controller.lastError, contains('only available on Android'));
      // Nothing to open, and no pointless permission prompt.
      expect(service.openSettingsCount, 0);

      controller.dispose();
    });

    test('enable() refuses to claim it works without usage access', () async {
      final service = FakeAppAwarenessService(usageAccess: false);
      final storage = FakeAwarenessStorage();
      final controller = AppAwarenessController(
        service: service,
        storage: storage,
      );

      final enabled = await controller.enable();

      expect(enabled, isFalse);
      expect(controller.enabled, isFalse);
      expect(controller.hasUsageAccess, isFalse);
      expect(controller.lastError, contains('Usage access'));
      // Sends the user straight to the screen that fixes it.
      expect(service.openSettingsCount, 1);
      // And does not persist a preference it cannot honour.
      expect(storage.stored, isFalse);

      controller.dispose();
    });

    test('enable() reads the current app once access is granted', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final storage = FakeAwarenessStorage();
      final controller = AppAwarenessController(
        service: service,
        storage: storage,
        pollInterval: const Duration(milliseconds: 20),
      );

      final enabled = await controller.enable();

      expect(enabled, isTrue);
      expect(controller.enabled, isTrue);
      expect(controller.hasUsageAccess, isTrue);
      expect(controller.lastError, isNull);
      expect(controller.currentApp, _chrome);
      expect(storage.stored, isTrue);
      // Not sent to settings when the permission is already there.
      expect(service.openSettingsCount, 0);

      controller.dispose();
    });

    test('polling notices when the user moves to another app', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
        pollInterval: const Duration(milliseconds: 10),
      );

      await controller.enable();
      expect(controller.currentApp, _chrome);

      service.app = _maps;
      await _settle(40);

      expect(controller.currentApp, _maps);

      controller.dispose();
    });

    test('notifies listeners only when the app actually changes', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
      );

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.enable();
      final afterEnable = notifications;

      // Same app again: no repaint, so the UI does not churn every poll.
      await controller.refresh();
      expect(notifications, afterEnable);

      service.app = _maps;
      await controller.refresh();
      expect(notifications, afterEnable + 1);

      controller.dispose();
    });

    test('suspend() stops polling and resume() restarts it', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
        pollInterval: const Duration(milliseconds: 10),
      );

      await controller.enable();

      await controller.suspend();
      final callsWhileSuspended = service.foregroundCallCount;
      await _settle(30);
      expect(service.foregroundCallCount, callsWhileSuspended);

      await controller.resume();
      expect(controller.enabled, isTrue);
      expect(controller.currentApp, _chrome);

      controller.dispose();
    });

    test('resume() stands down if access was revoked while away', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final storage = FakeAwarenessStorage();
      final controller = AppAwarenessController(
        service: service,
        storage: storage,
        pollInterval: const Duration(milliseconds: 10),
      );

      await controller.enable();
      service.usageAccess = false;

      await controller.resume();

      expect(controller.enabled, isFalse);
      expect(controller.currentApp, isNull);
      expect(controller.lastError, contains('turned off'));
      expect(storage.stored, isFalse);

      controller.dispose();
    });

    test('disable() forgets the current app and the preference', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final storage = FakeAwarenessStorage(stored: true);
      final controller = AppAwarenessController(
        service: service,
        storage: storage,
        pollInterval: const Duration(milliseconds: 10),
      );

      await controller.enable();
      await controller.disable();

      expect(controller.enabled, isFalse);
      expect(controller.currentApp, isNull);
      expect(storage.stored, isFalse);

      // And polling really stopped.
      final calls = service.foregroundCallCount;
      await _settle(30);
      expect(service.foregroundCallCount, calls);

      controller.dispose();
    });

    test('restorePreferences() re-arms a saved preference', () async {
      final controller = AppAwarenessController(
        service: FakeAppAwarenessService(app: _chrome),
        storage: FakeAwarenessStorage(stored: true),
      );

      await controller.restorePreferences();

      expect(controller.enabled, isTrue);
      expect(controller.currentApp, _chrome);

      controller.dispose();
    });

    test('restorePreferences() stays quiet when never switched on', () async {
      final controller = AppAwarenessController(
        service: FakeAppAwarenessService(app: _chrome),
        storage: FakeAwarenessStorage(),
      );

      await controller.restorePreferences();

      expect(controller.enabled, isFalse);
      expect(controller.currentApp, isNull);
      // But it still learns the permission state, so settings can tell the
      // truth before the user touches the switch.
      expect(controller.hasUsageAccess, isTrue);

      controller.dispose();
    });

    test('refreshPermission() reads the state without switching anything on',
        () async {
      final storage = FakeAwarenessStorage();
      final controller = AppAwarenessController(
        service: FakeAppAwarenessService(app: _chrome),
        storage: storage,
      );

      expect(controller.hasUsageAccess, isFalse);

      await controller.refreshPermission();

      expect(controller.hasUsageAccess, isTrue);
      expect(controller.enabled, isFalse);
      expect(controller.currentApp, isNull);
      expect(storage.stored, isNull);

      controller.dispose();
    });

    test('refreshPermission() notices a permission that was revoked', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
      );

      await controller.refreshPermission();
      expect(controller.hasUsageAccess, isTrue);

      service.usageAccess = false;
      await controller.refreshPermission();
      expect(controller.hasUsageAccess, isFalse);

      controller.dispose();
    });

    test('restorePreferences() does not bounce the user to settings', () async {
      final service = FakeAppAwarenessService(usageAccess: false);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(stored: true),
      );

      await controller.restorePreferences();

      expect(service.openSettingsCount, 0);

      controller.dispose();
    });

    test('buildPromptContext() only speaks once the app is known', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
      );

      expect(controller.buildPromptContext(), isNull);

      await controller.enable();
      final context = controller.buildPromptContext();

      expect(context, isNotNull);
      expect(context, contains('Chrome'));
      // Must not imply Kitten can read the screen itself.
      expect(context, contains('not able to see the contents'));

      await controller.disable();
      expect(controller.buildPromptContext(), isNull);

      controller.dispose();
    });

    test('dispose() releases the service and stops polling', () async {
      final service = FakeAppAwarenessService(app: _chrome);
      final controller = AppAwarenessController(
        service: service,
        storage: FakeAwarenessStorage(),
        pollInterval: const Duration(milliseconds: 10),
      );

      await controller.enable();
      controller.dispose();

      expect(service.disposed, isTrue);
      final calls = service.foregroundCallCount;
      await _settle(30);
      expect(service.foregroundCallCount, calls);
    });

    test('a null app is reported as unknown rather than guessed', () async {
      final controller = AppAwarenessController(
        service: FakeAppAwarenessService(),
        storage: FakeAwarenessStorage(),
      );

      await controller.enable();

      expect(controller.enabled, isTrue);
      expect(controller.currentApp, isNull);
      expect(controller.buildPromptContext(), isNull);

      controller.dispose();
    });
  });
}

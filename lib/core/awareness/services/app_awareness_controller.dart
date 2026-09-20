import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kitten/core/awareness/models/foreground_app.dart';
import 'package:kitten/core/awareness/services/app_awareness_service.dart';
import 'package:kitten/core/awareness/services/method_channel_app_awareness_service.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

/// Tracks the app the user is currently using and contributes that context to
/// Kitten's system prompt.
///
/// Usage access is a special permission the user grants in system settings, so
/// the controller never assumes it is available: enabling can legitimately fail,
/// and returning from the settings screen re-checks rather than trusting a
/// cached answer.
class AppAwarenessController extends ChangeNotifier {
  AppAwarenessController({
    AppAwarenessService? service,
    SecureStorageService? storage,
    Duration? pollInterval,
  })  : _injectedService = service,
        _injectedStorage = storage,
        _pollInterval = pollInterval ?? const Duration(seconds: 5);

  final AppAwarenessService? _injectedService;
  final SecureStorageService? _injectedStorage;
  final Duration _pollInterval;

  AppAwarenessService? _service;
  SecureStorageService? _storageInstance;

  Timer? _poller;
  bool _enabled = false;
  bool _hasUsageAccess = false;
  bool _suspended = false;
  bool _refreshing = false;
  bool _disposed = false;
  ForegroundApp? _currentApp;
  String? _lastError;

  AppAwarenessService get _serviceInstance =>
      _service ??= _injectedService ?? MethodChannelAppAwarenessService();

  SecureStorageService get _storageService =>
      _storageInstance ??= _injectedStorage ?? SecureStorageService();

  /// Whether the user has switched app awareness on.
  bool get enabled => _enabled;

  /// Whether this platform can report the foreground app at all.
  bool get isSupported => _serviceInstance.isSupported;

  /// Whether usage access has been granted in system settings.
  bool get hasUsageAccess => _hasUsageAccess;

  /// The app currently in the foreground, or null when unknown or not ours.
  ForegroundApp? get currentApp => _currentApp;

  /// The most recent user-facing problem, or null.
  String? get lastError => _lastError;

  /// Re-applies the saved preference. Call once at startup.
  Future<void> restorePreferences() async {
    // Read the permission even when awareness is off, so the settings screen
    // can describe the real state before the user touches anything.
    await refreshPermission();

    final stored = await _storageService.getAppAwarenessEnabled();
    if (_disposed || stored != true) return;
    await enable(openSettingsIfMissing: false);
  }

  /// Re-reads whether usage access is granted without changing the switch.
  Future<void> refreshPermission() async {
    if (_disposed || !_serviceInstance.isSupported) return;

    final granted = await _serviceInstance.hasUsageAccess();
    if (_disposed || granted == _hasUsageAccess) return;

    _hasUsageAccess = granted;
    _safeNotify();
  }

  /// Switches awareness on, checking the permission first.
  ///
  /// Returns false when usage access is missing; the system settings screen is
  /// opened in that case unless [openSettingsIfMissing] is false, so the user
  /// can grant it in one step. The switch never claims to be on when it cannot
  /// actually see anything.
  Future<bool> enable({bool openSettingsIfMissing = true}) async {
    if (_disposed) return false;

    if (!_serviceInstance.isSupported) {
      _enabled = false;
      _lastError = 'App awareness is only available on Android.';
      await _storageService.saveAppAwarenessEnabled(false);
      _safeNotify();
      return false;
    }

    _hasUsageAccess = await _serviceInstance.hasUsageAccess();
    if (_disposed) return false;

    if (!_hasUsageAccess) {
      _enabled = false;
      _currentApp = null;
      _lastError =
          'Kitten needs Usage access to see which app you are using. Grant it '
          'in system settings, then switch this on again.';
      _stopPolling();
      await _storageService.saveAppAwarenessEnabled(false);
      _safeNotify();

      if (openSettingsIfMissing) {
        await _serviceInstance.openUsageAccessSettings();
      }
      return false;
    }

    _enabled = true;
    await _storageService.saveAppAwarenessEnabled(true);
    _lastError = null;
    await _startPolling();
    return true;
  }

  /// Switches awareness off and forgets the current app.
  Future<void> disable() async {
    _enabled = false;
    _currentApp = null;
    _lastError = null;
    _stopPolling();
    await _storageService.saveAppAwarenessEnabled(false);
    _safeNotify();
  }

  /// Opens the system screen where usage access is granted.
  Future<void> openUsageAccessSettings() =>
      _serviceInstance.openUsageAccessSettings();

  /// Reads the foreground app once, if allowed.
  Future<void> refresh({bool force = false}) async {
    if (_disposed || !_enabled || !_hasUsageAccess) return;
    if (_suspended && !force) return;
    // Polling can outrun a slow platform call; skip rather than overlap.
    if (_refreshing) return;

    _refreshing = true;
    try {
      final app = await _serviceInstance.foregroundApp();
      if (_disposed) return;
      if (app != _currentApp) {
        _currentApp = app;
        _safeNotify();
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Stops polling because the app left the foreground.
  Future<void> suspend() async {
    _suspended = true;
    _stopPolling();
  }

  /// Resumes polling, re-checking the permission because the user may have
  /// changed it while away.
  Future<void> resume() async {
    _suspended = false;
    if (_disposed || !_enabled) return;

    _hasUsageAccess = await _serviceInstance.hasUsageAccess();
    if (_disposed) return;

    if (_hasUsageAccess) {
      _lastError = null;
      await _startPolling();
    } else {
      // Access was revoked while we were away; stop reading rather than show
      // a stale app.
      _enabled = false;
      _currentApp = null;
      _lastError = 'Usage access was turned off, so Kitten stopped watching.';
      _stopPolling();
      await _storageService.saveAppAwarenessEnabled(false);
    }
    _safeNotify();
  }

  /// The prompt section describing the foreground app, or null when there is
  /// nothing useful (or permitted) to say.
  String? buildPromptContext() {
    final app = _currentApp;
    if (!_enabled || app == null) return null;

    return 'CURRENT CONTEXT:\n'
        'The user currently has "${app.displayName}" open in the foreground. '
        'You may refer to it naturally when it is relevant, but you are not '
        'able to see the contents of their screen.';
  }

  Future<void> _startPolling() async {
    _stopPolling();
    if (_disposed || !_enabled || _suspended || !_hasUsageAccess) return;

    await refresh();
    if (_disposed || !_enabled) return;

    _poller = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    // Only dispose a service we created ourselves.
    _service?.dispose();
    super.dispose();
  }
}

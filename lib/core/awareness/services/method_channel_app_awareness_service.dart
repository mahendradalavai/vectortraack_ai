import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:kitten/core/awareness/models/foreground_app.dart';
import 'package:kitten/core/awareness/services/app_awareness_service.dart';

/// [AppAwarenessService] backed by a small native channel.
///
/// Android's usage APIs need the `GET_USAGE_STATS` app-op, which has no
/// plugin-visible equivalent, so the few lines of platform code live beside
/// the app's own `MainActivity` rather than pulling in another dependency.
///
/// Every call fails soft: a missing plugin or a platform error degrades to
/// "no awareness" instead of throwing into the UI.
class MethodChannelAppAwarenessService implements AppAwarenessService {
  MethodChannelAppAwarenessService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'kitten/app_awareness';

  final MethodChannel _channel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> hasUsageAccess() async {
    if (!isSupported) return false;

    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openUsageAccessSettings() async {
    if (!isSupported) return;

    try {
      await _channel.invokeMethod<bool>('openUsageAccessSettings');
    } on PlatformException {
      // Opening settings is best-effort; the user can navigate manually.
    } on MissingPluginException {
      // Nothing to open on this platform.
    }
  }

  @override
  Future<ForegroundApp?> foregroundApp() async {
    if (!isSupported) return null;

    try {
      final result =
          await _channel.invokeMapMethod<String, String>('foregroundApp');
      if (result == null) return null;

      final packageName = result['packageName'];
      if (packageName == null || packageName.isEmpty) return null;

      final label = result['label'];
      return ForegroundApp(
        packageName: packageName,
        label: label == null || label.isEmpty ? null : label,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void dispose() {}
}

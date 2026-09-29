import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:kitten/core/overlay/models/overlay_app_context.dart';

import 'floating_overlay_service.dart';

/// Android implementation of the floating overlay contract.
class MethodChannelFloatingOverlayService implements FloatingOverlayService {
  MethodChannelFloatingOverlayService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'kitten/floating_overlay';
  final MethodChannel _channel;

  /// The live receiver for handed-over apps, if any.
  void Function(OverlayAppContext context)? _openingHandler;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> hasOverlayPermission() => _invokeBool('hasOverlayPermission');

  @override
  Future<bool> openOverlaySettings() => _invokeBool('openOverlaySettings');

  @override
  Future<bool> startFloatingKitten() => _invokeBool('startFloatingKitten');

  @override
  Future<bool> stopFloatingKitten() => _invokeBool('stopFloatingKitten');

  @override
  Future<bool> isFloatingKittenRunning() =>
      _invokeBool('isFloatingKittenRunning');

  @override
  void handleAppOpenings(void Function(OverlayAppContext context)? handler) {
    if (!isSupported) return;
    _openingHandler = handler;
    if (handler == null) {
      // Only step aside if this instance owns the handler: Settings and the
      // home page can share one channel, and clearing it blindly would silence
      // the other listener.
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  @override
  Future<OverlayAppContext?> takePendingAppContext() async {
    try {
      final payload = await _channel.invokeMethod<Object?>('takeAppContext');
      return OverlayAppContext.fromChannel(payload);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> acknowledgeAppContext() async {
    try {
      await _channel.invokeMethod<bool>('acknowledgeAppContext');
    } on MissingPluginException {
      // Nothing is stashed when the platform side does not exist.
    } on PlatformException {
      // Acknowledgement is best effort; the Dart side also ignores repeats.
    }
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    if (call.method == 'appContextOpened') {
      final context = OverlayAppContext.fromChannel(call.arguments);
      if (context != null) _openingHandler?.call(context);
    }
    return null;
  }

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

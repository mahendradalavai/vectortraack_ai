import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:kitten/core/screen/services/screen_capture_service.dart';

/// [ScreenCaptureService] backed by the `kitten/screen_capture` channel.
///
/// The consent dialog, projection, and one-shot foreground service all live in
/// the platform code; this class only forwards the request and translates
/// platform failures into typed exceptions. Every call fails soft so a missing
/// plugin or a platform error degrades to "no screen understanding" instead of
/// throwing into the UI.
class MethodChannelScreenCaptureService implements ScreenCaptureService {
  MethodChannelScreenCaptureService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'kitten/screen_capture';

  final MethodChannel _channel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String?> captureScreen() async {
    if (!isSupported) {
      throw const ScreenCaptureException(ScreenCaptureException.failedCode);
    }

    try {
      // The platform side sends the JPEG as raw bytes; base64 is applied here
      // because that is the shape the model request needs.
      final bytes = await _channel
          .invokeMethod<Uint8List>('captureScreen')
          .timeout(const Duration(seconds: 45));
      if (bytes == null) return null;
      if (bytes.isEmpty) return '';
      return base64Encode(bytes);
    } on PlatformException catch (error) {
      if (error.code == 'busy') {
        throw ScreenCaptureException(ScreenCaptureException.busyCode);
      }
      throw ScreenCaptureException(
        ScreenCaptureException.failedCode,
        error.message,
      );
    } on MissingPluginException {
      throw const ScreenCaptureException(ScreenCaptureException.failedCode);
    } on TimeoutException {
      throw const ScreenCaptureException(ScreenCaptureException.timeoutCode);
    }
  }

  @override
  void dispose() {}
}

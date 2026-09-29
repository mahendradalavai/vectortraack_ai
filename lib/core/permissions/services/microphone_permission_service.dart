import 'package:flutter/services.dart';

/// Reads the Android microphone permission without requesting it implicitly.
class MicrophonePermissionService {
  MicrophonePermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'kitten/permissions';
  final MethodChannel _channel;

  Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>('hasMicrophonePermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openMicrophoneSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

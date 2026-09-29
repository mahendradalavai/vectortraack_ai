import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'background_assistant_service.dart';

class MethodChannelBackgroundAssistantService
    implements BackgroundAssistantService {
  MethodChannelBackgroundAssistantService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'kitten/background_assistant';
  final MethodChannel _channel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isEnabled() => _invoke('isEnabled');

  @override
  Future<bool> start() => _invoke('start');

  @override
  Future<bool> stop() => _invoke('stop');

  Future<bool> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

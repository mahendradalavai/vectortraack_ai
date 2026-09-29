import 'package:flutter/services.dart';

import 'phone_capability_service.dart';

/// Android implementation backed by system intents.
class MethodChannelPhoneCapabilityService implements PhoneCapabilityService {
  MethodChannelPhoneCapabilityService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'kitten/phone_capabilities';
  final MethodChannel _channel;

  @override
  bool get isSupported => true;

  @override
  Future<PhoneActionResult> openDialer(String phoneNumber) =>
      _invoke('openDialer', {'phoneNumber': phoneNumber});

  @override
  Future<PhoneActionResult> composeMessage({
    required String phoneNumber,
    required String message,
  }) => _invoke('composeMessage', {
    'phoneNumber': phoneNumber,
    'message': message,
  });

  @override
  Future<PhoneActionResult> setAlarm({
    required int hour,
    required int minute,
    String? message,
  }) => _invoke('setAlarm', {
    'hour': hour,
    'minute': minute,
    'message': ?message,
  });

  @override
  Future<PhoneActionResult> setTimer({required int seconds, String? message}) =>
      _invoke('setTimer', {
        'seconds': seconds,
        'message': ?message,
      });

  @override
  Future<PhoneActionResult> openApp(String packageName) =>
      _invoke('openApp', {'packageName': packageName});

  Future<PhoneActionResult> _invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        arguments,
      );
      final success = result?['success'] == true;
      return success
          ? PhoneActionResult.ok(result?['message'] as String?)
          : PhoneActionResult.failure(
              result?['message'] as String? ??
                  'The action could not be opened.',
            );
    } on MissingPluginException {
      return const PhoneActionResult.failure(
        'Phone actions are not available on this device.',
      );
    } on PlatformException catch (error) {
      return PhoneActionResult.failure(
        error.message ?? 'The phone action could not be opened.',
      );
    }
  }
}

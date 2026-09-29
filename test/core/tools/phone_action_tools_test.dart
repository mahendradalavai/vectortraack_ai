import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/phone/services/phone_capability_service.dart';
import 'package:kitten/core/tools/built_in/phone_action_tools.dart';

class FakePhoneCapabilityService implements PhoneCapabilityService {
  String? dialedNumber;
  String? messageNumber;
  String? messageBody;
  int? alarmHour;
  int? alarmMinute;
  int? timerSeconds;
  String? openedPackage;

  @override
  bool get isSupported => true;

  @override
  Future<PhoneActionResult> openDialer(String phoneNumber) async {
    dialedNumber = phoneNumber;
    return const PhoneActionResult.ok('dialer opened');
  }

  @override
  Future<PhoneActionResult> composeMessage({
    required String phoneNumber,
    required String message,
  }) async {
    messageNumber = phoneNumber;
    messageBody = message;
    return const PhoneActionResult.ok('message composer opened');
  }

  @override
  Future<PhoneActionResult> setAlarm({
    required int hour,
    required int minute,
    String? message,
  }) async {
    alarmHour = hour;
    alarmMinute = minute;
    return const PhoneActionResult.ok('alarm opened');
  }

  @override
  Future<PhoneActionResult> setTimer({
    required int seconds,
    String? message,
  }) async {
    timerSeconds = seconds;
    return const PhoneActionResult.ok('timer opened');
  }

  @override
  Future<PhoneActionResult> openApp(String packageName) async {
    openedPackage = packageName;
    return const PhoneActionResult.ok('app opened');
  }
}

void main() {
  group('phone action tools', () {
    late FakePhoneCapabilityService service;

    setUp(() => service = FakePhoneCapabilityService());

    test('opens the dialer without placing a call', () async {
      final result = await OpenDialerTool(service)
          .execute({'phone_number': '  +1 555 0100 '});

      expect(result.isSuccess, isTrue);
      expect(service.dialedNumber, '+1 555 0100');
    });

    test('requires a message recipient and body', () async {
      final result = await ComposeMessageTool(service)
          .execute({'phone_number': '+15550100'});

      expect(result.isSuccess, isFalse);
      expect(service.messageNumber, isNull);
    });

    test('validates alarm and timer ranges before delegating', () async {
      final alarm = await SetAlarmTool(service)
          .execute({'hour': 24, 'minute': 0});
      final timer = await SetTimerTool(service).execute({'seconds': 0});

      expect(alarm.isSuccess, isFalse);
      expect(timer.isSuccess, isFalse);
      expect(service.alarmHour, isNull);
      expect(service.timerSeconds, isNull);
    });

    test('delegates valid alarm, timer, and app requests', () async {
      await SetAlarmTool(service).execute({'hour': 7, 'minute': 5});
      await SetTimerTool(service).execute({'seconds': 90});
      await OpenAppTool(service)
          .execute({'package_name': 'com.android.chrome'});

      expect(service.alarmHour, 7);
      expect(service.alarmMinute, 5);
      expect(service.timerSeconds, 90);
      expect(service.openedPackage, 'com.android.chrome');
    });
  });
}

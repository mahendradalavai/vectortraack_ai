/// Result of asking the operating system to perform a phone action.
class PhoneActionResult {
  const PhoneActionResult({required this.success, this.message});

  const PhoneActionResult.ok([this.message])
    : success = true;

  const PhoneActionResult.failure(this.message) : success = false;

  final bool success;
  final String? message;
}

/// Platform capabilities that Kitten can hand off to the operating system.
abstract interface class PhoneCapabilityService {
  bool get isSupported;

  Future<PhoneActionResult> openDialer(String phoneNumber);

  Future<PhoneActionResult> composeMessage({
    required String phoneNumber,
    required String message,
  });

  Future<PhoneActionResult> setAlarm({
    required int hour,
    required int minute,
    String? message,
  });

  Future<PhoneActionResult> setTimer({required int seconds, String? message});

  Future<PhoneActionResult> openApp(String packageName);
}

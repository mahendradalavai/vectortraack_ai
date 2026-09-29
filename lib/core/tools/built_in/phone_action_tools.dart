import 'package:kitten/core/phone/services/phone_capability_service.dart';
import 'package:kitten/core/tools/kitten_tool.dart';

class OpenDialerTool implements KittenTool {
  const OpenDialerTool(this.service);

  final PhoneCapabilityService service;

  @override
  String get name => 'open_dialer';

  @override
  String get description =>
      'Open the phone dialer with a phone number ready. It does not place a call automatically.';

  @override
  Map<String, dynamic> get parametersSchema => const {
    'type': 'object',
    'properties': {
      'phone_number': {
        'type': 'string',
        'description': 'The phone number to show in the dialer.',
      },
    },
    'required': ['phone_number'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final phoneNumber = arguments['phone_number'] as String?;
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      return const ToolResult.failure('A phone number is required.');
    }
    return _result(await service.openDialer(phoneNumber.trim()));
  }
}

class ComposeMessageTool implements KittenTool {
  const ComposeMessageTool(this.service);

  final PhoneCapabilityService service;

  @override
  String get name => 'compose_message';

  @override
  String get description =>
      'Open the SMS composer with a recipient and message filled in. It never sends automatically.';

  @override
  Map<String, dynamic> get parametersSchema => const {
    'type': 'object',
    'properties': {
      'phone_number': {'type': 'string'},
      'message': {'type': 'string'},
    },
    'required': ['phone_number', 'message'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final phoneNumber = arguments['phone_number'] as String?;
    final message = arguments['message'] as String?;
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      return const ToolResult.failure('A phone number is required.');
    }
    if (message == null || message.trim().isEmpty) {
      return const ToolResult.failure('A message is required.');
    }
    return _result(
      await service.composeMessage(
        phoneNumber: phoneNumber.trim(),
        message: message.trim(),
      ),
    );
  }
}

class SetAlarmTool implements KittenTool {
  const SetAlarmTool(this.service);

  final PhoneCapabilityService service;

  @override
  String get name => 'set_alarm';

  @override
  String get description =>
      'Open the system clock to create an alarm at a local 24-hour time.';

  @override
  Map<String, dynamic> get parametersSchema => const {
    'type': 'object',
    'properties': {
      'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
      'minute': {'type': 'integer', 'minimum': 0, 'maximum': 59},
      'message': {'type': 'string'},
    },
    'required': ['hour', 'minute'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final hour = _integer(arguments['hour']);
    final minute = _integer(arguments['minute']);
    if (hour == null || hour < 0 || hour > 23) {
      return const ToolResult.failure(
        'The alarm hour must be between 0 and 23.',
      );
    }
    if (minute == null || minute < 0 || minute > 59) {
      return const ToolResult.failure(
        'The alarm minute must be between 0 and 59.',
      );
    }
    return _result(
      await service.setAlarm(
        hour: hour,
        minute: minute,
        message: arguments['message'] as String?,
      ),
    );
  }
}

class SetTimerTool implements KittenTool {
  const SetTimerTool(this.service);

  final PhoneCapabilityService service;

  @override
  String get name => 'set_timer';

  @override
  String get description =>
      'Open the system clock timer with a duration in seconds.';

  @override
  Map<String, dynamic> get parametersSchema => const {
    'type': 'object',
    'properties': {
      'seconds': {'type': 'integer', 'minimum': 1},
      'message': {'type': 'string'},
    },
    'required': ['seconds'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final seconds = _integer(arguments['seconds']);
    if (seconds == null || seconds < 1) {
      return const ToolResult.failure('The timer must be at least one second.');
    }
    return _result(
      await service.setTimer(
        seconds: seconds,
        message: arguments['message'] as String?,
      ),
    );
  }
}

class OpenAppTool implements KittenTool {
  const OpenAppTool(this.service);

  final PhoneCapabilityService service;

  @override
  String get name => 'open_app';

  @override
  String get description =>
      'Open an installed Android app by its package name, such as com.android.chrome.';

  @override
  Map<String, dynamic> get parametersSchema => const {
    'type': 'object',
    'properties': {
      'package_name': {'type': 'string'},
    },
    'required': ['package_name'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final packageName = arguments['package_name'] as String?;
    if (packageName == null || packageName.trim().isEmpty) {
      return const ToolResult.failure('An app package name is required.');
    }
    return _result(await service.openApp(packageName.trim()));
  }
}

int? _integer(Object? value) => value is int ? value : int.tryParse('$value');

ToolResult _result(PhoneActionResult result) => result.success
    ? ToolResult.ok({'message': result.message ?? 'Done.'})
    : ToolResult.failure(
        result.message ?? 'The phone action could not be opened.',
      );

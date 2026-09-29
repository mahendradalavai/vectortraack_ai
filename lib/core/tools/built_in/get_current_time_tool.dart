import 'package:kitten/core/tools/kitten_tool.dart';

/// Lets Kitten answer "what time is it?" without guessing.
///
/// Models have no clock, so without this the honest answer is "I don't know".
class GetCurrentTimeTool implements KittenTool {
  const GetCurrentTimeTool();

  @override
  String get name => 'get_current_time';

  @override
  String get description =>
      'Get the current date and time on the user\'s device. Use this whenever '
      'an answer depends on what time or date it is right now.';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final now = DateTime.now();

    return ToolResult.ok({
      'iso8601': now.toIso8601String(),
      'localTime': '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}',
      'weekday': _weekdayName(now.weekday),
      'date': '${_twoDigits(now.year)}-${_twoDigits(now.month)}-${_twoDigits(now.day)}',
    });
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _weekdayName(int weekday) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][weekday - 1];
}

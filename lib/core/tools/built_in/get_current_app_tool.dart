import 'package:kitten/core/awareness/services/app_awareness_controller.dart';
import 'package:kitten/core/tools/kitten_tool.dart';

/// Lets Kitten *ask* which app is open instead of only being told.
///
/// App awareness already feeds the foreground app into every turn's context;
/// this tool exists for turns where Kitten needs it explicitly, such as when
/// the user asks what it can see. It reports honestly when awareness is off
/// rather than inventing an app.
class GetCurrentAppTool implements KittenTool {
  const GetCurrentAppTool(this.controller);

  final AppAwarenessController? controller;

  @override
  String get name => 'get_current_app';

  @override
  String get description =>
      'Find out which app the user was most recently using. Only works when '
      'the user has granted app awareness; it cannot see inside the app.';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final awareness = controller;
    if (awareness == null || !awareness.isSupported) {
      return const ToolResult.failure(
        'App awareness is not available on this device.',
      );
    }
    if (!awareness.enabled) {
      return const ToolResult.failure(
        'The user has not turned app awareness on.',
      );
    }

    await awareness.refresh();
    final app = awareness.currentApp;
    if (app == null) {
      return const ToolResult.failure(
        'No recent app is known right now.',
      );
    }

    return ToolResult.ok({
      'app': app.displayName,
      'package': app.packageName,
    });
  }
}

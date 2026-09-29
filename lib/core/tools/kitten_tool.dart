import 'dart:convert';

/// What a tool reports back after running.
///
/// Tools are allowed to fail; the failure is reported to the model as part of
/// the conversation rather than crashing the turn, so Kitten can explain or
/// try something else.
class ToolResult {
  const ToolResult.ok(this.payload)
      : error = null,
        assert(payload != null);

  const ToolResult.failure(this.error)
      : payload = null,
        assert(error != null);

  /// A JSON-encodable payload on success.
  final Map<String, dynamic>? payload;

  /// A short, user-safe explanation on failure.
  final String? error;

  bool get isSuccess => error == null;

  /// The message content sent back to the model for this tool call.
  ///
  /// Always JSON so the model can parse it consistently, success or not.
  String asToolMessageContent() => jsonEncode(
        isSuccess ? payload : <String, dynamic>{'error': error},
      );
}

/// A capability Kitten can ask the model to use.
///
/// Implementations stay platform-agnostic where possible: anything that needs
/// Android talks through one of the existing `core` services, keeping tools
/// testable without a device.
abstract class KittenTool {
  /// The name the model calls it by. Lower-case snake_case, as models expect.
  String get name;

  /// What it is for. This is what the model reads when deciding to use it, so
  /// it should say when the tool is useful *and* when it is not.
  String get description;

  /// A JSON schema for the arguments. An empty-object schema means the tool
  /// takes no arguments.
  Map<String, dynamic> get parametersSchema;

  /// Runs the tool. Must never throw; report failure through [ToolResult].
  Future<ToolResult> execute(Map<String, dynamic> arguments);
}

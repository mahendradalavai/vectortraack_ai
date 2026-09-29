import 'dart:convert';

/// One function the model asked Kitten to run.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    this.argumentsJson = '{}',
  });

  /// The provider's identifier for this call, echoed back with the result.
  final String id;

  /// The tool name, matching a registered [KittenTool].
  final String name;

  /// The arguments as a JSON string, exactly as the model produced them.
  final String argumentsJson;

  /// The arguments decoded defensively: malformed JSON becomes an empty map
  /// rather than an exception, so one bad call cannot break the whole turn.
  Map<String, dynamic> decodedArguments() {
    try {
      final decoded = jsonDecode(argumentsJson);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  factory ToolCall.fromGroqJson(Map<String, dynamic> json) {
    final function = json['function'] as Map<String, dynamic>?;
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: function?['name'] as String? ?? '',
      argumentsJson: function?['arguments'] as String? ?? '{}',
    );
  }

  /// The OpenAI-compatible shape an assistant message carries so the model
  /// can see which calls it made earlier in the conversation.
  Map<String, dynamic> toGroqJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': argumentsJson},
      };

  @override
  String toString() => 'ToolCall($name, $argumentsJson)';
}

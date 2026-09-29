import 'package:kitten/core/tools/models/tool_call.dart';

/// Encapsulates the response from an AI provider chat completion.
class ChatResponse {
  const ChatResponse({
    required this.content,
    required this.model,
    this.toolCalls = const [],
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  factory ChatResponse.fromGroqJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('Empty choices in Groq response');
    }

    final firstChoice = choices[0] as Map<String, dynamic>;
    final message = firstChoice['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String? ?? '';
    final finishReason = firstChoice['finish_reason'] as String?;
    final model = json['model'] as String? ?? 'unknown';

    final rawCalls = message?['tool_calls'] as List<dynamic>?;
    final toolCalls = rawCalls == null
        ? const <ToolCall>[]
        : [
            for (final call in rawCalls)
              if (call is Map<String, dynamic>) ToolCall.fromGroqJson(call),
          ];

    final usage = json['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int?;
    final completionTokens = usage?['completion_tokens'] as int?;
    final totalTokens = usage?['total_tokens'] as int?;

    return ChatResponse(
      content: content.trim(),
      model: model,
      toolCalls: toolCalls,
      finishReason: finishReason,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  final String content;
  final String model;

  /// The tool calls the model asked for, empty for a plain text answer.
  final List<ToolCall> toolCalls;

  /// Whether this response wants tools run rather than being shown as text.
  bool get hasToolCalls => toolCalls.isNotEmpty;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

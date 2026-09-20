/// Encapsulates the response from an AI provider chat completion.
class ChatResponse {
  const ChatResponse({
    required this.content,
    required this.model,
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

    final usage = json['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int?;
    final completionTokens = usage?['completion_tokens'] as int?;
    final totalTokens = usage?['total_tokens'] as int?;

    return ChatResponse(
      content: content.trim(),
      model: model,
      finishReason: finishReason,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
    );
  }

  final String content;
  final String model;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

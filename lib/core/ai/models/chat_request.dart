import 'package:kitten/core/ai/models/chat_message.dart';

/// Encapsulates a chat completion request to an AI provider.
class ChatRequest {
  const ChatRequest({
    required this.messages,
    this.model,
    this.temperature = 0.7,
    this.maxTokens = 1024,
  });

  final List<ChatMessage> messages;
  final String? model;
  final double temperature;
  final int maxTokens;

  /// Serializes the request into an OpenAI-compatible payload.
  ///
  /// When [stream] is true, the provider is asked to return server-sent
  /// events instead of a single completion object.
  Map<String, dynamic> toJson({
    required String defaultModel,
    bool stream = false,
  }) => {
        'model': model ?? defaultModel,
        'messages': messages.map((m) => m.toJson()).toList(),
        'temperature': temperature,
        'max_tokens': maxTokens,
        if (stream) 'stream': true,
      };
}

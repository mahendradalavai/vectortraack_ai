import 'package:kitten/core/ai/models/chat_message.dart';

/// Encapsulates a chat completion request to an AI provider.
class ChatRequest {
  const ChatRequest({
    required this.messages,
    this.model,
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.tools,
  });

  final List<ChatMessage> messages;
  final String? model;
  final double temperature;
  final int maxTokens;

  /// The tools the model may call, already in OpenAI-compatible shape, or null
  /// when this turn should be a plain text exchange.
  final List<Map<String, dynamic>>? tools;

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
        // Offered with 'auto' choice so the model may simply answer in text
        // when no tool would help.
        if (tools != null && tools!.isNotEmpty) ...{
          'tools': tools,
          'tool_choice': 'auto',
        },
      };

  /// A copy of this request told to use [model] instead.
  ///
  /// Vision models are only good at pictures, so a screen-understanding turn
  /// asks for a specific multimodal model rather than the user's text model.
  ChatRequest withModel(String model) => ChatRequest(
        messages: messages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        tools: tools,
      );
}

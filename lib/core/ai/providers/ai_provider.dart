import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';

/// Abstract contract for an AI provider.
///
/// Designed to support any LLM backend (Groq, Gemini, OpenAI, etc.)
/// without coupling business or presentation logic to vendor APIs.
abstract class AiProvider {
  /// User-friendly identifier for the provider (e.g. 'Groq').
  String get providerName;

  /// Sends a conversation completion request and returns the AI response.
  Future<ChatResponse> sendMessage(ChatRequest request);

  /// Streams a conversation completion as incremental text deltas.
  ///
  /// Providers that cannot stream server-sent events may rely on this
  /// default implementation, which emits the complete response as a single
  /// chunk so callers can treat every provider uniformly.
  Stream<String> streamMessage(ChatRequest request) async* {
    final response = await sendMessage(request);
    if (response.content.isNotEmpty) {
      yield response.content;
    }
  }

  /// Performs a lightweight connectivity & authentication test against the provider.
  ///
  /// Returns `true` on success, or throws an [AiException] on failure.
  Future<bool> checkConnection();

  /// Releases any resources held by the provider (e.g. HTTP clients).
  ///
  /// Defaults to a no-op so lightweight or injected providers need not care.
  void dispose() {}
}

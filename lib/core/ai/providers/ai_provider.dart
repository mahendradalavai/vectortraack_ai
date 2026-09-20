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

  /// Performs a lightweight connectivity & authentication test against the provider.
  ///
  /// Returns `true` on success, or throws an [AiException] on failure.
  Future<bool> checkConnection();
}

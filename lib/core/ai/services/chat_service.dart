import 'package:flutter/foundation.dart';

import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_message.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/prompts/kitten_system_prompt.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/ai/providers/groq_provider.dart';
import 'package:kitten/core/models/assistant_state.dart';

/// Orchestrates chat conversation flow between the user interface
/// and the configured [AiProvider].
///
/// Keeps active session messages, prepends the Kitten personality prompt,
/// and tracks the assistant's runtime state (idle -> thinking -> idle).
class ChatService extends ChangeNotifier {
  ChatService({AiProvider? provider}) : _provider = provider ?? GroqProvider();

  AiProvider _provider;
  final List<ChatMessage> _messages = [];
  AssistantState _assistantState = AssistantState.idle;
  String? _lastError;

  /// Returns an unmodifiable view of visible conversation messages (excluding system prompt).
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  AssistantState get assistantState => _assistantState;
  String? get lastError => _lastError;
  AiProvider get provider => _provider;

  /// Updates the underlying AI provider.
  void setProvider(AiProvider provider) {
    _provider = provider;
    notifyListeners();
  }

  /// Clears the current conversation history and errors.
  void clearConversation() {
    _messages.clear();
    _lastError = null;
    _assistantState = AssistantState.idle;
    notifyListeners();
  }

  /// Sends a text message from the user, updates state to [AssistantState.thinking],
  /// invokes the AI provider with system prompt and history, and updates state to [AssistantState.idle].
  Future<ChatMessage?> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final userMessage = ChatMessage.user(trimmed);
    _messages.add(userMessage);
    _lastError = null;
    _assistantState = AssistantState.thinking;
    notifyListeners();

    try {
      // Construct full request including system prompt and conversation history.
      final conversationPayload = [
        ChatMessage.system(KittenSystemPrompt.prompt),
        ..._messages,
      ];

      final request = ChatRequest(messages: conversationPayload);
      final ChatResponse response = await _provider.sendMessage(request);

      final assistantMessage = ChatMessage.assistant(response.content);
      _messages.add(assistantMessage);
      _assistantState = AssistantState.idle;
      notifyListeners();
      return assistantMessage;
    } on AiException catch (e) {
      _lastError = e.userFriendlyMessage;
      _assistantState = AssistantState.idle;
      notifyListeners();
      return null;
    } catch (e) {
      _lastError = 'An unexpected error occurred. Please try again.';
      _assistantState = AssistantState.idle;
      notifyListeners();
      return null;
    }
  }
}

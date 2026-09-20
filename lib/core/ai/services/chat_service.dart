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
  final StringBuffer _streamBuffer = StringBuffer();

  AssistantState _assistantState = AssistantState.idle;
  String? _lastError;
  AiErrorType? _lastErrorType;
  bool _isStreaming = false;
  bool _cancelRequested = false;

  /// Returns an unmodifiable view of visible conversation messages (excluding system prompt).
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  AssistantState get assistantState => _assistantState;
  String? get lastError => _lastError;

  /// Categorized reason for the most recent failure, or null when the last
  /// turn succeeded. Prefer this over inspecting [lastError] text.
  AiErrorType? get lastErrorType => _lastErrorType;

  AiProvider get provider => _provider;

  /// Whether a streaming response is currently being received.
  bool get isStreaming => _isStreaming;

  /// The partially received assistant message, or null when not streaming.
  ChatMessage? get streamingMessage =>
      _isStreaming ? ChatMessage.assistant(_streamBuffer.toString()) : null;

  /// Whether the last error can only be fixed by the user visiting Settings
  /// (i.e. a missing or rejected API key).
  bool get lastErrorRequiresSettings =>
      _lastErrorType == AiErrorType.missingApiKey ||
      _lastErrorType == AiErrorType.invalidApiKey;

  /// Updates the underlying AI provider.
  void setProvider(AiProvider provider) {
    _provider = provider;
    notifyListeners();
  }

  /// Clears the current conversation history, streaming buffer, and errors.
  void clearConversation() {
    _messages.clear();
    _lastError = null;
    _lastErrorType = null;
    _streamBuffer.clear();
    _isStreaming = false;
    _cancelRequested = false;
    _assistantState = AssistantState.idle;
    notifyListeners();
  }

  /// Sends a text message from the user and awaits a single complete response.
  ///
  /// Prefer [sendMessageStreaming] for interactive UIs; this path is kept as a
  /// simple fallback for providers or callers that cannot consume a stream.
  Future<ChatMessage?> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    _beginTurn(trimmed);

    try {
      final request = ChatRequest(messages: _conversationPayload());
      final ChatResponse response = await _provider.sendMessage(request);

      final assistantMessage = ChatMessage.assistant(response.content);
      _messages.add(assistantMessage);
      _completeTurn();
      return assistantMessage;
    } catch (error) {
      _failTurn(error);
      return null;
    }
  }

  /// Sends a text message and surfaces Kitten's reply incrementally.
  ///
  /// The partial response is exposed via [streamingMessage] while deltas
  /// arrive, then committed to [messages] once the stream completes.
  Future<ChatMessage?> sendMessageStreaming(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    _beginTurn(trimmed);
    _isStreaming = true;
    _streamBuffer.clear();
    notifyListeners();

    var cancelled = false;

    try {
      final request = ChatRequest(messages: _conversationPayload());

      await for (final delta in _provider.streamMessage(request)) {
        if (_cancelRequested) {
          cancelled = true;
          break;
        }
        _streamBuffer.write(delta);
        notifyListeners();
      }

      _cancelRequested = false;
      final content = _streamBuffer.toString().trim();
      _isStreaming = false;
      _streamBuffer.clear();

      if (content.isEmpty) {
        if (cancelled) {
          // The user stopped before any text arrived: end the turn quietly.
          _assistantState = AssistantState.idle;
          notifyListeners();
          return null;
        }
        throw AiException.badResponse('Groq returned an empty response.');
      }

      final assistantMessage = ChatMessage.assistant(content);
      _messages.add(assistantMessage);
      _completeTurn();
      return assistantMessage;
    } catch (error) {
      // Guard against a repeated reset if the error happened after finalizing.
      _isStreaming = false;
      _cancelRequested = false;
      _failTurn(error);
      return null;
    }
  }

  /// Requests cancellation of an in-flight streaming response.
  ///
  /// Any text already received is kept and committed as Kitten's reply.
  void cancelStreaming() {
    if (_isStreaming) {
      _cancelRequested = true;
    }
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  /// Appends the user's message and marks Kitten as thinking.
  void _beginTurn(String trimmed) {
    _messages.add(ChatMessage.user(trimmed));
    _lastError = null;
    _lastErrorType = null;
    _cancelRequested = false;
    _assistantState = AssistantState.thinking;
    notifyListeners();
  }

  /// The full payload sent to the provider: system prompt plus history.
  List<ChatMessage> _conversationPayload() => [
        ChatMessage.system(KittenSystemPrompt.prompt),
        ..._messages,
      ];

  void _completeTurn() {
    _assistantState = AssistantState.idle;
    notifyListeners();
  }

  void _failTurn(Object error) {
    if (error is AiException) {
      _lastError = error.userFriendlyMessage;
      _lastErrorType = error.type;
    } else {
      _lastError = 'An unexpected error occurred. Please try again.';
      _lastErrorType = AiErrorType.unknown;
    }
    _assistantState = AssistantState.idle;
    notifyListeners();
  }
}

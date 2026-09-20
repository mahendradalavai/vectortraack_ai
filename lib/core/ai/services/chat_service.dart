import 'package:flutter/foundation.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_message.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/ai/providers/groq_provider.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/personality/services/personality_service.dart';

/// Orchestrates chat conversation flow between the user interface
/// and the configured [AiProvider].
///
/// Keeps active session messages, prepends the Kitten personality prompt,
/// and tracks the assistant's runtime state (idle -> thinking -> idle).
class ChatService extends ChangeNotifier {
  ChatService({
    AiProvider? provider,
    PersonalityService? personality,
    String? Function()? contextProvider,
  })  : _provider = provider ?? GroqProvider(),
        _ownsPersonality = personality == null,
        _promptContext = contextProvider,
        personality = personality ?? PersonalityService() {
    // Mood changes should repaint the UI just like new messages do.
    this.personality.addListener(_onPersonalityChanged);
  }

  /// Tracks Kitten's mood, which is folded into the system prompt.
  final PersonalityService personality;

  final bool _ownsPersonality;

  /// Supplies extra prompt context for the current turn, such as the app the
  /// user was last using. A callback keeps this layer unaware of app
  /// awareness, which owns that knowledge.
  final String? Function()? _promptContext;

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

  /// Sends a question together with a screenshot for Kitten to look at.
  ///
  /// The reply streams exactly like [sendMessageStreaming], but the turn is
  /// routed to a vision-capable model because the everyday text model cannot
  /// read images.
  Future<ChatMessage?> sendMessageWithImage(
    String text,
    String imageBase64, {
    String imageMimeType = 'image/jpeg',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    _beginTurn(
      ChatMessage.userWithImage(
        trimmed,
        imageBase64,
        imageMimeType: imageMimeType,
      ),
    );
    return _streamReply(AiConfig.visionModel);
  }

  /// Sends a text message from the user and awaits a single complete response.
  ///
  /// Prefer [sendMessageStreaming] for interactive UIs; this path is kept as a
  /// simple fallback for providers or callers that cannot consume a stream.
  Future<ChatMessage?> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    _beginTurn(ChatMessage.user(trimmed));

    try {
      final request = ChatRequest(messages: _conversationPayload());
      final ChatResponse response = await _provider.sendMessage(request);

      final assistantMessage = ChatMessage.assistant(response.content);
      _messages.add(assistantMessage);
      _completeTurn(response.content);
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

    _beginTurn(ChatMessage.user(trimmed));
    return _streamReply();
  }

  /// Streams a reply for the turn already begun by [_beginTurn], optionally on
  /// an override [model] such as the vision model for a screenshot turn.
  Future<ChatMessage?> _streamReply([String? model]) async {
    _isStreaming = true;
    _streamBuffer.clear();
    notifyListeners();

    var cancelled = false;

    try {
      var request = ChatRequest(messages: _conversationPayload());
      if (model != null) {
        request = request.withModel(model);
      }

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
      _completeTurn(content);
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
    personality.removeListener(_onPersonalityChanged);
    _provider.dispose();
    if (_ownsPersonality) {
      personality.dispose();
    }
    super.dispose();
  }

  /// Appends the user's message and marks Kitten as thinking.
  void _beginTurn(ChatMessage message) {
    _messages.add(message);
    _lastError = null;
    _lastErrorType = null;
    _cancelRequested = false;
    _assistantState = AssistantState.thinking;
    personality.onUserMessage(message.content);
    notifyListeners();
  }

  /// The full payload sent to the provider: system prompt plus history.
  ///
  /// Resending every past screenshot on every turn would burn tokens fast, so
  /// only the most recent image-bearing message keeps its image; older ones
  /// become their text alone.
  List<ChatMessage> _conversationPayload() {
    final systemPrompt = personality.buildSystemPrompt();
    final context = _promptContext?.call()?.trim();

    final messages = [
      ChatMessage.system(
        context == null || context.isEmpty
            ? systemPrompt
            : '$systemPrompt\n\n$context',
      ),
      ..._messages,
    ];

    var lastImageIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].hasImage) lastImageIndex = i;
    }
    if (lastImageIndex < 0) return messages;

    return [
      for (var i = 0; i < messages.length; i++)
        i == lastImageIndex ? messages[i] : messages[i].withoutImage(),
    ];
  }

  void _completeTurn(String reply) {
    personality.onAssistantMessage(reply);
    _assistantState = AssistantState.idle;
    notifyListeners();
  }

  void _onPersonalityChanged() => notifyListeners();

  void _failTurn(Object error) {
    personality.onFailure();
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

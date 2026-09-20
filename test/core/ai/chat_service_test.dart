import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_message.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/prompts/kitten_system_prompt.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/personality/models/kitten_mood.dart';

class FakeAiProvider implements AiProvider {
  FakeAiProvider({
    this.responseToReturn = 'Meow! How are you?',
    this.shouldThrow,
    this.streamChunks,
  });

  String responseToReturn;
  Exception? shouldThrow;
  List<String>? streamChunks;
  ChatRequest? lastRequest;
  bool disposed = false;

  @override
  String get providerName => 'FakeProvider';

  @override
  Future<ChatResponse> sendMessage(ChatRequest request) async {
    lastRequest = request;
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    return ChatResponse(
      content: responseToReturn,
      model: 'fake-model',
    );
  }

  @override
  Stream<String> streamMessage(ChatRequest request) async* {
    lastRequest = request;
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    final chunks = streamChunks ?? [responseToReturn];
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  @override
  Future<bool> checkConnection() async {
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    return true;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

/// A provider whose stream is driven manually, so tests can interleave
/// cancellation with incoming deltas.
class ControlledStreamProvider implements AiProvider {
  final StreamController<String> controller = StreamController<String>();

  @override
  String get providerName => 'ControlledProvider';

  @override
  Future<ChatResponse> sendMessage(ChatRequest request) async =>
      const ChatResponse(content: '', model: 'controlled');

  @override
  Stream<String> streamMessage(ChatRequest request) => controller.stream;

  @override
  Future<bool> checkConnection() async => true;

  @override
  void dispose() {
    controller.close();
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('ChatService', () {
    test('initial state is idle with no messages', () {
      final service = ChatService(provider: FakeAiProvider());
      expect(service.assistantState, AssistantState.idle);
      expect(service.messages, isEmpty);
      expect(service.lastError, isNull);
      expect(service.lastErrorType, isNull);
      expect(service.isStreaming, isFalse);
      expect(service.streamingMessage, isNull);
    });

    test('sendMessage prepends system prompt and updates state to idle after response', () async {
      final fakeProvider = FakeAiProvider(
        responseToReturn: 'Hello! *purrs* I am Kitten!',
      );
      final service = ChatService(provider: fakeProvider);

      final result = await service.sendMessage('Hello Kitten');

      expect(result, isNotNull);
      expect(result!.content, 'Hello! *purrs* I am Kitten!');
      expect(result.role, ChatRole.assistant);

      // Verify conversation messages
      expect(service.messages.length, 2);
      expect(service.messages[0].isUser, isTrue);
      expect(service.messages[0].content, 'Hello Kitten');
      expect(service.messages[1].isAssistant, isTrue);
      expect(service.assistantState, AssistantState.idle);

      // Verify system prompt was sent to the provider
      final sentMessages = fakeProvider.lastRequest!.messages;
      expect(sentMessages.first.isSystem, isTrue);
      // The prompt now carries the base persona plus Kitten's live mood.
      expect(sentMessages.first.content, contains(KittenSystemPrompt.prompt));
      expect(sentMessages.first.content, contains('CURRENT MOOD:'));
      expect(sentMessages[1].content, 'Hello Kitten');
    });

    test('the system prompt reflects Kitten\'s mood as it changes', () async {
      final fakeProvider = FakeAiProvider();
      final service = ChatService(provider: fakeProvider);

      await service.sendMessage('tell me a joke!');
      expect(service.personality.mood, KittenMood.playful);
      expect(
        fakeProvider.lastRequest!.messages.first.content,
        contains('playful'),
      );
    });

    // ── Screen understanding ────────────────────────────────────

    test('sendMessageWithImage attaches the image and asks the vision model',
        () async {
      final fakeProvider = FakeAiProvider(streamChunks: ['A ', 'cat']);
      final service = ChatService(provider: fakeProvider);

      final reply = await service.sendMessageWithImage(
        'What is on my screen?',
        'QUJD',
      );

      expect(reply?.content, 'A cat');
      // The everyday text model cannot read images, so the turn is rerouted.
      expect(fakeProvider.lastRequest!.model, AiConfig.visionModel);

      final userMessage = service.messages.first;
      expect(userMessage.hasImage, isTrue);
      expect(userMessage.content, 'What is on my screen?');
    });

    test('replaying history resends only the newest screenshot', () async {
      final fakeProvider = FakeAiProvider();
      final service = ChatService(provider: fakeProvider);

      await service.sendMessageWithImage('first look', 'AAAA');
      await service.sendMessageWithImage('second look', 'BBBB');

      final sent = fakeProvider.lastRequest!.messages;
      final withImages = sent.where((m) => m.hasImage).toList();

      expect(withImages.length, 1);
      expect(withImages.single.imageDataBase64, 'BBBB');
      // The older turn keeps its text, so the conversation still makes sense.
      expect(
        sent.any((m) => m.content == 'first look' && !m.hasImage),
        isTrue,
      );

      // Trimming applies to the request only; the visible chat keeps both.
      expect(service.messages.where((m) => m.hasImage).length, 2);
    });

    test('a screenshot turn reports a vision failure through lastError',
        () async {
      final fakeProvider = FakeAiProvider(
        shouldThrow: AiException.badResponse('vision model rejected the image'),
      );
      final service = ChatService(provider: fakeProvider);

      final reply = await service.sendMessageWithImage('look', 'QUJD');

      expect(reply, isNull);
      expect(service.lastError, isNotNull);
      expect(service.assistantState, AssistantState.idle);
    });

    test('extra context is appended to the system prompt after the mood', () async {
      final fakeProvider = FakeAiProvider();
      final service = ChatService(
        provider: fakeProvider,
        contextProvider: () => 'CURRENT CONTEXT: the user was in Chrome.',
      );

      await service.sendMessage('hi');

      final systemPrompt = fakeProvider.lastRequest!.messages.first.content;
      expect(systemPrompt, contains(KittenSystemPrompt.prompt));
      expect(
        systemPrompt,
        contains('CURRENT CONTEXT: the user was in Chrome.'),
      );
      // Context is added under the persona and mood, never instead of them.
      expect(
        systemPrompt.indexOf('CURRENT MOOD:'),
        lessThan(systemPrompt.indexOf('CURRENT CONTEXT:')),
      );
    });

    test('the context provider is asked every turn and may stay silent', () async {
      String? context;
      final fakeProvider = FakeAiProvider();
      final service = ChatService(
        provider: fakeProvider,
        contextProvider: () => context,
      );

      await service.sendMessage('hi');
      expect(
        fakeProvider.lastRequest!.messages.first.content,
        isNot(contains('CURRENT CONTEXT')),
      );

      context = 'CURRENT CONTEXT: the user was in Chrome.';
      await service.sendMessage('still there?');
      expect(
        fakeProvider.lastRequest!.messages.first.content,
        contains('CURRENT CONTEXT'),
      );
    });

    test('sendMessage sets safe error message and returns state to idle on failure', () async {
      final fakeProvider = FakeAiProvider(
        shouldThrow: AiException.missingApiKey(),
      );
      final service = ChatService(provider: fakeProvider);

      final result = await service.sendMessage('Hello');

      expect(result, isNull);
      expect(service.assistantState, AssistantState.idle);
      expect(service.lastError, contains('Groq API key is not configured'));
      // Only the user message was added to visible messages
      expect(service.messages.length, 1);
    });

    test('clearConversation resets messages and error state', () async {
      final fakeProvider = FakeAiProvider();
      final service = ChatService(provider: fakeProvider);

      await service.sendMessage('Hello');
      expect(service.messages.length, 2);

      service.clearConversation();
      expect(service.messages, isEmpty);
      expect(service.lastError, isNull);
      expect(service.assistantState, AssistantState.idle);
    });

    // ── Streaming ───────────────────────────────────────────────

    test('sendMessageStreaming accumulates deltas into one assistant message', () async {
      final fakeProvider = FakeAiProvider(
        streamChunks: ['Meow', '! I am ', 'Kitten'],
      );
      final service = ChatService(provider: fakeProvider);

      final states = <AssistantState>[];
      service.addListener(() => states.add(service.assistantState));

      final result = await service.sendMessageStreaming('Hi');

      expect(result, isNotNull);
      expect(result!.content, 'Meow! I am Kitten');
      expect(service.messages.length, 2);
      expect(service.messages[1].content, 'Meow! I am Kitten');
      expect(service.assistantState, AssistantState.idle);
      expect(service.isStreaming, isFalse);
      expect(service.streamingMessage, isNull);
      expect(states, contains(AssistantState.thinking));
    });

    test('sendMessageStreaming exposes a live partial message while streaming', () async {
      final fakeProvider = FakeAiProvider(streamChunks: ['Hel', 'lo']);
      final service = ChatService(provider: fakeProvider);

      // Mirrors the UI, which only renders non-empty partials.
      final partials = <String>[];
      service.addListener(() {
        final partial = service.streamingMessage;
        if (partial != null && partial.content.isNotEmpty) {
          partials.add(partial.content);
        }
      });

      await service.sendMessageStreaming('Hi');

      expect(partials, ['Hel', 'Hello']);
    });

    test('sendMessageStreaming records typed error on provider failure', () async {
      final fakeProvider = FakeAiProvider(
        shouldThrow: AiException.invalidApiKey(),
      );
      final service = ChatService(provider: fakeProvider);

      final result = await service.sendMessageStreaming('Hi');

      expect(result, isNull);
      expect(service.lastErrorType, AiErrorType.invalidApiKey);
      expect(service.lastErrorRequiresSettings, isTrue);
      expect(service.isStreaming, isFalse);
      expect(service.streamingMessage, isNull);
      expect(service.assistantState, AssistantState.idle);
      // Only the user message remains.
      expect(service.messages.length, 1);
    });

    test('cancelStreaming keeps already-received text and ends the turn', () async {
      final provider = ControlledStreamProvider();
      final service = ChatService(provider: provider);

      final future = service.sendMessageStreaming('Hi');
      await _settle();

      provider.controller.add('Partial');
      await _settle();
      expect(service.isStreaming, isTrue);
      expect(service.streamingMessage?.content, 'Partial');

      service.cancelStreaming();
      provider.controller.add(' and more');
      await _settle();

      final result = await future;

      expect(result, isNotNull);
      expect(result!.content, 'Partial');
      expect(service.isStreaming, isFalse);
      expect(service.messages.last.content, 'Partial');
      expect(service.assistantState, AssistantState.idle);

      await provider.controller.close();
    });

    test('dispose releases the underlying provider', () {
      final fakeProvider = FakeAiProvider();
      final service = ChatService(provider: fakeProvider);

      service.dispose();

      expect(fakeProvider.disposed, isTrue);
    });
  });

  group('ChatService error classification', () {
    Future<ChatService> failingWith(AiException error) async {
      final service = ChatService(provider: FakeAiProvider(shouldThrow: error));
      await service.sendMessage('Hi');
      return service;
    }

    test('missing or invalid keys require the Settings action', () async {
      final missing = await failingWith(AiException.missingApiKey());
      expect(missing.lastErrorType, AiErrorType.missingApiKey);
      expect(missing.lastErrorRequiresSettings, isTrue);

      final invalid = await failingWith(AiException.invalidApiKey());
      expect(invalid.lastErrorType, AiErrorType.invalidApiKey);
      expect(invalid.lastErrorRequiresSettings, isTrue);
    });

    test('transient errors do not require the Settings action', () async {
      final timeout = await failingWith(AiException.timeout());
      expect(timeout.lastErrorType, AiErrorType.timeout);
      expect(timeout.lastErrorRequiresSettings, isFalse);

      final rateLimited = await failingWith(AiException.rateLimited());
      expect(rateLimited.lastErrorType, AiErrorType.rateLimited);
      expect(rateLimited.lastErrorRequiresSettings, isFalse);
    });

    test('a successful turn clears any previous typed error', () async {
      final provider = FakeAiProvider(shouldThrow: AiException.timeout());
      final service = ChatService(provider: provider);

      await service.sendMessage('Hi');
      expect(service.lastErrorType, AiErrorType.timeout);

      provider.shouldThrow = null;
      await service.sendMessage('Hi again');

      expect(service.lastError, isNull);
      expect(service.lastErrorType, isNull);
      expect(service.lastErrorRequiresSettings, isFalse);
    });
  });
}

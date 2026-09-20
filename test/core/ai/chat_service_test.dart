import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_message.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/prompts/kitten_system_prompt.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/models/assistant_state.dart';

class FakeAiProvider implements AiProvider {
  FakeAiProvider({
    this.responseToReturn = 'Meow! How are you?',
    this.shouldThrow,
  });

  String responseToReturn;
  Exception? shouldThrow;
  ChatRequest? lastRequest;

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
  Future<bool> checkConnection() async {
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    return true;
  }
}

void main() {
  group('ChatService', () {
    test('initial state is idle with no messages', () {
      final service = ChatService(provider: FakeAiProvider());
      expect(service.assistantState, AssistantState.idle);
      expect(service.messages, isEmpty);
      expect(service.lastError, isNull);
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
      expect(sentMessages.first.content, KittenSystemPrompt.prompt);
      expect(sentMessages[1].content, 'Hello Kitten');
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
  });
}

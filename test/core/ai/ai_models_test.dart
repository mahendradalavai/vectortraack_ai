import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_message.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/prompts/kitten_system_prompt.dart';

void main() {
  group('AI Models & Prompts', () {
    test(
      'ChatMessage creates user, assistant, and system messages correctly',
      () {
        final userMsg = ChatMessage.user('Hello');
        expect(userMsg.role, ChatRole.user);
        expect(userMsg.isUser, isTrue);
        expect(userMsg.content, 'Hello');

        final assistantMsg = ChatMessage.assistant('Meow! How can I help?');
        expect(assistantMsg.role, ChatRole.assistant);
        expect(assistantMsg.isAssistant, isTrue);

        final sysMsg = ChatMessage.system('System instruction');
        expect(sysMsg.role, ChatRole.system);
        expect(sysMsg.isSystem, isTrue);

        final json = userMsg.toJson();
        expect(json['role'], 'user');
        expect(json['content'], 'Hello');

        final parsed = ChatMessage.fromJson(json);
        expect(parsed.role, ChatRole.user);
        expect(parsed.content, 'Hello');
      },
    );

    test('a text message serializes its content as a plain string', () {
      final message = ChatMessage.user('Hello');

      expect(message.hasImage, isFalse);
      expect(message.toJson()['content'], 'Hello');
    });

    test('an image message serializes to multimodal content parts', () {
      final message = ChatMessage.userWithImage('What is this?', 'QUJD');

      expect(message.hasImage, isTrue);
      final content = message.toJson()['content'] as List<dynamic>;
      expect(content.length, 2);
      expect(content[0], {'type': 'text', 'text': 'What is this?'});

      final imagePart = content[1] as Map<String, dynamic>;
      expect(imagePart['type'], 'image_url');
      // The image travels inline as a data URL, so no separate upload is needed.
      expect(
        (imagePart['image_url'] as Map<String, dynamic>)['url'],
        'data:image/jpeg;base64,QUJD',
      );
    });

    test('withoutImage keeps the text and drops the picture', () {
      final message = ChatMessage.userWithImage('What is this?', 'QUJD');
      final textOnly = message.withoutImage();

      expect(textOnly.hasImage, isFalse);
      expect(textOnly.content, 'What is this?');
      expect(textOnly.role, ChatRole.user);
      // A message with no image is already text-only, so it returns itself.
      expect(identical(textOnly.withoutImage(), textOnly), isTrue);
    });

    test('withModel overrides the model without touching the messages', () {
      final request = ChatRequest(messages: [ChatMessage.user('Hi')]);
      final vision = request.withModel(AiConfig.visionModel);

      expect(vision.model, AiConfig.visionModel);
      expect(vision.messages, request.messages);
      expect(
        vision.toJson(defaultModel: AiConfig.defaultModel)['model'],
        AiConfig.visionModel,
      );
      // The original request is untouched.
      expect(request.model, isNull);
    });

    test('ChatRequest formats payload with default and custom model', () {
      final requestWithDefault = ChatRequest(
        messages: [ChatMessage.user('Hi')],
      );
      final jsonDefault = requestWithDefault.toJson(
        defaultModel: AiConfig.defaultModel,
      );
      expect(jsonDefault['model'], AiConfig.defaultModel);
      expect(jsonDefault['messages'], isList);
      expect((jsonDefault['messages'] as List).length, 1);

      final requestWithCustom = ChatRequest(
        messages: [ChatMessage.user('Hi')],
        model: 'custom-model',
      );
      final jsonCustom = requestWithCustom.toJson(
        defaultModel: AiConfig.defaultModel,
      );
      expect(jsonCustom['model'], 'custom-model');
    });

    test('ChatResponse parses standard Groq JSON response', () {
      final mockGroqJson = {
        'id': 'chatcmpl-test',
        'object': 'chat.completion',
        'model': 'openai/gpt-oss-20b',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': 'Purr! Hello there!'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 12,
          'completion_tokens': 8,
          'total_tokens': 20,
        },
      };

      final response = ChatResponse.fromGroqJson(mockGroqJson);
      expect(response.content, 'Purr! Hello there!');
      expect(response.model, 'openai/gpt-oss-20b');
      expect(response.finishReason, 'stop');
      expect(response.totalTokens, 20);
    });

    test('ChatResponse throws FormatException on empty choices', () {
      final emptyJson = {'model': 'openai/gpt-oss-20b', 'choices': <dynamic>[]};

      expect(
        () => ChatResponse.fromGroqJson(emptyJson),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'AiException provides safe user-friendly messages without credentials',
      () {
        final missingKey = AiException.missingApiKey();
        expect(missingKey.type, AiErrorType.missingApiKey);
        expect(
          missingKey.userFriendlyMessage,
          contains('Groq API key is not configured'),
        );

        final invalidKey = AiException.invalidApiKey();
        expect(invalidKey.type, AiErrorType.invalidApiKey);
        expect(invalidKey.userFriendlyMessage, contains('rejected'));

        final network = AiException.networkUnavailable('SocketException');
        expect(network.type, AiErrorType.networkUnavailable);
        expect(network.userFriendlyMessage, contains('internet connection'));

        final timeout = AiException.timeout();
        expect(timeout.type, AiErrorType.timeout);
        expect(timeout.userFriendlyMessage, contains('timed out'));

        // Ensure no raw secret is leaked in toString
        expect(invalidKey.toString(), isNot(contains('sk-')));
        expect(invalidKey.toString(), isNot(contains('gsk_')));
      },
    );

    test(
      'KittenSystemPrompt enables hand-offs but forbids silent device actions',
      () {
        final prompt = KittenSystemPrompt.prompt;
        expect(prompt, contains('Kitten'));
        expect(prompt, contains('CRITICAL SCOPE CONSTRAINTS'));

        // The explicit hand-offs the tool registry actually exposes.
        expect(prompt, contains('phone hand-offs'));
        expect(prompt, contains('dialer'));
        expect(prompt, contains('SMS composer'));
        expect(prompt, contains('Alarms and timers'));

        // ...while anything that acts behind the user's back stays forbidden.
        expect(prompt, contains('never claim or promise'));
        expect(prompt, contains('without the user confirming it'));
        expect(prompt, contains('Listen continuously in the background'));
      },
    );

    test('AiConfig has valid default and supported models', () {
      expect(AiConfig.defaultModel, 'openai/gpt-oss-20b');
      expect(AiConfig.availableModels, contains(AiConfig.defaultModel));
      expect(
        AiConfig.availableModels,
        contains('openai/gpt-oss-safeguard-20b'),
      );
    });
  });
}

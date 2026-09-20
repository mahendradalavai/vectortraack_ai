import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_message.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/providers/groq_provider.dart';

import '../services/secure_storage_service_test.dart';

/// A fake HTTP client that returns a chunked server-sent-event body, so the
/// streaming parser can be exercised with realistic, split network frames.
class _SseMockClient extends http.BaseClient {
  _SseMockClient({
    this.chunks = const [],
    this.statusCode = 200,
    this.body = '',
    this.onSend,
  });

  final List<String> chunks;
  final int statusCode;
  final String body;
  final void Function(http.BaseRequest request)? onSend;

  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend?.call(request);

    final controller = StreamController<List<int>>();
    if (body.isNotEmpty) {
      controller.add(utf8.encode(body));
    } else {
      for (final chunk in chunks) {
        controller.add(utf8.encode(chunk));
      }
    }
    // Fire-and-forget: nothing is listening yet, so awaiting `close()` would
    // block forever and trip the provider's request timeout.
    unawaited(controller.close());

    return http.StreamedResponse(
      controller.stream,
      statusCode,
      headers: {
        'content-type': statusCode == 200
            ? 'text/event-stream; charset=utf-8'
            : 'application/json',
      },
    );
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  group('GroqProvider', () {
    const dummyKey = 'test_dummy_key_1234';

    test('sendMessage throws missingApiKey if no key is configured', () async {
      final storage = FakeSecureStorageService(initialKey: null);
      final provider = GroqProvider(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        secureStorage: storage,
      );

      final request = ChatRequest(messages: [ChatMessage.user('Hi')]);
      expect(
        () => provider.sendMessage(request),
        throwsA(predicate((e) =>
            e is AiException && e.type == AiErrorType.missingApiKey)),
      );
    });

    test('sendMessage sends proper Bearer token and parses 200 response', () async {
      late http.Request capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        final responsePayload = {
          'id': 'chatcmpl-test',
          'object': 'chat.completion',
          'model': 'openai/gpt-oss-20b',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': 'Meow! I am your Kitten companion.',
              },
              'finish_reason': 'stop',
            }
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 10,
            'total_tokens': 20,
          }
        };

        return http.Response(
          jsonEncode(responsePayload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final request = ChatRequest(messages: [ChatMessage.user('Hello')]);
      final response = await provider.sendMessage(request);

      expect(response.content, 'Meow! I am your Kitten companion.');
      expect(response.model, 'openai/gpt-oss-20b');
      expect(capturedRequest.headers['Authorization'], 'Bearer $dummyKey');
      expect(capturedRequest.headers['Content-Type'], 'application/json');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['model'], 'openai/gpt-oss-20b');
      expect((body['messages'] as List).length, 1);
    });

    test('sendMessage maps 401 response to invalidApiKey', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Invalid API Key', 'type': 'invalid_request_error'}
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final request = ChatRequest(messages: [ChatMessage.user('Hi')]);
      expect(
        () => provider.sendMessage(request),
        throwsA(predicate((e) =>
            e is AiException && e.type == AiErrorType.invalidApiKey)),
      );
    });

    test('sendMessage maps 429 response to rateLimited', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Rate limit reached', 429);
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final request = ChatRequest(messages: [ChatMessage.user('Hi')]);
      expect(
        () => provider.sendMessage(request),
        throwsA(predicate((e) =>
            e is AiException && e.type == AiErrorType.rateLimited)),
      );
    });

    test('sendMessage maps 500 response to safe apiError', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Internal Server Error'}
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final request = ChatRequest(messages: [ChatMessage.user('Hi')]);
      expect(
        () => provider.sendMessage(request),
        throwsA(predicate((e) =>
            e is AiException &&
            e.type == AiErrorType.apiError &&
            e.userFriendlyMessage.contains('Internal Server Error'))),
      );
    });

    test('sendMessage maps network client exception to networkUnavailable', () async {
      final mockClient = MockClient((_) async {
        throw http.ClientException('Connection reset by peer');
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final request = ChatRequest(messages: [ChatMessage.user('Hi')]);
      expect(
        () => provider.sendMessage(request),
        throwsA(predicate((e) =>
            e is AiException && e.type == AiErrorType.networkUnavailable)),
      );
    });

    test('checkConnection succeeds when models endpoint returns 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/openai/v1/models');
        expect(request.headers['Authorization'], 'Bearer $dummyKey');
        return http.Response('{"data": []}', 200);
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final result = await provider.checkConnection();
      expect(result, isTrue);
    });

    test('checkConnection throws invalidApiKey on 401 response', () async {
      final mockClient = MockClient((_) async {
        return http.Response('{"error": "Unauthorized"}', 401);
      });

      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      expect(
        () => provider.checkConnection(),
        throwsA(predicate((e) =>
            e is AiException && e.type == AiErrorType.invalidApiKey)),
      );
    });

    test('checkConnection throws missingApiKey if no key is set', () async {
      final storage = FakeSecureStorageService(initialKey: null);
      final provider = GroqProvider(
        httpClient: MockClient((_) async => http.Response('', 200)),
        secureStorage: storage,
      );

      expect(
        () => provider.checkConnection(),
        throwsA(predicate((e) =>
            e is AiException && e.type == AiErrorType.missingApiKey)),
      );
    });

    // ── Streaming ───────────────────────────────────────────────

    test('streamMessage emits deltas and stops at the [DONE] sentinel', () async {
      final mockClient = _SseMockClient(chunks: [
        'data: {"choices":[{"delta":{"content":"Meow"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":" there"}}]}\n\n',
        'data: [DONE]\n\n',
      ]);
      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final deltas = await provider
          .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
          .toList();

      expect(deltas, ['Meow', ' there']);
    });

    test('streamMessage reassembles SSE frames split across chunks', () async {
      final mockClient = _SseMockClient(chunks: [
        'data: {"choices":[{"delta":{"con',
        'tent":"Hi"}}]}\n\ndata: {"choices":[{"delta":{"content":"!"}}]}\n\n',
        'data: [DONE]\n\n',
      ]);
      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final deltas = await provider
          .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
          .toList();

      expect(deltas, ['Hi', '!']);
    });

    test('streamMessage ignores comments, keep-alives, and empty frames', () async {
      final mockClient = _SseMockClient(chunks: [
        ': keep-alive\n\n',
        '\n',
        'data: {"choices":[{"delta":{}}]}\n\n',
        'data: {"choices":[]}\n\n',
        'data: {"choices":[{"delta":{"content":"Hey"}}]}\n\n',
        'data: [DONE]\n\n',
      ]);
      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final deltas = await provider
          .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
          .toList();

      expect(deltas, ['Hey']);
    });

    test('streamMessage requests stream mode with Bearer auth', () async {
      http.Request? captured;
      final mockClient = _SseMockClient(
        chunks: ['data: [DONE]\n\n'],
        onSend: (request) => captured = request as http.Request,
      );
      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      await provider
          .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
          .toList();

      expect(captured, isNotNull);
      expect(captured!.headers['Authorization'], 'Bearer $dummyKey');
      expect(captured!.headers['Content-Type'], 'application/json');

      final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(payload['stream'], isTrue);
      expect(payload['model'], 'openai/gpt-oss-20b');
    });

    test('streamMessage maps a non-200 response before emitting any deltas', () async {
      final mockClient = _SseMockClient(
        statusCode: 401,
        body: jsonEncode({
          'error': {'message': 'Invalid API Key'}
        }),
      );
      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      await expectLater(
        provider
            .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
            .toList(),
        throwsA(predicate(
            (e) => e is AiException && e.type == AiErrorType.invalidApiKey)),
      );
    });

    test('streamMessage surfaces mid-stream error frames safely', () async {
      final mockClient = _SseMockClient(chunks: [
        'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n',
        'data: {"error":{"message":"Model overloaded"}}\n\n',
        'data: [DONE]\n\n',
      ]);
      final storage = FakeSecureStorageService(initialKey: dummyKey);
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: storage,
      );

      final collected = <String>[];
      await expectLater(
        provider
            .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
            .forEach(collected.add),
        throwsA(predicate((e) =>
            e is AiException &&
            e.type == AiErrorType.apiError &&
            e.userFriendlyMessage.contains('Model overloaded'))),
      );
      expect(collected, ['Hel']);
    });

    test('streamMessage throws missingApiKey when no key is configured', () async {
      final storage = FakeSecureStorageService(initialKey: null);
      final provider = GroqProvider(
        httpClient: _SseMockClient(),
        secureStorage: storage,
      );

      await expectLater(
        provider
            .streamMessage(ChatRequest(messages: [ChatMessage.user('Hi')]))
            .toList(),
        throwsA(predicate(
            (e) => e is AiException && e.type == AiErrorType.missingApiKey)),
      );
    });

    test('dispose closes the underlying HTTP client', () {
      final mockClient = _SseMockClient();
      final provider = GroqProvider(
        httpClient: mockClient,
        secureStorage: FakeSecureStorageService(initialKey: dummyKey),
      );

      provider.dispose();

      expect(mockClient.closed, isTrue);
    });
  });
}

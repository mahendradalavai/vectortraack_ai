import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/ai_exception.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

/// Concrete implementation of [AiProvider] using Groq's high-speed
/// OpenAI-compatible inference API.
///
/// All HTTP networking and authentication are strictly isolated in this class.
class GroqProvider implements AiProvider {
  GroqProvider({
    http.Client? httpClient,
    SecureStorageService? secureStorage,
  })  : _httpClient = httpClient ?? http.Client(),
        _secureStorage = secureStorage ?? SecureStorageService();

  final http.Client _httpClient;
  final SecureStorageService _secureStorage;

  @override
  String get providerName => 'Groq';

  @override
  Future<ChatResponse> sendMessage(ChatRequest request) async {
    final apiKey = await _resolveApiKey();
    final effectiveModel = await _resolveModel(request);

    final url = Uri.parse(AiConfig.groqApiEndpoint);
    final payload = jsonEncode(request.toJson(defaultModel: effectiveModel));

    try {
      final response = await _httpClient
          .post(url, headers: _jsonHeaders(apiKey), body: payload)
          .timeout(AiConfig.requestTimeout);

      return _handleChatResponse(response);
    } on SocketException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on http.ClientException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on TimeoutException {
      throw AiException.timeout();
    }
  }

  @override
  Stream<String> streamMessage(ChatRequest request) async* {
    final apiKey = await _resolveApiKey();
    final effectiveModel = await _resolveModel(request);

    final url = Uri.parse(AiConfig.groqApiEndpoint);
    final httpRequest = http.Request('POST', url)
      ..headers.addAll(_jsonHeaders(apiKey))
      ..body = jsonEncode(
        request.toJson(defaultModel: effectiveModel, stream: true),
      );

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse =
          await _httpClient.send(httpRequest).timeout(AiConfig.requestTimeout);
    } on SocketException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on http.ClientException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on TimeoutException {
      throw AiException.timeout();
    }

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw _mapErrorResponse(streamedResponse.statusCode, body);
    }

    final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines) {
        final data = _extractDataPayload(line);
        if (data == null) continue;
        if (data == '[DONE]') return;
        if (data.isEmpty) continue;

        final delta = _extractDelta(data);
        if (delta != null && delta.isNotEmpty) {
          yield delta;
        }
      }
    } on SocketException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on http.ClientException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on TimeoutException {
      throw AiException.timeout();
    }
  }

  @override
  Future<bool> checkConnection() async {
    final apiKey = await _resolveApiKey();

    final url = Uri.parse(AiConfig.groqModelsEndpoint);
    final headers = {'Authorization': 'Bearer $apiKey'};

    try {
      final response = await _httpClient
          .get(url, headers: headers)
          .timeout(AiConfig.connectionTestTimeout);

      if (response.statusCode == 200) {
        return true;
      }

      throw _mapErrorResponse(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on SocketException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on http.ClientException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on TimeoutException {
      throw AiException.timeout();
    }
  }

  @override
  void dispose() {
    _httpClient.close();
  }

  /// Reads and validates the stored API key, failing safely when absent.
  Future<String> _resolveApiKey() async {
    final apiKey = await _secureStorage.getGroqApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw AiException.missingApiKey();
    }
    return apiKey.trim();
  }

  /// Chooses the request model, falling back to the stored selection
  /// and finally to [AiConfig.defaultModel].
  Future<String> _resolveModel(ChatRequest request) async {
    final requestModel = request.model;
    if (requestModel != null && requestModel.isNotEmpty) {
      return requestModel;
    }

    final storedModel = await _secureStorage.getSelectedModel();
    if (storedModel != null && storedModel.isNotEmpty) {
      return storedModel;
    }

    return AiConfig.defaultModel;
  }

  Map<String, String> _jsonHeaders(String apiKey) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  ChatResponse _handleChatResponse(http.Response response) {
    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        return ChatResponse.fromGroqJson(decoded);
      } catch (e) {
        throw AiException.badResponse('Failed to parse Groq response JSON');
      }
    }

    throw _mapErrorResponse(
      response.statusCode,
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  }

  /// Maps a non-200 HTTP response into a categorized, user-safe [AiException].
  AiException _mapErrorResponse(int statusCode, String body) {
    if (statusCode == 401) {
      return AiException.invalidApiKey();
    }
    if (statusCode == 429) {
      return AiException.rateLimited();
    }

    String? errorMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final errorObj = decoded['error'];
        if (errorObj is Map<String, dynamic>) {
          errorMessage = errorObj['message'] as String?;
        } else if (errorObj is String) {
          errorMessage = errorObj;
        }
      }
    } catch (_) {
      // Suppress parsing failure for error responses.
    }

    final safeMessage = errorMessage != null && errorMessage.isNotEmpty
        ? 'Groq API error: $errorMessage'
        : 'Groq returned status code $statusCode.';

    return AiException.apiError(safeMessage);
  }

  /// Returns the payload of a server-sent-event `data:` line, or null for
  /// blank lines and comments (e.g. keep-alives).
  String? _extractDataPayload(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('data:')) return null;
    return trimmed.substring('data:'.length).trim();
  }

  /// Extracts the incremental text from a single SSE JSON frame.
  ///
  /// Throws [AiException] when the frame is malformed or reports an error.
  String? _extractDelta(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw AiException.badResponse('Malformed streaming frame from Groq');
      }

      final errorObj = decoded['error'];
      if (errorObj is Map<String, dynamic>) {
        final message = errorObj['message'] as String?;
        throw AiException.apiError(
          message != null && message.isNotEmpty
              ? 'Groq API error: $message'
              : 'Groq reported an error while streaming.',
        );
      }

      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;

      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) return null;

      final delta = firstChoice['delta'];
      if (delta is! Map<String, dynamic>) return null;

      final content = delta['content'];
      return content is String ? content : null;
    } on FormatException {
      throw AiException.badResponse('Malformed streaming frame from Groq');
    }
  }
}

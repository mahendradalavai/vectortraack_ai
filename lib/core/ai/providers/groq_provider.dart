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
    final apiKey = await _secureStorage.getGroqApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw AiException.missingApiKey();
    }

    final storedModel = await _secureStorage.getSelectedModel();
    final effectiveModel = request.model ??
        (storedModel != null && storedModel.isNotEmpty
            ? storedModel
            : AiConfig.defaultModel);

    final url = Uri.parse(AiConfig.groqApiEndpoint);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${apiKey.trim()}',
    };

    final payload = jsonEncode(
      request.toJson(defaultModel: effectiveModel),
    );

    try {
      final response = await _httpClient
          .post(url, headers: headers, body: payload)
          .timeout(AiConfig.requestTimeout);

      return _handleChatResponse(response);
    } on SocketException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on http.ClientException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on TimeoutException {
      throw AiException.timeout();
    } on FormatException catch (e) {
      throw AiException.badResponse(e.message);
    }
  }

  @override
  Future<bool> checkConnection() async {
    final apiKey = await _secureStorage.getGroqApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw AiException.missingApiKey();
    }

    final url = Uri.parse('https://api.groq.com/openai/v1/models');
    final headers = {
      'Authorization': 'Bearer ${apiKey.trim()}',
    };

    try {
      final response = await _httpClient
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 401) {
        throw AiException.invalidApiKey();
      } else if (response.statusCode == 429) {
        throw AiException.rateLimited();
      } else {
        throw AiException.apiError(
          'Groq connection test failed with status code ${response.statusCode}.',
        );
      }
    } on SocketException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on http.ClientException catch (e) {
      throw AiException.networkUnavailable(e.message);
    } on TimeoutException {
      throw AiException.timeout();
    }
  }

  ChatResponse _handleChatResponse(http.Response response) {
    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        return ChatResponse.fromGroqJson(decoded);
      } catch (e) {
        throw AiException.badResponse('Failed to parse Groq response JSON');
      }
    } else if (response.statusCode == 401) {
      throw AiException.invalidApiKey();
    } else if (response.statusCode == 429) {
      throw AiException.rateLimited();
    } else {
      String? errorMessage;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
          final errorObj = decoded['error'];
          if (errorObj is Map<String, dynamic>) {
            errorMessage = errorObj['message'] as String?;
          }
        }
      } catch (_) {
        // Suppress parsing failure for error response
      }

      final safeMessage = errorMessage != null && errorMessage.isNotEmpty
          ? 'Groq API error: $errorMessage'
          : 'Groq returned status code ${response.statusCode}.';

      throw AiException.apiError(safeMessage);
    }
  }
}

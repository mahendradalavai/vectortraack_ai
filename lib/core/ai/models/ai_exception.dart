/// Categorized exception for AI provider operations.
///
/// Designed to provide clean, user-safe error messages while preventing
/// any exposure of credentials, API keys, or raw authorization headers.
enum AiErrorType {
  missingApiKey,
  invalidApiKey,
  networkUnavailable,
  timeout,
  rateLimited,
  apiError,
  badResponse,
  unknown,
}

class AiException implements Exception {
  const AiException({
    required this.type,
    required this.userFriendlyMessage,
    this.technicalDetail,
  });

  factory AiException.missingApiKey() => const AiException(
        type: AiErrorType.missingApiKey,
        userFriendlyMessage:
            'Groq API key is not configured. Please add your key in Settings.',
      );

  factory AiException.invalidApiKey() => const AiException(
        type: AiErrorType.invalidApiKey,
        userFriendlyMessage:
            'Groq rejected the API key. Please check that your key is valid.',
      );

  factory AiException.networkUnavailable([String? detail]) => AiException(
        type: AiErrorType.networkUnavailable,
        userFriendlyMessage:
            'Unable to connect to Groq. Please check your internet connection.',
        technicalDetail: detail,
      );

  factory AiException.timeout([String? detail]) => AiException(
        type: AiErrorType.timeout,
        userFriendlyMessage:
            'Groq request timed out. Please try again in a moment.',
        technicalDetail: detail,
      );

  factory AiException.rateLimited([String? detail]) => AiException(
        type: AiErrorType.rateLimited,
        userFriendlyMessage:
            'Groq rate limit exceeded. Please wait a moment before sending another message.',
        technicalDetail: detail,
      );

  factory AiException.apiError(String safeMessage, [String? detail]) =>
      AiException(
        type: AiErrorType.apiError,
        userFriendlyMessage: safeMessage,
        technicalDetail: detail,
      );

  factory AiException.badResponse([String? detail]) => AiException(
        type: AiErrorType.badResponse,
        userFriendlyMessage:
            'Groq returned an unexpected response format.',
        technicalDetail: detail,
      );

  factory AiException.unknown([String? detail]) => AiException(
        type: AiErrorType.unknown,
        userFriendlyMessage:
            'An unexpected error occurred while communicating with the AI service.',
        technicalDetail: detail,
      );

  final AiErrorType type;
  final String userFriendlyMessage;
  final String? technicalDetail;

  @override
  String toString() => 'AiException($type): $userFriendlyMessage';
}

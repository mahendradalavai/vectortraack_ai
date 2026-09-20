/// Centralized configuration for AI provider integration.
///
/// Contains official model identifiers, timeouts, and request limits.
class AiConfig {
  AiConfig._();

  /// The default Groq model recommended by official Groq documentation.
  ///
  /// `openai/gpt-oss-20b` is an open-weight 20B MoE reasoning model optimized
  /// for Groq LPU inference speed, agentic workflows, and low-latency interaction.
  static const String defaultModel = 'openai/gpt-oss-20b';

  /// Supported models selectable in settings.
  static const List<String> availableModels = [
    'openai/gpt-oss-20b',
    'openai/gpt-oss-safeguard-20b',
  ];

  /// Groq Chat Completions API endpoint (OpenAI-compatible).
  static const String groqApiEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Groq models listing endpoint, used for connectivity & auth testing.
  static const String groqModelsEndpoint =
      'https://api.groq.com/openai/v1/models';

  /// Network timeout for Groq API requests.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Shorter timeout for the lightweight connection test.
  static const Duration connectionTestTimeout = Duration(seconds: 15);

  /// Default sampling temperature for creative yet coherent responses.
  static const double defaultTemperature = 0.7;

  /// Default maximum tokens per completion response.
  static const int defaultMaxTokens = 1024;
}

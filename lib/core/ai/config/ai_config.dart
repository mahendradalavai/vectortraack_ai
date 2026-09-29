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

  /// The model used for screen understanding.
  ///
  /// Groq's multimodal model: it accepts image parts alongside text. Chosen
  /// separately from [defaultModel] so the user's everyday text model never
  /// has to be vision-capable.
  static const String visionModel = 'qwen/qwen3.8-27b';

  /// Maximum size, in bytes, of a screenshot sent to the vision model.
  ///
  /// Groq rejects requests over 20 MB, and a raw phone screenshot compresses
  /// far below that, so this is a sanity guard rather than a real limit.
  static const int maxImageBytes = 4 * 1024 * 1024;

  /// How many request/execute rounds a single tool turn may take.
  ///
  /// Each round is one model request plus the tools it asked for. Bounded so a
  /// model stuck in a loop cannot spin forever on the user's battery and bill.
  static const int maxToolRounds = 3;

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

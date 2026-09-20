/// Centralized configuration for Kitten's voice input and output.
///
/// Keeping timings, locale, and voice character in one place makes the
/// hands-free loop easy to tune without touching orchestration logic.
class VoiceConfig {
  VoiceConfig._();

  /// Locale used for speech recognition (`speech_to_text` format).
  static const String speechLocaleId = 'en_US';

  /// Locale used for speech synthesis (`flutter_tts` format).
  static const String ttsLanguage = 'en-US';

  /// Maximum length of a single listening window.
  static const Duration listenFor = Duration(seconds: 30);

  /// Silence duration that closes a listening window.
  static const Duration pauseFor = Duration(seconds: 3);

  /// Wait after Kitten finishes speaking before reopening the microphone, so
  /// the tail of the audio output is not captured as input.
  static const Duration listenRestartDelay = Duration(milliseconds: 500);

  /// Speech rate as a `flutter_tts` fraction (0.0 - 1.0).
  static const double speechRate = 0.5;

  /// Slightly raised pitch to keep Kitten's playful character.
  static const double pitch = 1.1;

  /// Playback volume (0.0 - 1.0).
  static const double volume = 1.0;

  /// Whether Kitten re-opens the microphone after each reply by default.
  static const bool handsFreeByDefault = true;

  /// Whether Kitten speaks its replies out loud by default.
  static const bool speakRepliesByDefault = true;
}

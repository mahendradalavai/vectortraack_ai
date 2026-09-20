/// Centralized configuration for Kitten's voice input and output.
///
/// Keeping timings, locale, phrasing, and voice character in one place makes
/// the hands-free and wake-word loops easy to tune without touching logic.
class VoiceConfig {
  VoiceConfig._();

  /// Phrases that activate Kitten while it is waiting for its name.
  ///
  /// Kept short and lower-case; matching normalises casing and punctuation.
  static const List<String> wakePhrases = <String>[
    'hey kitten',
    'hi kitten',
  ];

  /// Locale used for speech recognition (`speech_to_text` format).
  static const String speechLocaleId = 'en_US';

  /// Locale used for speech synthesis (`flutter_tts` format).
  static const String ttsLanguage = 'en-US';

  /// Maximum length of a single conversational listening window.
  static const Duration listenFor = Duration(seconds: 30);

  /// Silence duration that closes a conversational listening window.
  static const Duration pauseFor = Duration(seconds: 3);

  /// Shorter window and pause while merely waiting for the wake phrase, so
  /// the recogniser is not held open longer than needed.
  static const Duration wakeListenFor = Duration(seconds: 15);
  static const Duration wakePauseFor = Duration(seconds: 2);

  /// Wait after Kitten finishes speaking before reopening the microphone, so
  /// the tail of the audio output is not captured as input.
  static const Duration listenRestartDelay = Duration(milliseconds: 500);

  /// Speech rate as a `flutter_tts` fraction (0.0 - 1.0).
  static const double speechRate = 0.5;

  /// Slightly raised pitch to keep Kitten's playful character.
  static const double pitch = 1.1;

  /// Playback volume (0.0 - 1.0).
  static const double volume = 1.0;

  /// Whether Kitten reopens the microphone after each reply by default.
  static const bool handsFreeByDefault = true;

  /// Whether Kitten speaks its replies out loud by default.
  static const bool speakRepliesByDefault = true;

  /// Whether Kitten watches for its wake phrase by default.
  ///
  /// Deliberately off: an always-open microphone is a privacy and battery
  /// decision the user should make explicitly.
  static const bool wakeWordByDefault = false;
}

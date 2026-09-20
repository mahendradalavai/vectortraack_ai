/// Tuning for on-demand screen understanding.
class ScreenConfig {
  ScreenConfig._();

  /// What Kitten is asked when the user taps the button without typing a
  /// question of their own.
  static const String defaultQuestion = 'What is on my screen?';

  /// How long a single capture may take before it is given up on.
  ///
  /// Consent plus one frame of a mirrored display normally finishes in a
  /// second or two; this only exists so a stalled capture cannot hang the UI.
  static const Duration captureTimeout = Duration(seconds: 45);

  /// Storage key marking that the one-time privacy explanation was shown.
  static const String explainedStorageKey = 'screen_read_explained';
}

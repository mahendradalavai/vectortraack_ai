/// Contract for text-to-speech output.
///
/// Keeps the conversation loop testable without invoking real audio.
abstract class TtsService {
  /// Whether spoken output is usable on this device.
  bool get isAvailable;

  /// Configures the voice. Returns false when the engine is unavailable
  /// (unsupported platform, missing plugin, or initialization failure).
  Future<bool> initialize({required void Function(String message) onError});

  /// Speaks [text], completing once playback finishes.
  Future<void> speak(String text);

  /// Stops any in-flight playback immediately.
  Future<void> stop();

  /// Releases platform resources held by the engine.
  void dispose();
}

/// Callback for recognized speech: the words heard and whether the result is
/// final (the listening window closed) or still partial.
typedef SpeechResultCallback = void Function(
  String recognizedWords,
  bool isFinal,
);

/// Why a listening window ended without usable speech.
enum SpeechIssue {
  /// The window closed with no speech detected. Expected in a hands-free loop
  /// and worth retrying quietly rather than reporting to the user.
  noSpeech,

  /// A problem the user must resolve, such as a denied microphone permission.
  /// The session should end instead of retrying blindly.
  permissionDenied,

  /// Any other recoverable failure.
  transient,
}

/// Reports a listening-window problem that ended it without a result.
typedef SpeechIssueCallback = void Function(SpeechIssue issue, String message);

/// How the recogniser should be tuned for a listening window.
///
/// Vendor-neutral on purpose: the platform plugin's own enum stays inside the
/// device implementation.
enum SpeechListenMode {
  /// Short phrases and commands — used while watching for the wake phrase.
  command,

  /// Longer sentences — used for conversational questions.
  dictation,
}

/// Contract for speech-to-text input.
///
/// Exists so the conversation loop can be driven and unit-tested without a
/// real microphone or platform plugin.
abstract class SpeechService {
  /// Whether the device can currently perform speech recognition.
  bool get isAvailable;

  /// Whether a listening window is currently open.
  bool get isListening;

  /// Prepares the recogniser, requesting microphone permission if needed.
  ///
  /// Returns false when speech input is unusable — an unsupported platform,
  /// denied permission, or a missing plugin — so callers can degrade
  /// gracefully instead of throwing.
  Future<bool> initialize({required SpeechIssueCallback onIssue});

  /// Opens one listening window. [onResult] is called with partial and final
  /// transcripts until the window closes on silence or timeout.
  Future<void> listen({
    required SpeechResultCallback onResult,
    SpeechListenMode mode = SpeechListenMode.dictation,
  });

  /// Closes the listening window, allowing a final result to be delivered.
  Future<void> stop();

  /// Closes the listening window and discards any buffered audio.
  Future<void> cancel();

  /// Releases platform resources held by the recogniser.
  void dispose();
}

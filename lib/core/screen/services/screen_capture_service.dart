/// An exception raised while trying to capture the screen.
///
/// Carries a machine-readable [code] so callers can react precisely (for
/// example, to tell a user-cancelled capture apart from a real failure)
/// without matching on message text.
class ScreenCaptureException implements Exception {
  const ScreenCaptureException(this.code, [this.details]);

  /// The user dismissed the system consent dialog.
  static const String cancelledCode = 'cancelled';

  /// A capture is already running, or the system refused to start one.
  static const String busyCode = 'busy';

  /// The capture genuinely failed, such as a refused projection.
  static const String failedCode = 'capture_failed';

  /// The capture did not produce an image in time.
  static const String timeoutCode = 'timeout';

  /// One of the codes above.
  final String code;

  /// Optional technical detail, never shown to the user.
  final String? details;

  @override
  String toString() =>
      'ScreenCaptureException($code${details == null ? '' : ', $details'})';
}

/// Contract for capturing the screen as a single image.
///
/// Kept abstract so the understanding flow can be tested without Android, and
/// so a different platform could be supported later.
abstract class ScreenCaptureService {
  /// Whether this platform can capture the screen at all.
  bool get isSupported;

  /// Captures the screen once and returns JPEG image bytes, encoded as
  /// base64, or null when the user declined the system consent dialog.
  ///
  /// Throws [ScreenCaptureException] when a capture was refused or failed.
  /// The implementation must impose its own timeout so a stalled capture
  /// cannot hang the caller.
  Future<String?> captureScreen();

  /// Releases any platform resources.
  void dispose();
}

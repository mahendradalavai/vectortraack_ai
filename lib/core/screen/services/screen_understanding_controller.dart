import 'package:flutter/foundation.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/screen/config/screen_config.dart';
import 'package:kitten/core/screen/services/method_channel_screen_capture_service.dart';
import 'package:kitten/core/screen/services/screen_capture_service.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

/// How an on-demand screen read ended.
enum ScreenReadStatus {
  /// Kitten answered the question about the screen.
  ok,

  /// The user dismissed the system consent dialog, so nothing happened.
  cancelled,

  /// Something went wrong; [ScreenReadOutcome.error] says what.
  failed,
}

/// The result of one [ScreenUnderstandingController.readScreen] call.
class ScreenReadOutcome {
  const ScreenReadOutcome(this.status, [this.error]);

  final ScreenReadStatus status;

  /// A user-facing explanation, when [status] is [ScreenReadStatus.failed].
  final String? error;

  bool get isOk => status == ScreenReadStatus.ok;
}

/// Drives Kitten's on-demand screen understanding.
///
/// Every read is a deliberate act by the user: they press the button, Android
/// shows the projection consent dialog, one screenshot is taken, and the
/// result is sent to a vision model as part of the conversation. Nothing runs
/// in the background and no image is taken without that explicit consent.
class ScreenUnderstandingController extends ChangeNotifier {
  ScreenUnderstandingController({
    required this.chatService,
    ScreenCaptureService? captureService,
    SecureStorageService? storage,
  })  : _injectedCapture = captureService,
        _injectedStorage = storage;

  /// The conversation the screen read belongs to and streams its reply into.
  final ChatService chatService;

  final ScreenCaptureService? _injectedCapture;
  final SecureStorageService? _injectedStorage;

  ScreenCaptureService? _capture;
  SecureStorageService? _storageInstance;

  bool _busy = false;
  bool _introduced = false;
  bool _disposed = false;

  ScreenCaptureService get _captureInstance =>
      _capture ??= _injectedCapture ?? MethodChannelScreenCaptureService();

  SecureStorageService get _storageService =>
      _storageInstance ??= _injectedStorage ?? SecureStorageService();

  /// Whether this platform can capture the screen at all.
  bool get isSupported => _captureInstance.isSupported;

  /// Whether a capture or its reply is in flight.
  bool get isCapturing => _busy;

  /// Whether the one-time privacy explanation still needs to be shown.
  bool get needsIntroduction => !_introduced;

  /// Re-applies the saved flag. Call once at startup.
  Future<void> restoreIntroduction() async {
    final shown = await _storageService.getScreenReadExplained();
    if (_disposed || shown != true) return;

    _introduced = true;
    _safeNotify();
  }

  /// Records that the privacy explanation was shown, so it appears once.
  Future<void> markIntroduced() async {
    _introduced = true;
    await _storageService.saveScreenReadExplained(true);
    _safeNotify();
  }

  /// Reads the screen once and streams Kitten's answer into [chatService].
  ///
  /// [question] overrides the default prompt, typically with whatever the user
  /// had typed. Returns how it ended; a cancelled consent is not an error.
  Future<ScreenReadOutcome> readScreen({String? question}) async {
    if (_disposed || _busy) {
      return const ScreenReadOutcome(ScreenReadStatus.cancelled);
    }

    if (!_captureInstance.isSupported) {
      return const ScreenReadOutcome(
        ScreenReadStatus.failed,
        'Screen reading is only available on Android.',
      );
    }

    _busy = true;
    _safeNotify();
    try {
      final String image;
      try {
        final captured = await _captureInstance.captureScreen();
        if (captured == null) {
          return const ScreenReadOutcome(ScreenReadStatus.cancelled);
        }
        if (captured.isEmpty) {
          return const ScreenReadOutcome(
            ScreenReadStatus.failed,
            'Kitten saw an empty screenshot. Please try again.',
          );
        }
        // Base64 is about four thirds of the payload, and Groq rejects an
        // oversized request outright. The native side keeps screenshots small,
        // so this only catches a genuinely broken capture.
        if (captured.length * 3 ~/ 4 > AiConfig.maxImageBytes) {
          return const ScreenReadOutcome(
            ScreenReadStatus.failed,
            'That screenshot is too large to send.',
          );
        }
        image = captured;
      } on ScreenCaptureException catch (error) {
        return ScreenReadOutcome(
          ScreenReadStatus.failed,
          _friendlyCaptureError(error),
        );
      }

      final text = (question != null && question.trim().isNotEmpty)
          ? question.trim()
          : ScreenConfig.defaultQuestion;

      await chatService.sendMessageWithImage(text, image);

      final chatError = chatService.lastError;
      if (chatError != null) {
        return ScreenReadOutcome(ScreenReadStatus.failed, chatError);
      }
      return const ScreenReadOutcome(ScreenReadStatus.ok);
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  String _friendlyCaptureError(ScreenCaptureException error) {
    switch (error.code) {
      case ScreenCaptureException.busyCode:
        return 'A screen capture is already running.';
      case ScreenCaptureException.timeoutCode:
        return 'Kitten could not see the screen in time. Please try again.';
      default:
        return 'Kitten could not capture the screen.';
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Only release a service we created ourselves.
    _capture?.dispose();
    super.dispose();
  }
}

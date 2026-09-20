import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:kitten/core/voice/config/voice_config.dart';
import 'package:kitten/core/voice/services/speech_service.dart';

/// [SpeechService] backed by the `speech_to_text` platform plugin.
///
/// All plugin contact is confined here. Initialization never throws: an
/// unsupported platform or denied permission surfaces as `isAvailable == false`
/// so the app keeps working in text-only mode.
class DeviceSpeechService implements SpeechService {
  DeviceSpeechService({SpeechToText? speechToText})
      : _speech = speechToText ?? SpeechToText();

  final SpeechToText _speech;

  bool _initialized = false;
  bool _available = false;
  String? _localeId;
  SpeechIssueCallback? _onIssue;

  @override
  bool get isAvailable => _available;

  @override
  bool get isListening => _available && _speech.isListening;

  @override
  Future<bool> initialize({required SpeechIssueCallback onIssue}) async {
    _onIssue = onIssue;
    if (_initialized) return _available;

    try {
      _available = await _speech.initialize(onError: _handleError);
      if (_available) {
        _localeId = await _resolveLocaleId();
      }
    } catch (_) {
      // Plugin missing (e.g. an unsupported platform) or engine failure.
      _available = false;
    }

    _initialized = true;
    return _available;
  }

  @override
  Future<void> listen({required SpeechResultCallback onResult}) async {
    if (!_available) return;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        listenFor: VoiceConfig.listenFor,
        pauseFor: VoiceConfig.pauseFor,
        localeId: _localeId,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  @override
  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  @override
  void dispose() {
    if (_speech.isListening) {
      _speech.cancel();
    }
  }

  /// Prefers the configured locale, falling back to the device default.
  Future<String?> _resolveLocaleId() async {
    try {
      final locales = await _speech.locales();
      if (locales
          .any((locale) => locale.localeId == VoiceConfig.speechLocaleId)) {
        return VoiceConfig.speechLocaleId;
      }
      final system = await _speech.systemLocale();
      return system?.localeId;
    } catch (_) {
      // Locale discovery is best-effort; the engine default is fine.
      return null;
    }
  }

  void _handleError(SpeechRecognitionError error) {
    final (issue, message) = _classify(error);
    _onIssue?.call(issue, message);
  }

  (SpeechIssue, String) _classify(SpeechRecognitionError error) {
    switch (error.errorMsg) {
      // Silence is normal in a continuous loop, not something to report.
      case 'error_no_match':
      case 'error_speech_timeout':
        return (
          SpeechIssue.noSpeech,
          'Kitten did not catch that. Please try again.',
        );
      case 'error_permission':
        return (
          SpeechIssue.permissionDenied,
          'Microphone access was denied. Enable it to talk to Kitten.',
        );
      case 'error_audio_error':
        return (
          SpeechIssue.permissionDenied,
          'The microphone is unavailable right now.',
        );
      case 'error_busy':
        return (
          SpeechIssue.transient,
          'The microphone is busy. Please try again in a moment.',
        );
      default:
        return (
          error.permanent ? SpeechIssue.permissionDenied : SpeechIssue.transient,
          'Voice input stopped unexpectedly. Please try again.',
        );
    }
  }
}

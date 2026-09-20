import 'package:flutter_tts/flutter_tts.dart';

import 'package:kitten/core/voice/config/voice_config.dart';
import 'package:kitten/core/voice/services/tts_service.dart';

/// [TtsService] backed by the `flutter_tts` platform plugin.
///
/// Initialization never throws so a device without a speech engine simply
/// runs in silent mode.
class FlutterTtsService implements TtsService {
  FlutterTtsService({FlutterTts? flutterTts})
      : _tts = flutterTts ?? FlutterTts();

  final FlutterTts _tts;

  bool _initialized = false;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Future<bool> initialize({
    required void Function(String message) onError,
  }) async {
    if (_initialized) return _available;

    try {
      await _tts.setLanguage(VoiceConfig.ttsLanguage);
      await _tts.setSpeechRate(VoiceConfig.speechRate);
      await _tts.setPitch(VoiceConfig.pitch);
      await _tts.setVolume(VoiceConfig.volume);

      // Make speak() complete only once playback has actually finished, so the
      // hands-free loop can reopen the microphone at the right moment.
      await _tts.awaitSpeakCompletion(true);

      _tts.setErrorHandler((dynamic message) {
        onError('Voice output failed: $message');
      });

      _available = true;
    } catch (_) {
      // Plugin missing (e.g. an unsupported platform) or engine failure.
      _available = false;
    }

    _initialized = true;
    return _available;
  }

  @override
  Future<void> speak(String text) async {
    if (!_available || text.trim().isEmpty) return;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    if (!_available) return;
    await _tts.stop();
  }

  @override
  void dispose() {
    if (_available) {
      _tts.stop();
    }
  }
}

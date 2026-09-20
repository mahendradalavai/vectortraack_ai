import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/voice/config/voice_config.dart';
import 'package:kitten/core/voice/services/device_speech_service.dart';
import 'package:kitten/core/voice/services/flutter_tts_service.dart';
import 'package:kitten/core/voice/services/speech_service.dart';
import 'package:kitten/core/voice/services/tts_service.dart';
import 'package:kitten/core/voice/util/voice_text_cleaner.dart';

/// Drives Kitten's hands-free voice conversation:
/// idle -> listening -> thinking -> speaking -> listening again.
///
/// Owns the speech and synthesis services and composes the existing
/// [ChatService], which stays responsible for the actual AI conversation.
/// Voice states take precedence over the text-chat states when reporting
/// [assistantState], so the status chip reflects what Kitten is doing now.
class VoiceController extends ChangeNotifier {
  VoiceController({
    ChatService? chatService,
    SpeechService? speechService,
    TtsService? ttsService,
    bool? handsFree,
    bool? speakReplies,
    Duration? listenRestartDelay,
  })  : chatService = chatService ?? ChatService(),
        _ownsChatService = chatService == null,
        _injectedSpeech = speechService,
        _injectedTts = ttsService,
        _handsFree = handsFree ?? VoiceConfig.handsFreeByDefault,
        _speakReplies = speakReplies ?? VoiceConfig.speakRepliesByDefault,
        _listenRestartDelay =
            listenRestartDelay ?? VoiceConfig.listenRestartDelay {
    this.chatService.addListener(_onChatChanged);
  }

  /// The conversation Kitten is having, shared with the text UI.
  final ChatService chatService;

  final bool _ownsChatService;
  final SpeechService? _injectedSpeech;
  final TtsService? _injectedTts;

  // Created lazily so constructing the controller never touches platform
  // plugins (important for tests and unsupported platforms).
  SpeechService? _speech;
  TtsService? _tts;

  final Duration _listenRestartDelay;
  bool _handsFree;
  bool _speakReplies;

  bool _initialized = false;
  bool _active = false;
  bool _disposed = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _speechAvailable = false;
  bool _ttsAvailable = false;
  bool _handlingUtterance = false;
  bool _relistenScheduled = false;
  String? _voiceError;

  /// Whether the hands-free session is currently running.
  bool get isActive => _active;

  /// Whether the microphone is open right now.
  bool get isListening => _isListening;

  /// Whether Kitten is speaking right now.
  bool get isSpeaking => _isSpeaking;

  /// Whether speech recognition could be initialized on this device.
  bool get speechAvailable => _speechAvailable;

  /// Whether spoken output could be initialized on this device.
  bool get ttsAvailable => _ttsAvailable;

  /// Whether Kitten repeats the microphone after each reply.
  bool get handsFree => _handsFree;

  /// Whether Kitten reads its replies aloud.
  bool get speakReplies => _speakReplies;

  /// The most recent user-facing voice problem, or null.
  String? get voiceError => _voiceError;

  /// What Kitten is doing now, for the status chip.
  AssistantState get assistantState {
    if (_isSpeaking) return AssistantState.speaking;
    if (_isListening) return AssistantState.listening;
    return chatService.assistantState;
  }

  SpeechService get _speechService =>
      _speech ??= _injectedSpeech ?? DeviceSpeechService();

  TtsService get _ttsService => _tts ??= _injectedTts ?? FlutterTtsService();

  void setHandsFree(bool value) {
    _handsFree = value;
    _safeNotify();
  }

  void setSpeakReplies(bool value) {
    _speakReplies = value;
    _safeNotify();
  }

  /// Clears the current voice error so the UI stops reporting it.
  void clearVoiceError() {
    _voiceError = null;
    _safeNotify();
  }

  /// Starts the hands-free session, opening the microphone.
  Future<void> start() async {
    if (_active || _disposed) return;

    _voiceError = null;
    await _initializeServices();
    if (_disposed) return;

    if (!_speechAvailable) {
      _voiceError = 'Voice input is not available on this device.';
      _safeNotify();
      return;
    }

    _active = true;
    _safeNotify();
    await _listenOnce();
  }

  /// Ends the session and releases the microphone and speaker immediately.
  Future<void> stop() async {
    _active = false;
    _isListening = false;
    _isSpeaking = false;
    _relistenScheduled = false;
    _voiceError = null;

    // Touch only services that were actually created.
    if (_speech != null) await _speech!.cancel();
    if (_tts != null) await _tts!.stop();

    _safeNotify();
  }

  /// Starts the session if idle, otherwise ends it.
  Future<void> toggle() => _active ? stop() : start();

  Future<void> _initializeServices() async {
    if (_initialized) return;

    _speechAvailable = await _speechService.initialize(onIssue: _onSpeechIssue);
    _ttsAvailable = await _ttsService.initialize(onError: _onTtsError);
    _initialized = true;
  }

  Future<void> _listenOnce() async {
    if (!_active || _disposed || _isListening || _handlingUtterance) return;

    _isListening = true;
    _voiceError = null;
    _safeNotify();

    try {
      await _speechService.listen(onResult: _onSpeechResult);
    } catch (_) {
      _isListening = false;
      _voiceError = 'Voice input stopped unexpectedly. Please try again.';
      _safeNotify();
      _scheduleReListen();
    }
  }

  void _onSpeechResult(String recognizedWords, bool isFinal) {
    if (!_active || !isFinal) return;

    final text = recognizedWords.trim();
    _isListening = false;
    _safeNotify();

    if (text.isEmpty) {
      // Nothing was said: keep the loop alive without bothering the user.
      _scheduleReListen();
      return;
    }

    unawaited(_handleUtterance(text));
  }

  /// Sends the transcript to Kitten, speaks the reply, then listens again.
  Future<void> _handleUtterance(String text) async {
    if (_handlingUtterance) return;
    _handlingUtterance = true;
    _isListening = false;
    _safeNotify();

    try {
      final reply = await chatService.sendMessageStreaming(text);
      if (!_active || _disposed) return;

      final spoken = reply?.content.trim();
      final shouldSpeak = _speakReplies &&
          _ttsAvailable &&
          spoken != null &&
          spoken.isNotEmpty;

      if (shouldSpeak) {
        _isSpeaking = true;
        _safeNotify();
        try {
          await _ttsService.speak(cleanTextForSpeech(spoken));
        } catch (_) {
          // A failed utterance must never end the conversation.
        }
        _isSpeaking = false;
        _safeNotify();
      }
    } finally {
      _handlingUtterance = false;
    }

    if (!_active || _disposed) return;

    if (_handsFree) {
      _scheduleReListen();
    } else {
      _active = false;
      _safeNotify();
    }
  }

  /// Opens the microphone again after a short pause, once nothing else is
  /// using it.
  void _scheduleReListen() {
    if (_relistenScheduled || !_active || _disposed) return;
    _relistenScheduled = true;

    unawaited(
      Future<void>.delayed(_listenRestartDelay, () async {
        _relistenScheduled = false;
        if (!_active || _disposed) return;
        if (_isListening || _isSpeaking || _handlingUtterance) return;
        await _listenOnce();
      }),
    );
  }

  void _onSpeechIssue(SpeechIssue issue, String message) {
    _isListening = false;

    if (issue == SpeechIssue.permissionDenied) {
      _voiceError = message;
      _active = false;
      _safeNotify();
      return;
    }

    if (issue == SpeechIssue.transient) {
      _voiceError = message;
    }

    _safeNotify();
    _scheduleReListen();
  }

  void _onTtsError(String message) {
    _voiceError = message;
    _safeNotify();
  }

  void _onChatChanged() => _safeNotify();

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;

    chatService.removeListener(_onChatChanged);
    _speech?.dispose();
    _tts?.dispose();
    if (_ownsChatService) {
      chatService.dispose();
    }

    super.dispose();
  }
}

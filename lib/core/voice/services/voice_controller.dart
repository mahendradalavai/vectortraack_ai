import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/services/secure_storage_service.dart';
import 'package:kitten/core/voice/config/voice_config.dart';
import 'package:kitten/core/voice/services/device_speech_service.dart';
import 'package:kitten/core/voice/services/flutter_tts_service.dart';
import 'package:kitten/core/voice/services/speech_service.dart';
import 'package:kitten/core/voice/services/tts_service.dart';
import 'package:kitten/core/voice/util/voice_text_cleaner.dart';
import 'package:kitten/core/voice/util/wake_word_matcher.dart';

/// What Kitten is currently doing with the microphone.
enum VoiceMode {
  /// The microphone is closed.
  idle,

  /// Waiting to hear the wake phrase ("Hey Kitten").
  watchingForWakeWord,

  /// In an active conversation: listening -> thinking -> speaking -> listening.
  conversation,
}

/// Drives Kitten's voice behaviour.
///
/// Owns the speech and synthesis services and composes the existing
/// [ChatService], which stays responsible for the actual AI conversation.
/// There is a single recogniser on the device, so both the wake-word watch and
/// the conversation loop are coordinated here rather than competing for it.
class VoiceController extends ChangeNotifier {
  VoiceController({
    ChatService? chatService,
    SpeechService? speechService,
    TtsService? ttsService,
    bool? handsFree,
    bool? speakReplies,
    bool? wakeWordEnabled,
    SecureStorageService? storage,
    Duration? listenRestartDelay,
  })  : chatService = chatService ?? ChatService(),
        _ownsChatService = chatService == null,
        _injectedSpeech = speechService,
        _injectedTts = ttsService,
        _injectedStorage = storage,
        _handsFree = handsFree ?? VoiceConfig.handsFreeByDefault,
        _speakReplies = speakReplies ?? VoiceConfig.speakRepliesByDefault,
        _wakeEnabled = wakeWordEnabled ?? VoiceConfig.wakeWordByDefault,
        _listenRestartDelay =
            listenRestartDelay ?? VoiceConfig.listenRestartDelay {
    this.chatService.addListener(_onChatChanged);
  }

  /// The conversation Kitten is having, shared with the text UI.
  final ChatService chatService;

  final bool _ownsChatService;
  final SpeechService? _injectedSpeech;
  final TtsService? _injectedTts;
  final SecureStorageService? _injectedStorage;

  SecureStorageService? _storageInstance;

  // Created lazily so constructing the controller never touches platform
  // plugins (important for tests and unsupported platforms).
  SpeechService? _speech;
  TtsService? _tts;

  final Duration _listenRestartDelay;

  bool _handsFree;
  bool _speakReplies;
  bool _wakeEnabled;

  VoiceMode _mode = VoiceMode.idle;
  bool _initialized = false;
  bool _disposed = false;
  bool _suspended = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _speechAvailable = false;
  bool _ttsAvailable = false;
  bool _handlingUtterance = false;
  bool _relistenScheduled = false;
  String? _voiceError;

  /// What Kitten is doing with the microphone right now.
  VoiceMode get mode => _mode;

  /// Whether a conversation session is running.
  bool get isActive => _mode == VoiceMode.conversation;

  /// Whether Kitten is waiting to hear its wake phrase.
  bool get isWatchingForWakeWord => _mode == VoiceMode.watchingForWakeWord;

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

  /// Whether Kitten watches for the wake phrase.
  bool get wakeWordEnabled => _wakeEnabled;

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

  SecureStorageService get _storageService =>
      _storageInstance ??= _injectedStorage ?? SecureStorageService();

  void setHandsFree(bool value) {
    _handsFree = value;
    _safeNotify();
  }

  void setSpeakReplies(bool value) {
    _speakReplies = value;
    _safeNotify();
  }

  /// Applies the preferences saved by the Settings screen.
  ///
  /// Call once at startup; the microphone is only opened when the user had
  /// wake-word listening switched on.
  Future<void> restorePreferences() async {
    final wakeWord = await _storageService.getWakeWordEnabled();
    final speakReplies = await _storageService.getSpeakReplies();
    if (_disposed) return;

    if (speakReplies != null) {
      _speakReplies = speakReplies;
      _safeNotify();
    }

    if (wakeWord == true) {
      await enableWakeWord();
    }
  }

  /// Starts an explicit conversation (the Talk button).
  Future<void> start() async {
    if (_disposed || _mode == VoiceMode.conversation) return;

    _voiceError = null;
    await _initializeServices();
    if (_disposed) return;

    if (!_speechAvailable) {
      _voiceError = 'Voice input is not available on this device.';
      _safeNotify();
      return;
    }

    _mode = VoiceMode.conversation;
    _safeNotify();
    await _listenOnce();
  }

  /// Ends the conversation, returning to wake-word watching when enabled.
  Future<void> stop() async {
    await _teardown();

    if (_wakeEnabled && !_suspended && !_disposed) {
      await enableWakeWord();
    }
  }

  /// Starts a conversation if idle, otherwise ends it.
  Future<void> toggle() =>
      _mode == VoiceMode.conversation ? stop() : start();

  /// Starts watching for the wake phrase. Foreground only by design.
  Future<void> enableWakeWord() async {
    _wakeEnabled = true;
    _voiceError = null;

    if (_disposed || _suspended || _mode == VoiceMode.conversation) {
      _safeNotify();
      return;
    }

    await _initializeServices();
    if (_disposed) return;

    if (!_speechAvailable) {
      // The switch must not claim to listen when it cannot.
      _wakeEnabled = false;
      _voiceError = 'Voice input is not available on this device.';
      _safeNotify();
      return;
    }

    _mode = VoiceMode.watchingForWakeWord;
    _safeNotify();
    await _listenForWakeWord();
  }

  /// Stops watching for the wake phrase.
  Future<void> disableWakeWord() async {
    _wakeEnabled = false;

    if (_mode == VoiceMode.watchingForWakeWord) {
      await _teardown();
    } else {
      _safeNotify();
    }
  }

  /// Releases the microphone because the app left the foreground.
  Future<void> suspend() async {
    _suspended = true;
    await _teardown();
  }

  /// Re-arms listening after the app returns to the foreground.
  Future<void> resume() async {
    _suspended = false;

    if (_wakeEnabled && _mode == VoiceMode.idle && !_disposed) {
      await enableWakeWord();
    }
  }

  /// Clears the current voice error so the UI stops reporting it.
  void clearVoiceError() {
    _voiceError = null;
    _safeNotify();
  }

  Future<void> _initializeServices() async {
    if (_initialized) return;

    _speechAvailable = await _speechService.initialize(onIssue: _onSpeechIssue);
    _ttsAvailable = await _ttsService.initialize(onError: _onTtsError);
    _initialized = true;
  }

  Future<void> _teardown() async {
    _mode = VoiceMode.idle;
    _isListening = false;
    _isSpeaking = false;
    _relistenScheduled = false;

    // Touch only services that were actually created.
    if (_speech != null) await _speech!.cancel();
    if (_tts != null) await _tts!.stop();

    _safeNotify();
  }

  // ── Wake-word watching ────────────────────────────────────────

  Future<void> _listenForWakeWord() async {
    if (_mode != VoiceMode.watchingForWakeWord || _disposed || _suspended) {
      return;
    }
    if (_isListening || _isSpeaking || _handlingUtterance) return;

    _isListening = true;
    _safeNotify();

    try {
      await _speechService.listen(
        onResult: _onWakeResult,
        mode: SpeechListenMode.command,
      );
    } catch (_) {
      _isListening = false;
      _safeNotify();
      _scheduleWakeRelisten();
    }
  }

  void _onWakeResult(String recognizedWords, bool isFinal) {
    if (_mode != VoiceMode.watchingForWakeWord || !isFinal) return;

    _isListening = false;
    _safeNotify();

    final match = matchWakeWord(recognizedWords);
    if (!match.matched) {
      // Heard something, but it was not Kitten's name.
      _scheduleWakeRelisten();
      return;
    }

    // Woken up: switch straight into a conversation.
    _mode = VoiceMode.conversation;
    _voiceError = null;
    _safeNotify();

    if (match.remainder.isEmpty) {
      // Just "Hey Kitten" — open the microphone for a separate question.
      _scheduleReListen();
    } else {
      // "Hey Kitten, what's the weather?" — answer it right away.
      unawaited(_handleUtterance(match.remainder));
    }
  }

  void _scheduleWakeRelisten() {
    if (_relistenScheduled || _disposed || _suspended) return;
    if (_mode != VoiceMode.watchingForWakeWord) return;

    _relistenScheduled = true;
    unawaited(
      Future<void>.delayed(_listenRestartDelay, () async {
        _relistenScheduled = false;
        if (_disposed || _suspended) return;
        if (_mode != VoiceMode.watchingForWakeWord) return;
        if (_isListening || _isSpeaking || _handlingUtterance) return;
        await _listenForWakeWord();
      }),
    );
  }

  // ── Conversation ──────────────────────────────────────────────

  Future<void> _listenOnce() async {
    if (_mode != VoiceMode.conversation || _disposed || _suspended) return;
    if (_isListening || _handlingUtterance) return;

    _isListening = true;
    _voiceError = null;
    _safeNotify();

    try {
      await _speechService.listen(
        onResult: _onSpeechResult,
        mode: SpeechListenMode.dictation,
      );
    } catch (_) {
      _isListening = false;
      _voiceError = 'Voice input stopped unexpectedly. Please try again.';
      _safeNotify();
      _scheduleReListen();
    }
  }

  void _onSpeechResult(String recognizedWords, bool isFinal) {
    if (_mode != VoiceMode.conversation || !isFinal) return;

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
      if (_mode != VoiceMode.conversation || _disposed) return;

      final spoken = reply?.content.trim();
      final shouldSpeak =
          _speakReplies && _ttsAvailable && spoken != null && spoken.isNotEmpty;

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

    if (_mode != VoiceMode.conversation || _disposed) return;

    if (_handsFree) {
      _scheduleReListen();
    } else {
      await stop();
    }
  }

  /// Opens the microphone again after a short pause, once nothing else is
  /// using it.
  void _scheduleReListen() {
    if (_relistenScheduled || _disposed || _suspended) return;
    if (_mode != VoiceMode.conversation) return;

    _relistenScheduled = true;
    unawaited(
      Future<void>.delayed(_listenRestartDelay, () async {
        _relistenScheduled = false;
        if (_disposed || _suspended) return;
        if (_mode != VoiceMode.conversation) return;
        if (_isListening || _isSpeaking || _handlingUtterance) return;
        await _listenOnce();
      }),
    );
  }

  // ── Issue handling ────────────────────────────────────────────

  void _onSpeechIssue(SpeechIssue issue, String message) {
    _isListening = false;

    if (issue == SpeechIssue.permissionDenied) {
      _voiceError = message;
      if (_mode == VoiceMode.watchingForWakeWord) {
        // Stop claiming to listen when the microphone is unusable.
        _wakeEnabled = false;
      }
      _mode = VoiceMode.idle;
      _safeNotify();
      return;
    }

    if (issue == SpeechIssue.transient && _mode == VoiceMode.conversation) {
      // While merely watching, transient noise is not worth reporting.
      _voiceError = message;
    }

    _safeNotify();

    if (_mode == VoiceMode.conversation) {
      _scheduleReListen();
    } else if (_mode == VoiceMode.watchingForWakeWord) {
      _scheduleWakeRelisten();
    }
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
    _mode = VoiceMode.idle;

    chatService.removeListener(_onChatChanged);
    _speech?.dispose();
    _tts?.dispose();
    if (_ownsChatService) {
      chatService.dispose();
    }

    super.dispose();
  }
}

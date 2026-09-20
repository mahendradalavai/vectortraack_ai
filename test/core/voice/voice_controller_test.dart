import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/voice/services/speech_service.dart';
import 'package:kitten/core/voice/services/tts_service.dart';
import 'package:kitten/core/voice/services/voice_controller.dart';

import '../ai/chat_service_test.dart' show FakeAiProvider;

/// A recogniser whose listening windows are driven by the test.
class FakeSpeechService implements SpeechService {
  FakeSpeechService({this.available = true});

  bool available;
  bool _listening = false;
  SpeechResultCallback? _onResult;
  SpeechIssueCallback? _onIssue;

  int listenCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  bool disposed = false;
  SpeechListenMode? lastMode;

  @override
  bool get isAvailable => available;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize({required SpeechIssueCallback onIssue}) async {
    _onIssue = onIssue;
    return available;
  }

  @override
  Future<void> listen({
    required SpeechResultCallback onResult,
    SpeechListenMode mode = SpeechListenMode.dictation,
  }) async {
    listenCount++;
    lastMode = mode;
    _onResult = onResult;
    _listening = true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _listening = false;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    _listening = false;
  }

  @override
  void dispose() {
    disposed = true;
  }

  /// Simulates the engine delivering a transcript.
  void emit(String words, {bool isFinal = true}) {
    _listening = false;
    _onResult?.call(words, isFinal);
  }

  /// Simulates the engine ending a window without usable speech.
  void emitIssue(SpeechIssue issue, [String message = 'issue']) {
    _listening = false;
    _onIssue?.call(issue, message);
  }
}

/// A synthesiser that records what Kitten said.
class FakeTtsService implements TtsService {
  FakeTtsService({this.available = true});

  bool available;
  final List<String> spoken = [];
  int stopCount = 0;
  bool disposed = false;

  @override
  bool get isAvailable => available;

  @override
  Future<bool> initialize({
    required void Function(String message) onError,
  }) async =>
      available;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

/// Lets the pending microtasks and zero-duration timers settle.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

VoiceController _buildController({
  required FakeSpeechService speech,
  required FakeTtsService tts,
  ChatService? chatService,
  bool? speakReplies,
  bool? handsFree,
  bool? wakeWordEnabled,
}) {
  return VoiceController(
    chatService: chatService ?? ChatService(provider: FakeAiProvider()),
    speechService: speech,
    ttsService: tts,
    speakReplies: speakReplies,
    handsFree: handsFree,
    wakeWordEnabled: wakeWordEnabled,
    // Keep the loops deterministic and fast in tests.
    listenRestartDelay: Duration.zero,
  );
}

void main() {
  group('VoiceController conversation', () {
    test('start opens a listening window and reports the listening state', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();

      expect(controller.isActive, isTrue);
      expect(controller.isListening, isTrue);
      expect(controller.assistantState, AssistantState.listening);
      expect(speech.listenCount, 1);
      expect(speech.lastMode, SpeechListenMode.dictation);
      expect(controller.voiceError, isNull);
    });

    test('a final transcript is answered, spoken aloud, and the mic reopens', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      final states = <AssistantState>[];
      controller.addListener(() => states.add(controller.assistantState));

      await controller.start();
      speech.emit('Hello Kitten');
      await _settle();

      expect(controller.chatService.messages.length, 2);
      expect(controller.chatService.messages[0].content, 'Hello Kitten');
      expect(tts.spoken, ['Meow! How are you?']);
      expect(speech.listenCount, 2);
      expect(controller.isActive, isTrue);
      expect(controller.isListening, isTrue);

      expect(
        states,
        containsAllInOrder([
          AssistantState.listening,
          AssistantState.thinking,
          AssistantState.speaking,
        ]),
      );
    });

    test('partial results are ignored until the transcript is final', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();
      speech.emit('Hel', isFinal: false);
      await _settle();

      expect(controller.chatService.messages, isEmpty);
      expect(controller.isListening, isTrue);

      speech.emit('Hello', isFinal: true);
      await _settle();

      expect(controller.chatService.messages.length, 2);
    });

    test('an empty transcript keeps the loop alive without messaging Kitten', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();
      speech.emit('   ');
      await _settle();

      expect(controller.chatService.messages, isEmpty);
      expect(tts.spoken, isEmpty);
      expect(speech.listenCount, 2);
      expect(controller.voiceError, isNull);
    });

    test('a no-speech issue reopens the microphone without reporting an error', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();
      speech.emitIssue(SpeechIssue.noSpeech);
      await _settle();

      expect(controller.voiceError, isNull);
      expect(controller.isActive, isTrue);
      expect(speech.listenCount, 2);
    });

    test('a permission issue ends the session and reports it', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();
      speech.emitIssue(
        SpeechIssue.permissionDenied,
        'Microphone access was denied.',
      );
      await _settle();

      expect(controller.isActive, isFalse);
      expect(controller.isListening, isFalse);
      expect(controller.voiceError, 'Microphone access was denied.');
    });

    test('stop ends the session and releases the microphone and speaker', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();
      await controller.stop();

      expect(controller.isActive, isFalse);
      expect(controller.isListening, isFalse);
      expect(controller.assistantState, AssistantState.idle);
      expect(speech.cancelCount, greaterThanOrEqualTo(1));
      expect(tts.stopCount, greaterThanOrEqualTo(1));
    });

    test('speakReplies false leaves Kitten silent but still conversing', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(
        speech: speech,
        tts: tts,
        speakReplies: false,
      );

      await controller.start();
      speech.emit('Are you there?');
      await _settle();

      expect(controller.chatService.messages.length, 2);
      expect(tts.spoken, isEmpty);
      expect(speech.listenCount, 2);
    });

    test('hands-free off ends the session after a single reply', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(
        speech: speech,
        tts: tts,
        handsFree: false,
      );

      await controller.start();
      speech.emit('One question');
      await _settle();

      expect(controller.chatService.messages.length, 2);
      expect(speech.listenCount, 1);
      expect(controller.isActive, isFalse);
    });

    test('unavailable speech input leaves the session inactive with an error', () async {
      final speech = FakeSpeechService(available: false);
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();

      expect(controller.isActive, isFalse);
      expect(controller.speechAvailable, isFalse);
      expect(controller.voiceError, isNotNull);
    });

    test('forwards ChatService changes to its own listeners', () async {
      final chat = ChatService(provider: FakeAiProvider());
      final controller = _buildController(
        speech: FakeSpeechService(),
        tts: FakeTtsService(),
        chatService: chat,
      );

      var notifications = 0;
      controller.addListener(() => notifications++);

      await chat.sendMessage('Hi');

      expect(notifications, greaterThan(0));
    });

    test('dispose releases voice services but leaves an injected ChatService alive', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final chat = ChatService(provider: FakeAiProvider());
      final controller = _buildController(
        speech: speech,
        tts: tts,
        chatService: chat,
      );

      await controller.start();
      controller.dispose();

      expect(speech.disposed, isTrue);
      expect(tts.disposed, isTrue);

      final reply = await chat.sendMessage('Still there?');
      expect(reply, isNotNull);
    });
  });

  group('VoiceController wake word', () {
    test('is off by default and only watches once enabled', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      expect(controller.wakeWordEnabled, isFalse);
      expect(speech.listenCount, 0);

      await controller.enableWakeWord();

      expect(controller.wakeWordEnabled, isTrue);
      expect(controller.isWatchingForWakeWord, isTrue);
      expect(controller.isListening, isTrue);
      expect(speech.lastMode, SpeechListenMode.command);
    });

    test('the wake phrase with a trailing question is answered immediately', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      speech.emit('Hey Kitten, what is the weather?');
      await _settle();

      expect(controller.isActive, isTrue);
      expect(controller.chatService.messages.length, 2);
      expect(
        controller.chatService.messages[0].content,
        'what is the weather',
      );
      expect(tts.spoken, ['Meow! How are you?']);
    });

    test('a bare wake phrase opens the microphone for a separate question', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      speech.emit('Hey Kitten');
      await _settle();

      expect(controller.isActive, isTrue);
      // Nothing was asked yet, so no conversation has happened.
      expect(controller.chatService.messages, isEmpty);
      expect(tts.spoken, isEmpty);
      expect(controller.isListening, isTrue);
      expect(speech.listenCount, 2);
      expect(speech.lastMode, SpeechListenMode.dictation);
    });

    test('tolerates casing, punctuation, and stray spacing', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      speech.emit('  HEY,   Kitten!! : what is your name ');
      await _settle();

      expect(controller.isActive, isTrue);
      expect(controller.chatService.messages.first.content, 'what is your name');
    });

    test('speech that is not the wake phrase keeps watching', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      speech.emit('does this thing work');
      await _settle();

      expect(controller.isWatchingForWakeWord, isTrue);
      expect(controller.isActive, isFalse);
      expect(controller.chatService.messages, isEmpty);
      expect(controller.voiceError, isNull);
      expect(speech.listenCount, 2);
    });

    test('ending a conversation returns to watching for the wake phrase', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      speech.emit('Hey Kitten');
      await _settle();
      expect(controller.isActive, isTrue);

      await controller.stop();

      expect(controller.isWatchingForWakeWord, isTrue);
      expect(controller.isActive, isFalse);
      expect(speech.lastMode, SpeechListenMode.command);
    });

    test('suspend closes the microphone and resume re-arms watching', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      await controller.suspend();

      expect(controller.mode, VoiceMode.idle);
      expect(controller.isListening, isFalse);

      await controller.resume();

      expect(controller.isWatchingForWakeWord, isTrue);
      expect(controller.isListening, isTrue);
    });

    test('disableWakeWord stops watching', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();
      await controller.disableWakeWord();

      expect(controller.wakeWordEnabled, isFalse);
      expect(controller.mode, VoiceMode.idle);
      expect(controller.isListening, isFalse);
      expect(speech.cancelCount, greaterThanOrEqualTo(1));
    });

    test('never claims to watch when speech input is unavailable', () async {
      final speech = FakeSpeechService(available: false);
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.enableWakeWord();

      expect(controller.wakeWordEnabled, isFalse);
      expect(controller.isWatchingForWakeWord, isFalse);
      expect(controller.voiceError, isNotNull);
    });

    test('suspend during a conversation leaves nothing listening', () async {
      final speech = FakeSpeechService();
      final tts = FakeTtsService();
      final controller = _buildController(speech: speech, tts: tts);

      await controller.start();
      await controller.suspend();
      await _settle();

      expect(controller.mode, VoiceMode.idle);
      expect(controller.isListening, isFalse);
      expect(speech.isListening, isFalse);
    });
  });
}

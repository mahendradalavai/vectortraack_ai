import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/screen/config/screen_config.dart';
import 'package:kitten/core/screen/services/screen_capture_service.dart';
import 'package:kitten/core/screen/services/screen_understanding_controller.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

class FakeScreenCaptureService implements ScreenCaptureService {
  FakeScreenCaptureService({
    this.supported = true,
    this.imageBase64 = 'QUJD',
    this.error,
    this.declined = false,
  });

  bool supported;
  String imageBase64;

  /// When set, [captureScreen] throws it instead of returning an image.
  ScreenCaptureException? error;

  /// When true, the user dismissed the consent dialog.
  bool declined;

  int captureCount = 0;
  bool disposed = false;

  @override
  bool get isSupported => supported;

  @override
  Future<String?> captureScreen() async {
    captureCount++;
    final failure = error;
    if (failure != null) throw failure;
    if (declined) return null;
    return imageBase64;
  }

  @override
  void dispose() => disposed = true;
}

class RecordingProvider implements AiProvider {
  RecordingProvider({this.chunks = const ['Looks like ', 'a settings page.']});

  final List<String> chunks;
  ChatRequest? lastRequest;

  @override
  String get providerName => 'RecordingProvider';

  @override
  Future<ChatResponse> sendMessage(ChatRequest request) async {
    lastRequest = request;
    return const ChatResponse(content: 'ok', model: 'fake');
  }

  @override
  Stream<String> streamMessage(ChatRequest request) async* {
    lastRequest = request;
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  @override
  Future<bool> checkConnection() async => true;

  @override
  void dispose() {}
}

class FakeScreenStorage extends SecureStorageService {
  FakeScreenStorage({this.explained});

  bool? explained;

  @override
  Future<bool?> getScreenReadExplained() async => explained;

  @override
  Future<void> saveScreenReadExplained(bool shown) async => explained = shown;
}

void main() {
  group('ScreenUnderstandingController', () {
    late RecordingProvider provider;
    late ChatService chatService;

    setUp(() {
      provider = RecordingProvider();
      chatService = ChatService(provider: provider);
    });

    ScreenUnderstandingController build({
      FakeScreenCaptureService? capture,
      FakeScreenStorage? storage,
    }) =>
        ScreenUnderstandingController(
          chatService: chatService,
          captureService: capture ?? FakeScreenCaptureService(),
          storage: storage ?? FakeScreenStorage(),
        );

    test('a read captures once and answers on the vision model', () async {
      final capture = FakeScreenCaptureService();
      final controller = build(capture: capture);

      final outcome = await controller.readScreen();

      expect(outcome.isOk, isTrue);
      expect(outcome.error, isNull);
      expect(capture.captureCount, 1);
      expect(provider.lastRequest!.model, AiConfig.visionModel);

      // The screenshot is attached to the user turn, and the default question
      // is used when the user typed nothing.
      final userMessage = chatService.messages.first;
      expect(userMessage.hasImage, isTrue);
      expect(userMessage.content, ScreenConfig.defaultQuestion);

      // Kitten's answer streams into the shared conversation.
      expect(chatService.messages.last.content, 'Looks like a settings page.');

      controller.dispose();
    });

    test('a typed question replaces the default prompt', () async {
      final controller = build();

      await controller.readScreen(question: '  what does this error mean?  ');

      expect(
        chatService.messages.first.content,
        'what does this error mean?',
      );

      controller.dispose();
    });

    test('declining consent is reported as cancelled, not as an error',
        () async {
      final capture = FakeScreenCaptureService(declined: true);
      final controller = build(capture: capture);

      final outcome = await controller.readScreen();

      expect(outcome.status, ScreenReadStatus.cancelled);
      expect(outcome.error, isNull);
      expect(capture.captureCount, 1);
      // Nothing was sent anywhere and nothing was said.
      expect(chatService.messages, isEmpty);
      expect(provider.lastRequest, isNull);

      controller.dispose();
    });

    test('an unsupported platform never asks for a capture', () async {
      final capture = FakeScreenCaptureService(supported: false);
      final controller = build(capture: capture);

      expect(controller.isSupported, isFalse);
      final outcome = await controller.readScreen();

      expect(outcome.status, ScreenReadStatus.failed);
      expect(outcome.error, contains('only available on Android'));
      expect(capture.captureCount, 0);

      controller.dispose();
    });

    test('capture failures become friendly messages', () async {
      final cases = <ScreenCaptureException, String>{
        const ScreenCaptureException(ScreenCaptureException.timeoutCode):
            'in time',
        const ScreenCaptureException(ScreenCaptureException.busyCode):
            'already running',
        const ScreenCaptureException(ScreenCaptureException.failedCode):
            'could not capture',
      };

      for (final entry in cases.entries) {
        final controller = build(
          capture: FakeScreenCaptureService(error: entry.key),
        );

        final outcome = await controller.readScreen();

        expect(outcome.status, ScreenReadStatus.failed);
        expect(outcome.error, contains(entry.value));
        // A failed capture must not fabricate a conversation turn.
        expect(chatService.messages, isEmpty);

        controller.dispose();
      }
    });

    test('an empty screenshot is refused rather than sent to the model',
        () async {
      final controller = build(
        capture: FakeScreenCaptureService(imageBase64: ''),
      );

      final outcome = await controller.readScreen();

      expect(outcome.status, ScreenReadStatus.failed);
      expect(outcome.error, contains('empty screenshot'));
      expect(provider.lastRequest, isNull);

      controller.dispose();
    });

    test('an oversized screenshot is refused before it reaches Groq', () async {
      // Base64 of just over the allowed payload.
      final huge = 'A' * (AiConfig.maxImageBytes * 4 ~/ 3 + 16);
      final controller = build(
        capture: FakeScreenCaptureService(imageBase64: huge),
      );

      final outcome = await controller.readScreen();

      expect(outcome.status, ScreenReadStatus.failed);
      expect(outcome.error, contains('too large'));
      expect(provider.lastRequest, isNull);

      controller.dispose();
    });

    test('a model failure surfaces the chat error to the caller', () async {
      final failing = ChatService(
        provider: _FailingProvider(),
      );
      final controller = ScreenUnderstandingController(
        chatService: failing,
        captureService: FakeScreenCaptureService(),
        storage: FakeScreenStorage(),
      );

      final outcome = await controller.readScreen();

      expect(outcome.status, ScreenReadStatus.failed);
      expect(outcome.error, isNotNull);

      controller.dispose();
    });

    test('isCapturing is true only while a read is in flight', () async {
      final controller = build();
      expect(controller.isCapturing, isFalse);

      final pending = controller.readScreen();
      expect(controller.isCapturing, isTrue);

      await pending;
      expect(controller.isCapturing, isFalse);

      controller.dispose();
    });

    test('a second tap while busy is ignored rather than double-capturing',
        () async {
      final capture = FakeScreenCaptureService();
      final controller = build(capture: capture);

      final first = controller.readScreen();
      final second = await controller.readScreen();
      await first;

      expect(second.status, ScreenReadStatus.cancelled);
      expect(capture.captureCount, 1);

      controller.dispose();
    });

    test('the privacy note is shown once and remembered', () async {
      final storage = FakeScreenStorage();
      final controller = build(storage: storage);

      expect(controller.needsIntroduction, isTrue);
      expect(await storage.getScreenReadExplained(), isNull);

      await controller.markIntroduced();

      expect(controller.needsIntroduction, isFalse);
      expect(storage.explained, isTrue);

      controller.dispose();
    });

    test('a stored flag suppresses the note on later launches', () async {
      final controller = build(storage: FakeScreenStorage(explained: true));

      await controller.restoreIntroduction();

      expect(controller.needsIntroduction, isFalse);

      controller.dispose();
    });

    test('dispose leaves an injected capture service alone', () {
      final capture = FakeScreenCaptureService();
      final controller = build(capture: capture);

      controller.dispose();

      // The caller owns what it injected; only a service this controller
      // created itself would be released.
      expect(capture.disposed, isFalse);
    });
  });
}

class _FailingProvider implements AiProvider {
  @override
  String get providerName => 'FailingProvider';

  @override
  Future<ChatResponse> sendMessage(ChatRequest request) async =>
      throw StateError('no');

  @override
  Stream<String> streamMessage(ChatRequest request) =>
      Stream<String>.error(StateError('no'));

  @override
  Future<bool> checkConnection() async => false;

  @override
  void dispose() {}
}

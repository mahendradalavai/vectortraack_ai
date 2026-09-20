import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kitten/app/app.dart';
import 'package:kitten/core/ai/config/ai_config.dart';
import 'package:kitten/core/ai/models/chat_request.dart';
import 'package:kitten/core/ai/models/chat_response.dart';
import 'package:kitten/core/ai/providers/ai_provider.dart';
import 'package:kitten/core/ai/providers/groq_provider.dart';
import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/screen/services/method_channel_screen_capture_service.dart';
import 'package:kitten/core/screen/services/screen_capture_service.dart';
import 'package:kitten/core/screen/services/screen_understanding_controller.dart';
import 'package:kitten/core/services/secure_storage_service.dart';

/// These run on a real device, because MediaProjection, its consent dialog,
/// and the foreground service it requires have no host-side stand-in.
///
/// Before running them, pre-approve the consent dialog so the capture is not
/// waiting on a system prompt nothing can tap:
///   adb shell appops set com.example.kitten android:media_projection allow
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('screen understanding on device', () {
    testWidgets('captures a real screenshot and hands back JPEG bytes',
        (tester) async {
      final capture = MethodChannelScreenCaptureService();

      expect(capture.isSupported, isTrue);

      final base64Jpeg = await capture.captureScreen();
      expect(base64Jpeg, isNotNull, reason: 'check that the media projection '
          'app-op is granted');

      final bytes = base64Decode(base64Jpeg!);
      expect(bytes.length, greaterThan(1000));
      // JPEG files start with the SOI marker, which proves this is a real
      // encoded image rather than an empty buffer.
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);

      debugPrint('captured ${bytes.length} bytes of screen');
    });

    testWidgets('the privacy note appears before the first read', (tester) async {
      await tester.pumpWidget(const KittenApp());
      await tester.pump(const Duration(milliseconds: 500));

      final readButton = find.byTooltip('Read my screen');
      expect(readButton, findsOneWidget);

      await tester.tap(readButton);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Read your screen?'), findsOneWidget);
      expect(
        find.textContaining('send it to a Groq vision model'),
        findsOneWidget,
      );

      // Declining must not capture anything or add a turn to the chat.
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Read your screen?'), findsNothing);
      expect(find.textContaining('Screenshot'), findsNothing);
    });

    testWidgets('a real screenshot reaches Kitten end to end', (tester) async {
      final storage = SecureStorageService();
      final apiKey = await storage.getGroqApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        markTestSkipped('no Groq API key configured on this device');
        return;
      }

      final chatService = ChatService(
        provider: GroqProvider(secureStorage: storage),
      );
      final controller = ScreenUnderstandingController(
        chatService: chatService,
        captureService: MethodChannelScreenCaptureService(),
        storage: storage,
      );

      final outcome = await controller.readScreen(
        question: 'In one short sentence, what is on my screen?',
      );

      expect(outcome.status, ScreenReadStatus.ok, reason: outcome.error);

      final screenshotTurn = chatService.messages.first;
      expect(screenshotTurn.hasImage, isTrue);

      final reply = chatService.messages.last;
      expect(reply.isAssistant, isTrue);
      expect(reply.content.trim(), isNotEmpty);
      debugPrint('vision reply: ${reply.content.trim()}');

      controller.dispose();
      chatService.dispose();
    });

    testWidgets('the vision model is asked instead of the text model',
        (tester) async {
      final provider = _CapturingProvider();
      final chatService = ChatService(provider: provider);
      final controller = ScreenUnderstandingController(
        chatService: chatService,
        // The capture itself is covered above; this test is about routing.
        captureService: _TinyCapture(),
        storage: SecureStorageService(),
      );

      await controller.readScreen(question: 'what is this?');

      expect(provider.lastModel, AiConfig.visionModel);

      controller.dispose();
      chatService.dispose();
    });
  });
}

/// A standing in for a real capture, so model routing can be asserted without
/// waiting on the system consent dialog.
class _TinyCapture implements ScreenCaptureService {
  @override
  bool get isSupported => true;

  @override
  Future<String?> captureScreen() async =>
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//';  

  @override
  void dispose() {}
}

/// Records the model each request asks for, then fails cheaply.
class _CapturingProvider implements AiProvider {
  String? lastModel;

  @override
  String get providerName => 'CapturingProvider';

  @override
  Future<ChatResponse> sendMessage(ChatRequest request) async {
    lastModel = request.model;
    return const ChatResponse(content: '', model: 'none');
  }

  @override
  Stream<String> streamMessage(ChatRequest request) async* {
    lastModel = request.model;
  }

  @override
  Future<bool> checkConnection() async => false;

  @override
  void dispose() {}
}

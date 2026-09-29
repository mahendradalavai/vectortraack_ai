import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/awareness/services/app_awareness_controller.dart';
import 'package:kitten/core/background/services/background_assistant_controller.dart';
import 'package:kitten/core/constants/app_constants.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/core/overlay/models/overlay_app_context.dart';
import 'package:kitten/core/overlay/services/floating_overlay_controller.dart';
import 'package:kitten/core/phone/services/method_channel_phone_capability_service.dart';
import 'package:kitten/core/screen/services/screen_understanding_controller.dart';
import 'package:kitten/core/tools/built_in/get_current_app_tool.dart';
import 'package:kitten/core/tools/built_in/get_current_time_tool.dart';
import 'package:kitten/core/tools/built_in/phone_action_tools.dart';
import 'package:kitten/core/tools/tool_registry.dart';
import 'package:kitten/core/voice/config/voice_config.dart';
import 'package:kitten/core/voice/services/voice_controller.dart';
import 'package:kitten/features/home/presentation/widgets/chat_bubble.dart';
import 'package:kitten/features/kitten/presentation/widgets/kitten_avatar.dart';
import 'package:kitten/features/settings/presentation/pages/settings_page.dart';
import 'package:kitten/shared/widgets/assistant_status_indicator.dart';

/// The main screen of the Kitten AI application.
///
/// Integrates the Kitten avatar, status indicator, voice placeholder,
/// text conversation history, and text input field connected to the AI provider.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.voiceController,
    this.awarenessController,
    this.screenController,
    this.overlayController,
    this.backgroundAssistantController,
  });

  /// Optional injected [VoiceController] for testing and dependency injection.
  ///
  /// It also supplies the [ChatService] used for the text conversation.
  final VoiceController? voiceController;

  /// Optional injected [AppAwarenessController] for testing.
  final AppAwarenessController? awarenessController;

  /// Optional injected [ScreenUnderstandingController] for testing.
  final ScreenUnderstandingController? screenController;

  /// Optional injected overlay controller for testing and dependency injection.
  final FloatingOverlayController? overlayController;
  final BackgroundAssistantController? backgroundAssistantController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final VoiceController _voice;
  late final ChatService _chatService;
  late final AppAwarenessController _awareness;
  late final ScreenUnderstandingController _screen;
  late final FloatingOverlayController _overlay;
  late final BackgroundAssistantController _backgroundAssistant;
  StreamSubscription<String>? _backgroundCommandSubscription;
  StreamSubscription<OverlayAppContext>? _overlayOpeningSubscription;

  /// The chat service we built ourselves, and so must dispose.
  ChatService? _ownedChatService;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Focused after the floating Kitten hands a conversation over, so the reply
  /// can be typed straight away.
  final FocusNode _inputFocus = FocusNode();

  /// The last voice problem already shown, so it is not repeated.
  String? _shownVoiceError;

  /// Ages Kitten's mood so it can doze off after a quiet spell.
  Timer? _idleTicker;

  @override
  void initState() {
    super.initState();
    _awareness = widget.awarenessController ?? AppAwarenessController();
    _awareness.addListener(_onAwarenessUpdate);

    if (widget.voiceController == null) {
      // Kitten's replies may mention the app the user was last using, so the
      // conversation is given a way to read that context.
      final phoneService = MethodChannelPhoneCapabilityService();
      final toolRegistry = ToolRegistry()
        ..registerAll([
          const GetCurrentTimeTool(),
          GetCurrentAppTool(_awareness),
          OpenDialerTool(phoneService),
          ComposeMessageTool(phoneService),
          SetAlarmTool(phoneService),
          SetTimerTool(phoneService),
          OpenAppTool(phoneService),
        ]);
      final chatService = ChatService(
        contextProvider: _awareness.buildPromptContext,
        toolRegistry: toolRegistry,
      );
      _ownedChatService = chatService;
      _voice = VoiceController(chatService: chatService);
    } else {
      _voice = widget.voiceController!;
    }
    _chatService = _voice.chatService;
    _voice.addListener(_onVoiceUpdate);

    // Screen understanding streams its answer into the same conversation.
    _screen =
        widget.screenController ??
        ScreenUnderstandingController(chatService: _chatService);
    _screen.addListener(_onScreenUpdate);
    _overlay = widget.overlayController ?? FloatingOverlayController();
    _backgroundAssistant =
        widget.backgroundAssistantController ?? BackgroundAssistantController();
    _backgroundCommandSubscription = _backgroundAssistant.commands.listen(
      _handleBackgroundCommand,
    );
    unawaited(_backgroundAssistant.refresh());

    // The floating Kitten says what it can see and then hands that app over
    // when it is tapped, so the conversation starts in context.
    _overlayOpeningSubscription = _overlay.appOpenings.listen(
      _handleOverlayAppOpening,
    );
    unawaited(_takePendingOverlayApp());

    WidgetsBinding.instance.addObserver(this);

    // Re-apply the user's saved preferences.
    unawaited(_voice.restorePreferences());
    unawaited(_awareness.restorePreferences());
    unawaited(_screen.restoreIntroduction());

    _idleTicker = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _chatService.personality.tick(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTicker?.cancel();
    _voice.removeListener(_onVoiceUpdate);
    if (widget.voiceController == null) {
      _voice.dispose();
    }
    if (widget.overlayController == null) {
      _overlay.dispose();
    }
    _backgroundCommandSubscription?.cancel();
    _overlayOpeningSubscription?.cancel();
    _inputFocus.dispose();
    if (widget.backgroundAssistantController == null) {
      _backgroundAssistant.dispose();
    }
    _ownedChatService?.dispose();
    _awareness.removeListener(_onAwarenessUpdate);
    if (widget.awarenessController == null) {
      _awareness.dispose();
    }
    _screen.removeListener(_onScreenUpdate);
    if (widget.screenController == null) {
      _screen.dispose();
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never hold the microphone while the app is not in the foreground, and
    // stop reading usage stats while nobody can see the result.
    if (state == AppLifecycleState.resumed) {
      unawaited(_voice.resume());
      unawaited(_awareness.resume());
      // A tap on the floating cat brings Kitten forward, so anything it handed
      // over before this frame is collected here.
      unawaited(_takePendingOverlayApp());
    } else {
      unawaited(_voice.suspend());
      unawaited(_awareness.suspend());
    }
  }

  void _onAwarenessUpdate() {
    if (mounted) setState(() {});
  }

  void _onScreenUpdate() {
    if (mounted) setState(() {});
  }

  /// Takes one screenshot with the user's consent and asks Kitten about it.
  Future<void> _handleReadScreen() async {
    if (_isBusy || _screen.isCapturing) return;

    if (!_screen.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screen reading is only available on Android.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Explain what is about to happen, once, before anything is captured.
    if (_screen.needsIntroduction) {
      final agreed = await _confirmScreenReading();
      if (agreed != true) return;
      await _screen.markIntroduced();
    }

    // Typed text becomes the question; otherwise Kitten is asked to describe
    // the screen.
    final question = _textController.text.trim();
    if (question.isNotEmpty) _textController.clear();

    final outcome = await _screen.readScreen(
      question: question.isEmpty ? null : question,
    );

    if (!mounted) return;
    final error = outcome.error;
    if (outcome.status == ScreenReadStatus.failed && error != null) {
      _showErrorSnackBar(error);
    }
  }

  /// The one-time privacy explanation shown before the first screen read.
  Future<bool?> _confirmScreenReading() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Read your screen?'),
        content: const Text(
          'Kitten will take one screenshot and send it to a Groq vision model '
          'so it can answer your question about what is on your screen.\n\n'
          'Android asks you to allow the capture every time, nothing runs in '
          'the background, and no screenshot is taken unless you press this '
          'button.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// True while Kitten is thinking or streaming a reply.
  bool get _isBusy =>
      _chatService.isStreaming ||
      _voice.assistantState == AssistantState.thinking;

  void _onVoiceUpdate() {
    if (!mounted) return;

    setState(() {});
    // Streaming updates arrive per token, so jump instead of animating to
    // avoid fighting a never-ending scroll animation.
    _scrollToBottom(animate: !_chatService.isStreaming);
    _maybeShowVoiceError();
  }

  /// Surfaces a new voice problem once, without nagging on every rebuild.
  void _maybeShowVoiceError() {
    final error = _voice.voiceError;
    if (error == null) {
      _shownVoiceError = null;
      return;
    }
    if (error == _shownVoiceError) return;

    _shownVoiceError = error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _toggleVoice() async {
    await _voice.toggle();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _handleSendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _chatService.isStreaming || _isBusy) {
      return;
    }

    // Typing takes over from the hands-free loop.
    if (_voice.isActive) {
      await _voice.stop();
    }

    _textController.clear();
    await _chatService.sendMessageStreaming(text);

    if (mounted && _chatService.lastError != null) {
      _showErrorSnackBar(_chatService.lastError!);
    }
  }

  /// Collects an app the overlay handed over before this page could listen.
  Future<void> _takePendingOverlayApp() async {
    final context = await _overlay.takePendingAppContext();
    if (context != null) _handleOverlayAppOpening(context);
  }

  /// Opens the conversation already knowing which app the user came from.
  ///
  /// The line is the same one the floating Kitten showed, so the chat picks up
  /// exactly where the bubble left off. It is seeded locally rather than sent
  /// to the model, which would cost a request just to say hello.
  void _handleOverlayAppOpening(OverlayAppContext context) {
    if (!mounted) return;

    final seeded = _chatService.seedAssistantMessage(context.openingLine);
    if (seeded && !_voice.isActive) {
      _inputFocus.requestFocus();
      _scrollToBottom(animate: false);
    }
    setState(() {});
  }

  void _handleBackgroundCommand(String command) {
    if (!mounted) return;
    _textController.text = command;
    unawaited(_handleSendMessage());
  }

  void _showErrorSnackBar(String message) {
    final cs = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: cs.error,
        // Decided from the typed error, not by matching message text.
        action: _chatService.lastErrorRequiresSettings
            ? SnackBarAction(
                label: 'Settings',
                textColor: cs.onError,
                onPressed: _openSettings,
              )
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Hand over the live controllers so Settings switches apply at once.
        builder: (_) => SettingsPage(
          voiceController: _voice,
          awarenessController: _awareness,
          overlayController: _overlay,
          backgroundAssistantController: _backgroundAssistant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = _voice.assistantState;
    final messages = _chatService.messages;
    final isThinking = state == AssistantState.thinking;
    final isStreaming = _chatService.isStreaming;
    final streamingMessage = _chatService.streamingMessage;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '🐱 ${AppConstants.appName}',
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const Spacer(),
                  if (messages.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.refresh_outlined),
                      tooltip: 'Clear Chat',
                      onPressed: isThinking
                          ? null
                          : _chatService.clearConversation,
                    ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),

            // ── Main conversation & avatar area ────────────
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 8),

                  // Kitten avatar (reacts dynamically to AssistantState)
                  Center(
                    child: KittenAvatar(
                      state: state,
                      mood: _chatService.personality.mood,
                      size: 140,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Greeting header
                  Text(
                    AppConstants.kittenGreeting,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppConstants.kittenPrompt,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Voice Talk button & Status Chip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _toggleVoice,
                        icon: Icon(
                          _voice.isActive
                              ? Icons.stop_circle_outlined
                              : Icons.mic,
                          size: 18,
                        ),
                        label: Text(_voice.isActive ? 'Stop' : 'Talk'),
                      ),
                      const SizedBox(width: 12),
                      AssistantStatusIndicator(state: state),
                    ],
                  ),

                  // Wake-word hint, shown only while actually waiting.
                  if (_voice.isWatchingForWakeWord) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hearing_outlined,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Waiting for '
                          '"${VoiceConfig.wakePhrases.first}"...',
                          style: tt.bodySmall?.copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                  ],

                  // The app Kitten last saw the user in, once it knows one.
                  if (_awareness.currentApp != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Last app: ${_awareness.currentApp!.displayName}',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Conversation history or placeholder
                  if (messages.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.outlineVariant.withAlpha(80),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Say hello to Kitten!',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Type a message below to chat with your AI companion.',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    ...messages.map((m) => ChatBubble(message: m)),
                    // Show Kitten's reply as it is being generated.
                    if (isStreaming &&
                        streamingMessage != null &&
                        streamingMessage.content.isNotEmpty)
                      ChatBubble(message: streamingMessage)
                    else if (isThinking)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: cs.primaryContainer,
                              child: const Text(
                                '🐱',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Kitten is thinking...',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Chat input bar ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant.withAlpha(80)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _inputFocus,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !isThinking,
                        decoration: InputDecoration(
                          hintText: isThinking
                              ? 'Waiting for Kitten...'
                              : 'Chat with Kitten...',
                          hintStyle: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _handleSendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed:
                          (_isBusy ||
                              _screen.isCapturing ||
                              !_screen.isSupported)
                          ? null
                          : _handleReadScreen,
                      tooltip: 'Read my screen',
                      icon: _screen.isCapturing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.screenshot_monitor_outlined,
                              size: 20,
                            ),
                    ),
                    IconButton.filled(
                      onPressed: isStreaming
                          ? _chatService.cancelStreaming
                          : (isThinking ? null : _handleSendMessage),
                      icon: isStreaming
                          ? const Icon(Icons.stop, size: 20)
                          : (isThinking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send, size: 20)),
                      tooltip: isStreaming ? 'Stop response' : 'Send message',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

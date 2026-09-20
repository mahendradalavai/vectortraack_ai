import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/constants/app_constants.dart';
import 'package:kitten/core/models/assistant_state.dart';
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
  const HomePage({super.key, this.voiceController});

  /// Optional injected [VoiceController] for testing and dependency injection.
  ///
  /// It also supplies the [ChatService] used for the text conversation.
  final VoiceController? voiceController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final VoiceController _voice;
  late final ChatService _chatService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// The last voice problem already shown, so it is not repeated.
  String? _shownVoiceError;

  /// Ages Kitten's mood so it can doze off after a quiet spell.
  Timer? _idleTicker;

  @override
  void initState() {
    super.initState();
    _voice = widget.voiceController ?? VoiceController();
    _chatService = _voice.chatService;
    _voice.addListener(_onVoiceUpdate);
    WidgetsBinding.instance.addObserver(this);

    // Re-apply the user's saved voice preferences.
    unawaited(_voice.restorePreferences());

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
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never hold the microphone while the app is not in the foreground.
    if (state == AppLifecycleState.resumed) {
      _voice.resume();
    } else {
      _voice.suspend();
    }
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
        // Hand over the live voice session so Settings switches apply at once.
        builder: (_) => SettingsPage(voiceController: _voice),
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
                      onPressed: isThinking ? null : _chatService.clearConversation,
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
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
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
                              child: const Text('🐱', style: TextStyle(fontSize: 14)),
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
                  top: BorderSide(
                    color: cs.outlineVariant.withAlpha(80),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
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

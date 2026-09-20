import 'package:flutter/material.dart';

import 'package:kitten/core/ai/services/chat_service.dart';
import 'package:kitten/core/constants/app_constants.dart';
import 'package:kitten/core/models/assistant_state.dart';
import 'package:kitten/features/home/presentation/widgets/chat_bubble.dart';
import 'package:kitten/features/kitten/presentation/widgets/kitten_avatar.dart';
import 'package:kitten/features/settings/presentation/pages/settings_page.dart';
import 'package:kitten/shared/widgets/assistant_status_indicator.dart';

/// The main screen of the Kitten AI application.
///
/// Integrates the Kitten avatar, status indicator, voice placeholder,
/// text conversation history, and text input field connected to the AI provider.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.chatService});

  /// Optional injected [ChatService] for testing and dependency injection.
  final ChatService? chatService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ChatService _chatService;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatService();
    _chatService.addListener(_onChatServiceUpdate);
  }

  @override
  void dispose() {
    _chatService.removeListener(_onChatServiceUpdate);
    if (widget.chatService == null) {
      _chatService.dispose();
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// True while Kitten is thinking or streaming a reply.
  bool get _isBusy =>
      _chatService.isStreaming ||
      _chatService.assistantState == AssistantState.thinking;

  void _onChatServiceUpdate() {
    if (mounted) {
      setState(() {});
      // Streaming updates arrive per token, so jump instead of animating to
      // avoid fighting a never-ending scroll animation.
      _scrollToBottom(animate: !_chatService.isStreaming);
    }
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

  void _onMicPressed() {
    // Placeholder — will be implemented in a future voice-input task.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice input will be enabled in a future update.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = _chatService.assistantState;
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
                    child: KittenAvatar(state: state, size: 140),
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
                        onPressed: _onMicPressed,
                        icon: const Icon(Icons.mic, size: 18),
                        label: const Text('Talk'),
                      ),
                      const SizedBox(width: 12),
                      AssistantStatusIndicator(state: state),
                    ],
                  ),
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

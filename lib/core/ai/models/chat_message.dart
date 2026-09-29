import 'package:kitten/core/tools/models/tool_call.dart';

/// The role of the entity that sent a chat message.
enum ChatRole {
  system,
  user,
  assistant,
  tool;

  String toJson() => name;

  static ChatRole fromJson(String value) {
    switch (value.toLowerCase()) {
      case 'system':
        return ChatRole.system;
      case 'user':
        return ChatRole.user;
      case 'assistant':
        return ChatRole.assistant;
      case 'tool':
        return ChatRole.tool;
      default:
        return ChatRole.user;
    }
  }
}

/// A single message in an AI conversation.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.imageDataBase64,
    this.imageMimeType = 'image/jpeg',
    this.toolCallId,
    this.toolName,
    this.toolCalls,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.system(String content) => ChatMessage(
        role: ChatRole.system,
        content: content,
      );

  factory ChatMessage.user(String content) => ChatMessage(
        role: ChatRole.user,
        content: content,
      );

  factory ChatMessage.assistant(String content) => ChatMessage(
        role: ChatRole.assistant,
        content: content,
      );

  /// A user message that also carries an image, such as a screenshot.
  ///
  /// [imageMimeType] defaults to `image/jpeg`, which is what Android's screen
  /// capture produces.
  factory ChatMessage.userWithImage(
    String content,
    String imageDataBase64, {
    String imageMimeType = 'image/jpeg',
  }) =>
      ChatMessage(
        role: ChatRole.user,
        content: content,
        imageDataBase64: imageDataBase64,
        imageMimeType: imageMimeType,
      );

  /// An assistant message that asks Kitten to run tools.
  ///
  /// [content] carries any text the model wrote alongside the calls, which is
  /// often empty.
  factory ChatMessage.assistantWithToolCalls(
    List<ToolCall> toolCalls, {
    String content = '',
  }) =>
      ChatMessage(
        role: ChatRole.assistant,
        content: content,
        toolCalls: toolCalls,
      );

  /// The result of one executed tool call, sent back to the model.
  factory ChatMessage.toolResult({
    required String toolCallId,
    required String toolName,
    required String content,
  }) =>
      ChatMessage(
        role: ChatRole.tool,
        content: content,
        toolCallId: toolCallId,
        toolName: toolName,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: ChatRole.fromJson(json['role'] as String? ?? 'user'),
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  final ChatRole role;
  final String content;
  final DateTime timestamp;

  /// Base64 image data attached to this message, or null for plain text.
  final String? imageDataBase64;

  /// The MIME type of [imageDataBase64], when an image is attached.
  final String imageMimeType;

  /// The provider id of the tool call this result answers, for tool messages.
  final String? toolCallId;

  /// The tool this result came from, so the interface can show it.
  final String? toolName;

  /// The tool calls an assistant message asked for, or null.
  final List<ToolCall>? toolCalls;

  /// Whether this message carries an image for a vision model.
  bool get hasImage => imageDataBase64 != null && imageDataBase64!.isNotEmpty;

  /// Whether this message reports a tool result.
  bool get isTool => role == ChatRole.tool;

  /// Whether this message asks Kitten to run tools.
  bool get requestsTools =>
      role == ChatRole.assistant &&
      toolCalls != null &&
      toolCalls!.isNotEmpty;

  /// A copy of this message without its image, keeping role and text.
  ///
  /// Used when replaying history: a vision model has already described that
  /// screenshot, so re-sending it on every later turn would waste tokens.
  ChatMessage withoutImage() {
    if (!hasImage) return this;
    return ChatMessage(
      role: role,
      content: content,
      timestamp: timestamp,
    );
  }

  /// The OpenAI-compatible content for this message.
  ///
  /// A plain message serializes to a string. One carrying an image serializes
  /// to the multimodal content-part array that vision models expect, with the
  /// image embedded as a data URL so no upload step is needed.
  dynamic contentForRequest() {
    final image = imageDataBase64;
    if (image == null || image.isEmpty) return content;

    return [
      {'type': 'text', 'text': content},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$imageMimeType;base64,$image'},
      },
    ];
  }

  Map<String, dynamic> toJson() {
    // An assistant message asking for tools must carry them alongside content,
    // which is often empty, or the model loses track of its own calls.
    if (requestsTools) {
      return {
        'role': role.toJson(),
        'content': content,
        'tool_calls': [for (final call in toolCalls!) call.toGroqJson()],
      };
    }

    if (isTool) {
      return {
        'role': role.toJson(),
        'tool_call_id': toolCallId,
        'content': content,
      };
    }

    return {
      'role': role.toJson(),
      'content': contentForRequest(),
    };
  }

  bool get isUser => role == ChatRole.user;
  bool get isAssistant => role == ChatRole.assistant;
  bool get isSystem => role == ChatRole.system;
}

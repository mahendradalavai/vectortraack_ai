/// The role of the entity that sent a chat message.
enum ChatRole {
  system,
  user,
  assistant;

  String toJson() => name;

  static ChatRole fromJson(String value) {
    switch (value.toLowerCase()) {
      case 'system':
        return ChatRole.system;
      case 'user':
        return ChatRole.user;
      case 'assistant':
        return ChatRole.assistant;
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

  Map<String, dynamic> toJson() => {
        'role': role.toJson(),
        'content': content,
      };

  bool get isUser => role == ChatRole.user;
  bool get isAssistant => role == ChatRole.assistant;
  bool get isSystem => role == ChatRole.system;
}

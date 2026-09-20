/// Represents the current state of the Kitten AI assistant.
///
/// Future tasks will drive transitions between these states
/// based on voice input, AI processing, and speech output.
enum AssistantState {
  /// The assistant is waiting for activation.
  idle('Idle', '😴'),

  /// The assistant is listening to the user's voice.
  listening('Listening...', '👂'),

  /// The assistant is processing / generating a response.
  thinking('Thinking...', '🤔'),

  /// The assistant is speaking a response.
  speaking('Speaking...', '🗣️');

  const AssistantState(this.label, this.emoji);

  /// A human-readable label for display in the UI.
  final String label;

  /// An emoji representation for quick visual identification.
  final String emoji;
}

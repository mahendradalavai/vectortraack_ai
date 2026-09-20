/// Kitten's current emotional state.
///
/// A mood does double duty: it is painted onto the avatar and injected into
/// the system prompt, so Kitten's tone and its expression always agree.
enum KittenMood {
  /// Alert and inquisitive — the default resting state.
  curious(
    'Curious',
    'You are alert and inquisitive right now. Ask warm follow-up questions '
    'and show genuine interest in what the user is telling you.',
  ),

  /// Bouncy and game for anything.
  playful(
    'Playful',
    'You are feeling playful and bouncy right now. Be a little sillier than '
    'usual, enjoy wordplay, and keep it affectionate rather than distracting.',
  ),

  /// Settled and comfortable.
  content(
    'Content',
    'You are settled and comfortable right now. Speak calmly and warmly, and '
    'keep your answers steady and reassuring.',
  ),

  /// Attached and fond of the user.
  affectionate(
    'Affectionate',
    'You feel fond and affectionate toward the user right now. Be extra warm '
    'and encouraging, while still answering the question properly.',
  ),

  /// Dozing after a long quiet spell.
  sleepy(
    'Sleepy',
    'You were dozing and have just been woken up. Be soft, drowsy, and a '
    'little bit sleepy for the first sentence or two, then help normally.',
  ),

  /// Worried that something went wrong.
  concerned(
    'Concerned',
    'Something just went wrong in the app, so you are a little worried. Be '
    'gentle and reassuring, and help the user get back on track.',
  );

  const KittenMood(this.label, this.promptFragment);

  /// A short human-readable name for the mood.
  final String label;

  /// The instruction added to the system prompt while this mood is active.
  final String promptFragment;
}

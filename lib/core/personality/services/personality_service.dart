import 'package:flutter/foundation.dart';

import 'package:kitten/core/ai/prompts/kitten_system_prompt.dart';
import 'package:kitten/core/personality/models/kitten_mood.dart';

/// Tracks Kitten's evolving mood and rapport with the user.
///
/// Mood is driven by simple, deterministic rules over the conversation so the
/// behaviour is predictable and testable, rather than by asking the model to
/// invent a feeling. The resulting mood is fed back into the system prompt by
/// [buildSystemPrompt], so tone and expression stay consistent.
class PersonalityService extends ChangeNotifier {
  PersonalityService({
    KittenMood initialMood = KittenMood.curious,
    DateTime Function()? clock,
    Duration? sleepAfter,
  })  : _mood = initialMood,
        _clock = clock ?? DateTime.now,
        _sleepAfter = sleepAfter ?? const Duration(seconds: 90) {
    _lastInteraction = _clock();
  }

  final DateTime Function() _clock;
  final Duration _sleepAfter;

  static const Set<String> _affectionateWords = <String>{
    'love', 'thanks', 'thank', 'sweet', 'cute', 'adorable',
    'lovely', 'hug', 'purr', 'best', 'friend', 'please',
  };

  static const Set<String> _playfulWords = <String>{
    'play', 'joke', 'funny', 'game', 'silly', 'haha', 'lol', 'fun', 'toy',
  };

  KittenMood _mood;
  int _affinity = 0;
  late DateTime _lastInteraction;

  /// Kitten's current mood.
  KittenMood get mood => _mood;

  /// Rapport with the user, 0-100, which grows with every exchange.
  int get affinity => _affinity;

  /// When the user last said something to Kitten.
  DateTime get lastInteraction => _lastInteraction;

  /// Whether Kitten has dozed off after being left alone.
  bool get isDozing => _mood == KittenMood.sleepy;

  /// The system prompt for the current mood.
  String buildSystemPrompt() =>
      KittenSystemPrompt.build(moodDescription: _mood.promptFragment);

  /// Reacts to something the user said.
  void onUserMessage(String text) {
    _lastInteraction = _clock();
    _affinity = (_affinity + 2).clamp(0, 100);

    final normalized = text.toLowerCase();
    final words = normalized
        .split(RegExp(r'[^a-z]+'))
        .where((word) => word.isNotEmpty)
        .toSet();

    if (words.any(_affectionateWords.contains)) {
      _setMood(KittenMood.affectionate);
    } else if (words.any(_playfulWords.contains) || normalized.contains('!')) {
      _setMood(KittenMood.playful);
    } else if (normalized.contains('?')) {
      _setMood(KittenMood.curious);
    } else {
      _setMood(KittenMood.content);
    }
  }

  /// Reacts to Kitten's own reply, which also means any mishap is behind us.
  void onAssistantMessage(String text) {
    _lastInteraction = _clock();

    if (_mood == KittenMood.concerned) {
      _setMood(KittenMood.content);
    }
  }

  /// Reacts to a failed turn.
  void onFailure() {
    _lastInteraction = _clock();
    _setMood(KittenMood.concerned);
  }

  /// Ages the mood. Call periodically so Kitten can doze off when left alone.
  void tick({DateTime? now}) {
    final moment = now ?? _clock();
    if (moment.difference(_lastInteraction) >= _sleepAfter) {
      _setMood(KittenMood.sleepy);
    }
  }

  void _setMood(KittenMood mood) {
    if (_mood == mood) return;
    _mood = mood;
    notifyListeners();
  }
}

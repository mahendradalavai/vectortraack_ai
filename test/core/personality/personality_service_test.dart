import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/ai/prompts/kitten_system_prompt.dart';
import 'package:kitten/core/personality/models/kitten_mood.dart';
import 'package:kitten/core/personality/services/personality_service.dart';

void main() {
  late DateTime now;
  late PersonalityService personality;

  setUp(() {
    now = DateTime(2026, 9, 20, 12);
    personality = PersonalityService(
      clock: () => now,
      sleepAfter: const Duration(seconds: 90),
    );
  });

  tearDown(() => personality.dispose());

  group('PersonalityService mood rules', () {
    test('starts curious with no rapport', () {
      expect(personality.mood, KittenMood.curious);
      expect(personality.affinity, 0);
      expect(personality.isDozing, isFalse);
    });

    test('an affectionate word warms Kitten up', () {
      personality.onUserMessage('thank you, you are so cute');

      expect(personality.mood, KittenMood.affectionate);
    });

    test('playful words or an exclamation lift the mood', () {
      personality.onUserMessage('tell me a joke');
      expect(personality.mood, KittenMood.playful);

      personality.onUserMessage('that is amazing!');
      expect(personality.mood, KittenMood.playful);
    });

    test('a question makes Kitten curious', () {
      personality.onUserMessage('what time is it?');

      expect(personality.mood, KittenMood.curious);
    });

    test('a plain statement settles Kitten down', () {
      personality.onUserMessage('the sky is grey today');

      expect(personality.mood, KittenMood.content);
    });

    test('a failure makes Kitten concerned and the next reply recovers it', () {
      personality.onFailure();
      expect(personality.mood, KittenMood.concerned);

      personality.onAssistantMessage('Sorry about that!');
      expect(personality.mood, KittenMood.content);
    });

    test('rapport grows with each exchange and stops at 100', () {
      for (var i = 0; i < 60; i++) {
        personality.onUserMessage('hello');
      }

      expect(personality.affinity, 100);
    });
  });

  group('PersonalityService idling', () {
    test('dozes off after a long quiet spell', () {
      now = now.add(const Duration(minutes: 3));

      personality.tick(now: now);

      expect(personality.mood, KittenMood.sleepy);
      expect(personality.isDozing, isTrue);
    });

    test('does not doze off before the threshold', () {
      now = now.add(const Duration(seconds: 30));

      personality.tick(now: now);

      expect(personality.mood, KittenMood.curious);
    });

    test('wakes up as soon as the user speaks again', () {
      now = now.add(const Duration(minutes: 3));
      personality.tick(now: now);
      expect(personality.mood, KittenMood.sleepy);

      personality.onUserMessage('are you awake?');

      expect(personality.mood, KittenMood.curious);
      expect(personality.isDozing, isFalse);
    });
  });

  group('PersonalityService prompt and notifications', () {
    test('the system prompt keeps the base prompt and adds the mood', () {
      final prompt = personality.buildSystemPrompt();

      expect(prompt, contains(KittenSystemPrompt.prompt));
      expect(prompt, contains('CURRENT MOOD:'));
      // The scope constraints must not be displaced by the mood section.
      expect(prompt.indexOf('CRITICAL SCOPE CONSTRAINTS'),
          lessThan(prompt.indexOf('CURRENT MOOD:')));
    });

    test('a playful mood appears in the prompt', () {
      personality.onUserMessage('let us play a game');

      expect(personality.buildSystemPrompt(), contains('playful'));
    });

    test('notifies listeners only when the mood actually changes', () {
      var notifications = 0;
      personality.addListener(() => notifications++);

      personality.onUserMessage('hello there');
      expect(personality.mood, KittenMood.content);
      expect(notifications, 1);

      // Same resulting mood: no further notification.
      personality.onUserMessage('still just talking');
      expect(notifications, 1);

      personality.onUserMessage('tell me a joke');
      expect(notifications, 2);
    });
  });
}

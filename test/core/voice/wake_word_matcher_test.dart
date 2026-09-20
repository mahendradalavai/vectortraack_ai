import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/voice/util/wake_word_matcher.dart';

void main() {
  group('matchWakeWord', () {
    test('matches the bare wake phrase with no remainder', () {
      final match = matchWakeWord('hey kitten');

      expect(match.matched, isTrue);
      expect(match.remainder, isEmpty);
    });

    test('tolerates casing and punctuation', () {
      expect(matchWakeWord('Hey Kitten!').matched, isTrue);
      expect(matchWakeWord('HEY, KITTEN?').matched, isTrue);
      expect(matchWakeWord('  hey   kitten  ').matched, isTrue);
    });

    test('returns the question spoken after the wake phrase', () {
      final match = matchWakeWord('Hey Kitten, what is the weather?');

      expect(match.matched, isTrue);
      expect(match.remainder, 'what is the weather');
    });

    test('extracts the remainder from the middle of a sentence', () {
      final match = matchWakeWord('so hey kitten please tell me a joke');

      expect(match.matched, isTrue);
      expect(match.remainder, 'please tell me a joke');
    });

    test('accepts the alternative phrasing', () {
      final match = matchWakeWord('hi kitten sing me a song');

      expect(match.matched, isTrue);
      expect(match.remainder, 'sing me a song');
    });

    test('does not match unrelated speech', () {
      expect(matchWakeWord('what is the weather today').matched, isFalse);
      expect(matchWakeWord('kitchen').matched, isFalse);
      expect(matchWakeWord('kitten').matched, isFalse);
      expect(matchWakeWord('hey').matched, isFalse);
    });

    test('does not match empty or punctuation-only input', () {
      expect(matchWakeWord('').matched, isFalse);
      expect(matchWakeWord('   ').matched, isFalse);
      expect(matchWakeWord('!!!').matched, isFalse);
    });

    test('uses the earliest phrase when several are present', () {
      final match = matchWakeWord('hi kitten and also hey kitten stop');

      expect(match.matched, isTrue);
      expect(match.remainder, 'and also hey kitten stop');
    });

    test('honours a custom phrase list', () {
      final match = matchWakeWord(
        'okay buddy turn on the lights',
        phrases: ['okay buddy'],
      );

      expect(match.matched, isTrue);
      expect(match.remainder, 'turn on the lights');
      // The default phrase must not match when it was not supplied.
      expect(matchWakeWord('hey kitten', phrases: ['okay buddy']).matched, isFalse);
    });
  });

  group('normalizeTranscript', () {
    test('lower-cases, strips punctuation, and collapses spacing', () {
      expect(
        normalizeTranscript('  Hey,   Kitten!! it\'s 10:30 '),
        'hey kitten its 1030',
      );
    });
  });
}

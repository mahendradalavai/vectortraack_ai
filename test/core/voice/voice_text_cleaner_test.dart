import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/voice/util/voice_text_cleaner.dart';

void main() {
  group('cleanTextForSpeech', () {
    test('leaves plain prose untouched', () {
      expect(
        cleanTextForSpeech('Hello there, how are you today?'),
        'Hello there, how are you today?',
      );
    });

    test('removes asterisk stage directions', () {
      expect(
        cleanTextForSpeech('Hello! *purrs* I am Kitten.'),
        'Hello! I am Kitten.',
      );
    });

    test('removes parenthesised stage directions', () {
      expect(
        cleanTextForSpeech('Sure thing (tail flick) let me help.'),
        'Sure thing let me help.',
      );
    });

    test('strips emoji so they are not read as character names', () {
      expect(
        cleanTextForSpeech('Good morning ☀️ 🐱 let us begin!'),
        'Good morning let us begin!',
      );
    });

    test('collapses the whitespace left behind and tidies spacing', () {
      expect(
        cleanTextForSpeech('Well  then ,  *purrs*  ready?'),
        'Well then, ready?',
      );
    });

    test('returns an empty string when nothing is left to say', () {
      expect(cleanTextForSpeech('*purrs* 🐱'), '');
    });

    test('trims surrounding whitespace', () {
      expect(cleanTextForSpeech('   hello   '), 'hello');
    });
  });
}

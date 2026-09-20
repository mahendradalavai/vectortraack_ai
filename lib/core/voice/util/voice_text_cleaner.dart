/// Turns Kitten's written reply into clean text for text-to-speech.
///
/// The personality prompt encourages playful stage directions such as
/// `*purrs*` and decorative emoji. Reading those aloud sounds broken, so they
/// are stripped before synthesis while the on-screen message is untouched.
String cleanTextForSpeech(String input) {
  var output = input;

  // Remove parenthesised and asterisk stage directions, e.g. "*purrs*".
  output = output.replaceAll(RegExp(r'\*[^*]*\*'), ' ');
  output = output.replaceAll(RegExp(r'\([^()]*\)'), ' ');

  // Drop emoji and pictographs that would be read as character names.
  output = output.replaceAll(_emojiPattern, ' ');

  // Collapse the whitespace left behind and tidy spacing before punctuation.
  // Note: replaceAll does not expand group references, so use a mapped form.
  output = output.replaceAll(RegExp(r'\s+'), ' ').trim();
  output = output.replaceAllMapped(
    RegExp(r'\s+([,.!?;:])'),
    (match) => match.group(1)!,
  );

  return output;
}

final RegExp _emojiPattern = RegExp(
  '['
  '\u{1F300}-\u{1FAFF}' // symbols, pictographs, extended pictographs
  '\u{2600}-\u{27BF}' // misc symbols and dingbats
  '\u{2B00}-\u{2BFF}' // additional arrows and symbols
  '\u{FE0F}' // variation selector
  '\u{200D}' // zero-width joiner
  ']',
  unicode: true,
);

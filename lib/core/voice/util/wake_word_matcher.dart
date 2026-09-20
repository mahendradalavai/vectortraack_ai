import 'package:kitten/core/voice/config/voice_config.dart';

/// The outcome of scanning a transcript for Kitten's wake phrase.
class WakeWordMatch {
  const WakeWordMatch({required this.matched, this.remainder = ''});

  /// Whether a wake phrase was heard.
  final bool matched;

  /// Everything spoken after the wake phrase, usable directly as the first
  /// question (e.g. "hey kitten what's the weather" -> "whats the weather").
  final String remainder;
}

/// Scans [transcript] for one of [phrases].
///
/// Matching is tolerant of casing, punctuation, and extra spacing, because
/// speech recognition rarely returns the phrase cleanly. The remainder is
/// normalised so it can be sent straight to the AI as a question.
WakeWordMatch matchWakeWord(
  String transcript, {
  List<String> phrases = VoiceConfig.wakePhrases,
}) {
  final normalized = normalizeTranscript(transcript);
  if (normalized.isEmpty) return const WakeWordMatch(matched: false);

  var bestIndex = -1;
  var bestLength = 0;

  for (final phrase in phrases) {
    final target = normalizeTranscript(phrase);
    if (target.isEmpty) continue;

    final index = normalized.indexOf(target);
    if (index == -1) continue;

    // Prefer the earliest mention so the remainder starts at the right place.
    if (bestIndex == -1 || index < bestIndex) {
      bestIndex = index;
      bestLength = target.length;
    }
  }

  if (bestIndex == -1) return const WakeWordMatch(matched: false);

  return WakeWordMatch(
    matched: true,
    remainder: normalized.substring(bestIndex + bestLength).trim(),
  );
}

/// Lower-cases and strips punctuation so transcripts compare predictably.
String normalizeTranscript(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

import 'package:kitten/core/awareness/models/foreground_app.dart';

/// An app the floating Kitten talked about and then handed to the chat.
///
/// The native overlay owns this: it is what watched the app open and what drew
/// the line, so it supplies the wording too. The conversation therefore opens
/// with exactly the line the user already read in the bubble instead of a
/// second, differently phrased version of it.
class OverlayAppContext {
  const OverlayAppContext({required this.packageName, this.label, this.line});

  /// Android package id of the app the user had open, e.g. `com.instagram.android`.
  final String packageName;

  /// The app's human-readable name, when Android lets us see that package.
  final String? label;

  /// The line Kitten showed in its bubble, when the platform sent one.
  final String? line;

  /// The best name to show, reusing the app-awareness naming rules so a
  /// withheld label still becomes something readable.
  String get displayName =>
      ForegroundApp(packageName: packageName, label: label).displayName;

  /// Kitten's opening line for this app.
  ///
  /// Only a fallback: normally the platform's own line is used, so the bubble
  /// and the conversation stay in the same words.
  String get openingLine {
    final provided = line?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    return '$displayName? What are we doing here?';
  }

  /// Reads a handed-over context from the platform payload, or null when the
  /// payload is missing a usable package name.
  static OverlayAppContext? fromChannel(Object? arguments) {
    if (arguments is! Map) return null;

    final packageName = arguments['packageName'];
    if (packageName is! String || packageName.trim().isEmpty) return null;

    final label = arguments['label'];
    final line = arguments['line'];
    return OverlayAppContext(
      packageName: packageName,
      label: label is String && label.trim().isNotEmpty ? label : null,
      line: line is String && line.trim().isNotEmpty ? line : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OverlayAppContext &&
      other.packageName == packageName &&
      other.label == label &&
      other.line == line;

  @override
  int get hashCode => Object.hash(packageName, label, line);

  @override
  String toString() =>
      'OverlayAppContext($packageName, label: $label, line: $line)';
}

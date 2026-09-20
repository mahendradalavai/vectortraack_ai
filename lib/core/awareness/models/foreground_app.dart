/// The app the user currently has in the foreground.
///
/// [label] is only available when Android lets us see that package, so a
/// human-readable [displayName] is derived from the package name when the
/// label is missing.
class ForegroundApp {
  const ForegroundApp({required this.packageName, this.label});

  /// Android package id, e.g. `com.android.chrome`.
  final String packageName;

  /// The app's human-readable name, when the package is visible to us.
  final String? label;

  /// The best name we can show, preferring the real label.
  String get displayName {
    final provided = label?.trim();
    if (provided != null && provided.isNotEmpty) return provided;

    final segments =
        packageName.split('.').where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) return packageName;

    // Trailing segments such as `android`, `app`, or `apps` say nothing about
    // the app, so step back to the first meaningful one.
    const unhelpful = <String>{
      'android', 'app', 'apps', 'mobile', 'client', 'main', 'release',
    };

    for (var i = segments.length - 1; i >= 0; i--) {
      final segment = segments[i];
      if (segment.length > 2 && !unhelpful.contains(segment.toLowerCase())) {
        return _capitalise(segment);
      }
    }

    return packageName;
  }

  static String _capitalise(String value) =>
      value[0].toUpperCase() + value.substring(1);

  @override
  bool operator ==(Object other) =>
      other is ForegroundApp &&
      other.packageName == packageName &&
      other.label == label;

  @override
  int get hashCode => Object.hash(packageName, label);

  @override
  String toString() => 'ForegroundApp($packageName, label: $label)';
}

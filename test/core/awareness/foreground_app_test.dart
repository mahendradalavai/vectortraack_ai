import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/awareness/models/foreground_app.dart';

void main() {
  group('ForegroundApp', () {
    test('prefers the real label when Android provides one', () {
      const app = ForegroundApp(
        packageName: 'com.android.chrome',
        label: 'Chrome',
      );
      expect(app.displayName, 'Chrome');
    });

    test('falls back to a readable name derived from the package id', () {
      expect(
        const ForegroundApp(packageName: 'com.android.chrome').displayName,
        'Chrome',
      );
      expect(
        const ForegroundApp(packageName: 'com.spotify.music').displayName,
        'Music',
      );
    });

    test('skips meaningless trailing segments such as apps/android', () {
      expect(
        const ForegroundApp(
          packageName: 'com.google.android.apps.maps',
        ).displayName,
        'Maps',
      );
      expect(
        const ForegroundApp(packageName: 'com.android.settings').displayName,
        'Settings',
      );
    });

    test('ignores a blank label rather than showing nothing', () {
      expect(
        const ForegroundApp(
          packageName: 'com.android.chrome',
          label: '   ',
        ).displayName,
        'Chrome',
      );
    });

    test('returns the raw package when nothing readable can be derived', () {
      expect(const ForegroundApp(packageName: 'a.b').displayName, 'a.b');
    });

    test('equality follows package and label', () {
      const a = ForegroundApp(packageName: 'com.android.chrome', label: 'C');
      const b = ForegroundApp(packageName: 'com.android.chrome', label: 'C');
      const c = ForegroundApp(packageName: 'com.android.chrome', label: 'D');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}

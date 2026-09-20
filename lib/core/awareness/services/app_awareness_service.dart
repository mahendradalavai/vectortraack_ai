import 'package:kitten/core/awareness/models/foreground_app.dart';

/// Contract for knowing which app the user is currently using.
///
/// Kept abstract so the polling and permission logic can be tested without
/// Android, and so a different platform could be supported later.
abstract class AppAwarenessService {
  /// Whether this platform can report the foreground app at all.
  bool get isSupported;

  /// Whether the user has granted usage access.
  ///
  /// This is a special permission that cannot be granted by a normal dialog;
  /// the user must enable it from system settings.
  Future<bool> hasUsageAccess();

  /// Opens the system screen where usage access is granted.
  Future<void> openUsageAccessSettings();

  /// The most recently foregrounded app, or null when unknown, when access has
  /// not been granted, or when Kitten itself is in front.
  Future<ForegroundApp?> foregroundApp();

  /// Releases platform resources.
  void dispose();
}

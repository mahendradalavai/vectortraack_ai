import 'package:kitten/core/overlay/models/overlay_app_context.dart';

/// Platform abstraction for Kitten's floating overlay.
abstract interface class FloatingOverlayService {
  bool get isSupported;

  Future<bool> hasOverlayPermission();

  Future<bool> openOverlaySettings();

  Future<bool> startFloatingKitten();

  Future<bool> stopFloatingKitten();

  Future<bool> isFloatingKittenRunning();

  /// Registers the receiver for apps handed over while Kitten is already
  /// running, or clears it when [handler] is null.
  ///
  /// A hand-off is pushed because the overlay knows about it immediately:
  /// bringing Kitten forward from another app resumes the activity, and the
  /// pushed app arrives before any lifecycle callback would.
  void handleAppOpenings(void Function(OverlayAppContext context)? handler);

  /// Takes the app the overlay handed over before anyone was listening.
  ///
  /// Tapping the cat usually cold-starts Kitten, so the native side stashes the
  /// hand-off and the Dart side collects it once it is ready. Taking it clears
  /// it, so it is never used twice.
  Future<OverlayAppContext?> takePendingAppContext();

  /// Marks a pushed hand-off as handled.
  ///
  /// Pushed and stashed are the same hand-off, so without this a warm start
  /// would seed the conversation twice: once from the push and once from the
  /// take on the next resume.
  Future<void> acknowledgeAppContext();
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:kitten/core/overlay/models/overlay_app_context.dart';

import 'floating_overlay_service.dart';
import 'method_channel_floating_overlay_service.dart';

/// Owns overlay permission and running state without exposing platform calls to UI.
class FloatingOverlayController extends ChangeNotifier {
  FloatingOverlayController({FloatingOverlayService? service})
    : _service = service ?? MethodChannelFloatingOverlayService() {
    _service.handleAppOpenings(_onAppOpening);
  }

  final FloatingOverlayService _service;
  final StreamController<OverlayAppContext> _appOpenings =
      StreamController<OverlayAppContext>.broadcast();

  bool get isSupported => _service.isSupported;
  bool hasPermission = false;
  bool isRunning = false;
  String? lastError;

  /// Apps the floating Kitten handed over while Kitten was already running.
  ///
  /// The overlay says something like "Instagram? What are we doing here?" and
  /// the tap that follows opens Kitten with the same app, so the reply can
  /// start the conversation in context.
  Stream<OverlayAppContext> get appOpenings => _appOpenings.stream;

  Future<void> refresh() async {
    if (!isSupported) {
      hasPermission = false;
      isRunning = false;
      notifyListeners();
      return;
    }

    hasPermission = await _service.hasOverlayPermission();
    isRunning = await _service.isFloatingKittenRunning();
    notifyListeners();
  }

  Future<bool> openOverlaySettings() async {
    final opened = await _service.openOverlaySettings();
    if (!opened) {
      lastError = 'Android overlay settings could not be opened.';
      notifyListeners();
    }
    return opened;
  }

  Future<bool> start() async {
    lastError = null;
    hasPermission = await _service.hasOverlayPermission();
    if (!hasPermission) {
      lastError = 'Grant Display over other apps permission first.';
      notifyListeners();
      return false;
    }

    final started = await _service.startFloatingKitten();
    if (started) {
      isRunning = await _waitForRunning(true);
    } else {
      lastError = 'Floating Kitten could not be started.';
      isRunning = false;
    }
    notifyListeners();
    return started && isRunning;
  }

  Future<bool> stop() async {
    lastError = null;
    final stopped = await _service.stopFloatingKitten();
    isRunning = await _waitForRunning(false);
    if (!stopped || isRunning) {
      lastError = 'Floating Kitten could not be stopped.';
    }
    notifyListeners();
    return stopped && !isRunning;
  }

  /// Takes a hand-off that arrived before the conversation could listen, and
  /// tells the platform it has been accounted for.
  Future<OverlayAppContext?> takePendingAppContext() async {
    final context = await _service.takePendingAppContext();
    if (context != null) {
      unawaited(_service.acknowledgeAppContext());
    }
    return context;
  }

  void _onAppOpening(OverlayAppContext context) {
    _appOpenings.add(context);
    // The push and the stash are the same hand-off, so the stash goes too.
    unawaited(_service.acknowledgeAppContext());
  }

  Future<bool> _waitForRunning(bool expected) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final running = await _service.isFloatingKittenRunning();
      if (running == expected) return running;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _service.isFloatingKittenRunning();
  }

  @override
  void dispose() {
    _service.handleAppOpenings(null);
    _appOpenings.close();
    super.dispose();
  }
}

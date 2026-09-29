import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'background_assistant_service.dart';
import 'method_channel_background_assistant_service.dart';

/// Owns the opt-in background listener and forwards recognized commands.
class BackgroundAssistantController extends ChangeNotifier {
  BackgroundAssistantController({BackgroundAssistantService? service})
    : _service = service ?? MethodChannelBackgroundAssistantService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  static const channelName = 'kitten/background_assistant';
  final BackgroundAssistantService _service;
  final MethodChannel _channel = const MethodChannel(channelName);
  final StreamController<String> _commands = StreamController.broadcast();

  bool get isSupported => _service.isSupported;
  bool enabled = false;
  String? lastError;
  Stream<String> get commands => _commands.stream;

  Future<void> refresh() async {
    enabled = await _service.isEnabled();
    notifyListeners();
  }

  Future<bool> setEnabled(bool value) async {
    lastError = null;
    final changed = value ? await _service.start() : await _service.stop();
    enabled = changed ? value : await _service.isEnabled();
    if (!changed) {
      lastError = value
          ? 'Background listening could not be started.'
          : 'Background listening could not be stopped.';
    }
    notifyListeners();
    return changed;
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'assistantCommand' && call.arguments is String) {
      _commands.add(call.arguments as String);
    }
    return null;
  }

  @override
  void dispose() {
    _commands.close();
    super.dispose();
  }
}

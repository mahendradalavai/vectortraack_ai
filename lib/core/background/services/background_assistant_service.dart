/// Platform boundary for Kitten's opt-in background voice assistant.
abstract interface class BackgroundAssistantService {
  bool get isSupported;
  Future<bool> isEnabled();
  Future<bool> start();
  Future<bool> stop();
}

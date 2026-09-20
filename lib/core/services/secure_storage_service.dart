import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service responsible for managing encrypted storage for sensitive secrets,
/// specifically API keys and configuration values.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  final FlutterSecureStorage _storage;

  static const String _keyGroqApiKey = 'groq_api_key';
  static const String _keySelectedModel = 'ai_selected_model';
  static const String _keyWakeWordEnabled = 'voice_wake_word_enabled';
  static const String _keySpeakReplies = 'voice_speak_replies';
  static const String _keyAppAwarenessEnabled = 'awareness_app_enabled';

  /// Saves the Groq API key securely in encrypted storage.
  Future<void> saveGroqApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteGroqApiKey();
    } else {
      await _storage.write(key: _keyGroqApiKey, value: trimmed);
    }
  }

  /// Retrieves the stored Groq API key, or null if not set.
  Future<String?> getGroqApiKey() async {
    return _storage.read(key: _keyGroqApiKey);
  }

  /// Deletes the stored Groq API key.
  Future<void> deleteGroqApiKey() async {
    await _storage.delete(key: _keyGroqApiKey);
  }

  /// Checks if a Groq API key is currently stored.
  Future<bool> hasGroqApiKey() async {
    final key = await getGroqApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Saves the user-selected AI model name.
  Future<void> saveSelectedModel(String modelName) async {
    await _storage.write(key: _keySelectedModel, value: modelName.trim());
  }

  /// Retrieves the user-selected AI model name, or null if using default.
  Future<String?> getSelectedModel() async {
    return _storage.read(key: _keySelectedModel);
  }

  /// Stores whether Kitten should watch for its wake phrase.
  ///
  /// Non-secret preferences live here too, so the app needs only one storage
  /// dependency; the value is simply encrypted alongside the API key.
  Future<void> saveWakeWordEnabled(bool enabled) async {
    await _storage.write(
      key: _keyWakeWordEnabled,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Reads the stored wake-word preference, or null when never set.
  Future<bool?> getWakeWordEnabled() async {
    return _parseStoredBool(await _storage.read(key: _keyWakeWordEnabled));
  }

  /// Stores whether Kitten should read its replies aloud.
  Future<void> saveSpeakReplies(bool enabled) async {
    await _storage.write(
      key: _keySpeakReplies,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Reads the stored spoken-replies preference, or null when never set.
  Future<bool?> getSpeakReplies() async {
    return _parseStoredBool(await _storage.read(key: _keySpeakReplies));
  }

  /// Stores whether Kitten should notice which app the user is using.
  Future<void> saveAppAwarenessEnabled(bool enabled) async {
    await _storage.write(
      key: _keyAppAwarenessEnabled,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Reads the stored app-awareness preference, or null when never set.
  Future<bool?> getAppAwarenessEnabled() async {
    return _parseStoredBool(await _storage.read(key: _keyAppAwarenessEnabled));
  }

  static bool? _parseStoredBool(String? value) {
    if (value == null) return null;
    return value == 'true';
  }

  /// Returns a secure masked representation of an API key.
  ///
  /// Examples:
  /// - `gsk_1234567890abcdef` -> `****************cdef`
  /// - Empty or null -> `Not configured`
  /// - Very short keys -> `****`
  static String maskApiKey(String? key) {
    if (key == null || key.trim().isEmpty) {
      return 'Not configured';
    }
    final trimmed = key.trim();
    if (trimmed.length <= 4) {
      return '****';
    }
    final visibleSuffix = trimmed.substring(trimmed.length - 4);
    return '****************$visibleSuffix';
  }
}

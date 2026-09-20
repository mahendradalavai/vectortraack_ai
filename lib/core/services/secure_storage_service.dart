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

import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/services/secure_storage_service.dart';

class FakeSecureStorageService extends SecureStorageService {
  FakeSecureStorageService({this.initialKey, this.initialModel});

  String? initialKey;
  String? initialModel;

  @override
  Future<String?> getGroqApiKey() async => initialKey;

  @override
  Future<void> saveGroqApiKey(String apiKey) async {
    initialKey = apiKey.trim().isEmpty ? null : apiKey.trim();
  }

  @override
  Future<void> deleteGroqApiKey() async {
    initialKey = null;
  }

  @override
  Future<bool> hasGroqApiKey() async =>
      initialKey != null && initialKey!.isNotEmpty;

  @override
  Future<String?> getSelectedModel() async => initialModel;

  @override
  Future<void> saveSelectedModel(String modelName) async {
    initialModel = modelName.trim();
  }
}

void main() {
  group('SecureStorageService & Masking', () {
    test('maskApiKey handles null and empty keys safely', () {
      expect(SecureStorageService.maskApiKey(null), 'Not configured');
      expect(SecureStorageService.maskApiKey(''), 'Not configured');
      expect(SecureStorageService.maskApiKey('   '), 'Not configured');
    });

    test('maskApiKey masks short keys completely', () {
      expect(SecureStorageService.maskApiKey('abc'), '****');
      expect(SecureStorageService.maskApiKey('1234'), '****');
    });

    test('maskApiKey reveals only the last 4 characters preceded by 16 asterisks', () {
      const dummyTestKey = 'test_key_sample_1234567890abcd';
      final masked = SecureStorageService.maskApiKey(dummyTestKey);
      expect(masked, '****************abcd');
      expect(masked, isNot(contains('test_key_sample')));
      expect(masked.length, 20);
    });

    test('FakeSecureStorageService saves, reads, and deletes key', () async {
      final storage = FakeSecureStorageService();
      expect(await storage.hasGroqApiKey(), isFalse);
      expect(await storage.getGroqApiKey(), isNull);

      await storage.saveGroqApiKey('test_dummy_key');
      expect(await storage.hasGroqApiKey(), isTrue);
      expect(await storage.getGroqApiKey(), 'test_dummy_key');

      await storage.deleteGroqApiKey();
      expect(await storage.hasGroqApiKey(), isFalse);
      expect(await storage.getGroqApiKey(), isNull);
    });

    test('FakeSecureStorageService saves and retrieves model', () async {
      final storage = FakeSecureStorageService();
      expect(await storage.getSelectedModel(), isNull);

      await storage.saveSelectedModel('openai/gpt-oss-20b');
      expect(await storage.getSelectedModel(), 'openai/gpt-oss-20b');
    });
  });
}

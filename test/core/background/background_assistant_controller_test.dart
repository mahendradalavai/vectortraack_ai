import 'package:flutter_test/flutter_test.dart';

import 'package:kitten/core/background/services/background_assistant_controller.dart';
import 'package:kitten/core/background/services/background_assistant_service.dart';

class FakeBackgroundAssistantService implements BackgroundAssistantService {
  FakeBackgroundAssistantService({this.supported = true});

  final bool supported;
  bool enabled = false;
  bool shouldChange = true;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> start() async {
    if (shouldChange) enabled = true;
    return shouldChange;
  }

  @override
  Future<bool> stop() async {
    if (shouldChange) enabled = false;
    return shouldChange;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts disabled and refreshes native state', () async {
    final service = FakeBackgroundAssistantService();
    final controller = BackgroundAssistantController(service: service);

    expect(controller.enabled, isFalse);
    await controller.refresh();
    expect(controller.enabled, isFalse);

    controller.dispose();
  });

  test('starts and stops the opt-in listener', () async {
    final service = FakeBackgroundAssistantService();
    final controller = BackgroundAssistantController(service: service);

    expect(await controller.setEnabled(true), isTrue);
    expect(controller.enabled, isTrue);
    expect(await controller.setEnabled(false), isTrue);
    expect(controller.enabled, isFalse);

    controller.dispose();
  });

  test('reports platform failures without claiming enabled', () async {
    final service = FakeBackgroundAssistantService()..shouldChange = false;
    final controller = BackgroundAssistantController(service: service);

    expect(await controller.setEnabled(true), isFalse);
    expect(controller.enabled, isFalse);
    expect(controller.lastError, contains('started'));

    controller.dispose();
  });
}

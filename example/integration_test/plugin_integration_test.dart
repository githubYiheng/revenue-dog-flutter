// M1 占位集成测试：原生插件尚为桩（全部 notImplemented），M3 改造测试 app 时替换。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revenue_dog/revenue_dog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isConfigured reaches the native stub', (tester) async {
    await expectLater(
      Purchases.isConfigured,
      throwsA(isA<MissingPluginException>()),
    );
  });
}

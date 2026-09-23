// 设备上的最小冒烟：原生插件已注册，未配置时 isConfigured 回 false（不打后端、不需要 key）。
// 真机手测走 docs/audit/2026-09-24-flutter-device-checklist.md 的 F 系列，不在这里自动化。
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revenue_dog/revenue_dog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isConfigured reaches the native plugin', (tester) async {
    expect(await Purchases.isConfigured, isFalse);
  });
}

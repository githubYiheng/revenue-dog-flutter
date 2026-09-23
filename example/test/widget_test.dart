// 测试 app 冒烟：单页能渲染、核心按钮都在。宿主测试环境没有原生插件，状态刷新失败只进日志面板，不崩。
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog_example/main.dart';

void main() {
  testWidgets('renders tester page with core actions', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.text('RevenueDog Flutter 测试'), findsOneWidget);
    for (final label in ['configure', 'logIn', 'logOut', 'getCustomerInfo', 'getOfferings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}

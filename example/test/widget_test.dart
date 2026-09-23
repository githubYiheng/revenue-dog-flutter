import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenue_dog_example/main.dart';

void main() {
  testWidgets('renders status text', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data!.startsWith('Purchases:'),
      ),
      findsOneWidget,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:compress/main.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const CompressApp());
    await tester.pump();
    expect(find.byType(CompressApp), findsOneWidget);
  });
}

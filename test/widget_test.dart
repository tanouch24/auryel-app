import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/main.dart';

void main() {
  testWidgets('Home screen shows the Auryel wordmark', (WidgetTester tester) async {
    await tester.pumpWidget(const AuryelApp());
    await tester.pumpAndSettle();

    expect(find.text('AURYEL'), findsOneWidget);
    expect(find.text('Consulter'), findsOneWidget);
  });
}

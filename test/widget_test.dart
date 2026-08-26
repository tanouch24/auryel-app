import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/main.dart';

void main() {
  testWidgets('Splash shows the wordmark, then transitions to home', (WidgetTester tester) async {
    await tester.pumpWidget(const AuryelApp());
    expect(find.text('AURYEL'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();

    expect(find.text('Accueil'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/main.dart';
import 'package:auryel/state/auryel_state.dart';

void main() {
  testWidgets('Splash shows the wordmark, then routes a fresh user to onboarding', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AuryelState(repository: LocalOnboardingRepository());

    await tester.pumpWidget(AuryelApp(state: state));
    expect(find.text('AURYEL'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();

    // Onboarding jamais terminé → premier écran du parcours, pas l'accueil.
    expect(find.text('Choisis ton conseiller'), findsOneWidget);
  });
}

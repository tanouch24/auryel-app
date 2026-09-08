import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/tarot_fan.dart';

// ===========================================================================
// B8.1 §5/§12 — aucune RenderFlex overflow ni débordement latéral sur écran
// étroit (Galaxy A07 ~360 dp et en dessous).
// ===========================================================================

// Tailles exigées par B8.1 §5 (Galaxy A07 ~360 dp) — bornes basse et haute
// des téléphones courants.
const _widths = <double>[360, 375, 390, 430];

AuryelState _state() => AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u',
        selectedAdvisor: 'Séléna',
        firstName: 'N',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final w in _widths) {
    testWidgets('Accueil : aucun overflow à ${w.toInt()} px de large', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 900);
      addTearDown(t.view.reset);

      await t.pumpWidget(
        AuryelStateScope(
          state: _state(),
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await t.pump();
      await t.pump(const Duration(seconds: 1));

      expect(t.takeException(), isNull,
          reason: 'RenderFlex/overflow à ${w.toInt()} px');
    });

    testWidgets('TarotFan : aucun overflow à ${w.toInt()} px de large', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: w,
                height: 320,
                child: TarotFan(
                  count: 22,
                  selectionNumberFor: (i) => i == 0 || i == 21 ? 1 : null,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull,
          reason: 'TarotFan overflow à ${w.toInt()} px (cartes de bord '
              'inclinées / agrandies)');
    });
  }
}

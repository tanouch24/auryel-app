import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';

Widget _home() {
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u',
      selectedAdvisor: 'Maïa',
      firstName: 'Nina',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'portrait',
      portraitFeedback: 'feedback',
      onboardingCompleted: true,
    ),
  );
  return AuryelStateScope(
    state: state,
    child: MaterialApp(
      home: HomeScreen(
        thoughtRepository: DailyThoughtRepository(
          seed: [
            DailyThought(
              id: 1,
              publishDate: DateTime(2026, 9, 16),
              phrase: 'Phrase',
              interpretation: 'Interprétation',
              imageAsset: 'assets/images/daily_thought_default.png',
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Accueil affiche le Tirage du jour et son CTA Tarot', (t) async {
    await t.pumpWidget(_home());
    await t.pumpAndSettle();

    expect(find.byKey(const Key('home-daily-tirage-card')), findsOneWidget);
    expect(find.text('Tirage du jour'), findsOneWidget);
    expect(find.text('Tirer ma carte'), findsOneWidget);
    expect(find.text('Partage cette pensée avec tes proches'), findsOneWidget);
    expect(find.text('Mon programme Bien-être'), findsNothing);
    expect(find.text('Mes Étoiles'), findsNothing);
    expect(find.text('6 Étoiles'), findsNothing);
  });

  testWidgets('Le CTA du Tirage du jour ouvre le vrai parcours Tarot', (
    t,
  ) async {
    await t.pumpWidget(_home());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-daily-tirage-cta')));
    await t.pumpAndSettle();

    expect(find.byType(TirageScreen), findsOneWidget);
    expect(find.text('Ton tirage'), findsOneWidget);
  });
}

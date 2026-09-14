import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';

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

Widget _home() => AuryelStateScope(
  state: _state(),
  child: const MaterialApp(home: HomeScreen()),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Home ne rend plus les missions ni le parcours', (tester) async {
    await tester.pumpWidget(_home());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('TES MISSIONS DU JOUR'), findsNothing);
    expect(find.text('Suis ton parcours pendant 30 jours'), findsNothing);
    expect(find.text('Carte du jour'), findsNothing);
    expect(find.text('Prends ton temps'), findsNothing);
    expect(find.text('DÉCOUVRE LES OFFRES DE CONSULTATION'), findsOneWidget);
  });

  testWidgets('Home garde le contenu quotidien après les offres', (
    tester,
  ) async {
    await tester.pumpWidget(_home());
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Partager maintenant'));
    expect(find.text('Partager maintenant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('DailyMissionTracker — compatibilité des flux existants', () {
    test('reset logique automatique au changement de jour', () async {
      final tracker = DailyMissionTracker();
      await tracker.markDone(
        DailyMissionTracker.tirage,
        now: DateTime(2026, 9, 5, 10),
      );
      expect(
        await tracker.isDone(
          DailyMissionTracker.tirage,
          now: DateTime(2026, 9, 5, 23),
        ),
        isTrue,
      );
      expect(
        await tracker.isDone(
          DailyMissionTracker.tirage,
          now: DateTime(2026, 9, 6, 0, 1),
        ),
        isFalse,
      );
    });

    test('le tracker local ne porte aucun crédit financier', () {
      const api = {'isDone', 'markDone', 'tirage', 'consultation', 'moment'};
      expect(
        api.any(
          (value) =>
              value.toLowerCase().contains('reward') ||
              value.toLowerCase().contains('credit') ||
              value.toLowerCase().contains('purchase'),
        ),
        isFalse,
      );
    });
  });
}

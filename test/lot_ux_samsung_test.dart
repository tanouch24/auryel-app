import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/advisor_audio.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/advisor_selector_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/wellbeing_journey_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// CORRECTIF UX SAMSUNG — CTA Accueil « Suis ton parcours pendant 30 jours »,
// et fade de continuation sur le sélecteur de conseillers.
// ===========================================================================

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

DailyThoughtRepository _repo() => DailyThoughtRepository(
  seed: [
    DailyThought(
      id: 1,
      publishDate: DateTime(2026, 9, 4),
      phrase: 'Ce que tu n’oses pas regarder te dirige.',
      interpretation: 'x',
      imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
    ),
  ],
);

Widget _home() => AuryelStateScope(
  state: _state(),
  child: MaterialApp(
    home: MainNavScope(
      goToTab: (_) {},
      currentIndex: kTabHome,
      child: HomeScreen(thoughtRepository: _repo()),
    ),
  ),
);

class _FakeAudio implements AdvisorAudio {
  @override
  Future<void> play(
    String assetPath, {
    Duration fadeIn = Duration.zero,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Accueil — CTA parcours bien-être', () {
    testWidgets('le CTA « Suis ton parcours pendant 30 jours » est visible', (
      t,
    ) async {
      await t.pumpWidget(_home());
      await t.pumpAndSettle();
      expect(find.text('Suis ton parcours pendant 30 jours'), findsOneWidget);
    });

    testWidgets('le sous-texte annonce la récompense de 15 min à 30 jours', (
      t,
    ) async {
      await t.pumpWidget(_home());
      await t.pumpAndSettle();
      expect(
        find.text(
          'Avance chaque jour dans ton parcours bien-être et gagne 15 min '
          'de consultation offertes à la fin des 30 jours.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tap sur le CTA -> ouvre l\'écran parcours (carte)', (t) async {
      await t.pumpWidget(_home());
      await t.pumpAndSettle();
      final cta = find.text('Suis ton parcours pendant 30 jours');
      await t.ensureVisible(cta);
      await t.pumpAndSettle();
      await t.tap(cta);
      await t.pumpAndSettle();
      expect(find.byType(WellbeingJourneyScreen), findsOneWidget);
    });

    testWidgets('petit écran Samsung 360×640 : CTA présent, aucun overflow '
        'introduit par la carte CTA', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(_home());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Suis ton parcours pendant 30 jours'), findsOneWidget);
    });
  });

  group('Consultation — fade de continuation', () {
    Finder fade() => find.byKey(const Key('advisor-scroll-fade'));

    Widget host() => MaterialApp(
      home: AdvisorSelectorScreen(
        title: 'Avec qui veux-tu en parler ?',
        audioOverride: _FakeAudio(),
      ),
    );

    testWidgets(
      'fade + indice visibles au départ ; CORRECTIF UX FINAL — réapparaissent '
      'AUSSI sur la fiche suivante (chaque fiche a droit à son indice une '
      'fois), puis disparaissent pour une fiche déjà quittée',
      (t) async {
        await t.pumpWidget(host());
        await t.pumpAndSettle();

        expect(fade(), findsOneWidget);
        expect(find.text('Découvrir les autres conseillers'), findsOneWidget);

        // 1er défilement -> 2e fiche : PREMIÈRE apparition pour elle aussi,
        // fade + indice doivent s'afficher (pas uniquement sur Luna/1re carte).
        await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
        await t.pumpAndSettle();
        expect(fade(), findsOneWidget);
        expect(find.text('Découvrir les autres conseillers'), findsOneWidget);

        // On revient sur la 1re fiche, déjà quittée une fois : plus d'indice.
        await t.fling(find.byType(PageView), const Offset(0, 400), 1200);
        await t.pumpAndSettle();
        expect(fade(), findsNothing);
        expect(find.text('Découvrir les autres conseillers'), findsNothing);
      },
    );

    for (final size in const [
      Size(320, 480),
      Size(320, 520),
      Size(360, 640),
      Size(412, 915),
    ]) {
      testWidgets('aucun overflow (fade + indice) à ${size.width.toInt()}×'
          '${size.height.toInt()}', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(host());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(fade(), findsOneWidget);
      });
    }
  });
}

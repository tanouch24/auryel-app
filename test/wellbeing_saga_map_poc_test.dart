import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/dev/wellbeing_saga_map_poc.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/wellbeing_journey_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// POC CARTE AVENTURE (saga_map) — prototype visuel isolé, DEV UNIQUEMENT.
//
// Ces tests couvrent : l'accès dev (appui long, kDebugMode) qui n'altère PAS
// la navigation de production (tap normal), le rendu de la carte avec ses 7
// nœuds et leurs 3 états, les interactions (terminé/actuel/verrouillé), et
// l'absence d'overflow à 360x640 et 412x915.
//
// NOTE : l'écran POC porte des animations continues (halo de l'étape
// actuelle, avatar joueur) qui `repeat(reverse: true)` indéfiniment — donc
// `pumpAndSettle()` n'y termine jamais. On utilise à la place une poignée de
// `pump()` bornés dès que le POC est monté.
// ===========================================================================

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

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

Widget _poc() => const MaterialApp(home: WellbeingSagaMapPocScreen());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Accueil — accès dev au POC (ne casse pas la production)', () {
    testWidgets('tap normal sur le CTA -> écran de PRODUCTION (inchangé)', (
      t,
    ) async {
      await t.pumpWidget(_home());
      await t.pumpAndSettle();
      final cta = find.text('Suivre mon parcours bien-être');
      await t.ensureVisible(cta);
      await t.pumpAndSettle();
      await t.tap(cta);
      await t.pumpAndSettle();
      expect(find.byType(WellbeingJourneyScreen), findsOneWidget);
      expect(find.byType(WellbeingSagaMapPocScreen), findsNothing);
    });

    testWidgets(
      'appui long (debug) sur le CTA -> ouvre le POC saga_map',
      (t) async {
        await t.pumpWidget(_home());
        await t.pumpAndSettle();
        final cta = find.text('Suivre mon parcours bien-être');
        await t.ensureVisible(cta);
        await t.pumpAndSettle();
        await t.longPress(cta);
        await _settle(t);
        expect(find.byType(WellbeingSagaMapPocScreen), findsOneWidget);
      },
      skip: !kDebugMode,
    );
  });

  group('POC — rendu de la carte', () {
    testWidgets('affiche les 7 nœuds de progression', (t) async {
      await t.pumpWidget(_poc());
      await _settle(t);
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(Key('poc-node-$i')), findsOneWidget);
      }
    });

    testWidgets('affiche le bandeau de l’étape actuelle (Jour 4)', (
      t,
    ) async {
      await t.pumpWidget(_poc());
      await _settle(t);
      expect(find.textContaining('Jour 4'), findsWidgets);
      expect(find.text('Le passage'), findsWidgets);
    });

    testWidgets('la carte propose un viewer zoom/pan (InteractiveViewer)', (
      t,
    ) async {
      await t.pumpWidget(_poc());
      await _settle(t);
      expect(find.byKey(const Key('poc-map-viewer')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });

  group('POC — interactions par état', () {
    // Fenêtre haute : la carte (7 nœuds + décor) dépasse la hauteur d'un
    // écran de test par défaut (800x600). On agrandit la fenêtre plutôt que
    // de piloter le pan de l'InteractiveViewer, pour garder ces tests
    // concentrés sur l'interaction (tap -> bonne feuille/feedback), pas sur
    // le geste de défilement lui-même.
    Future<void> pumpTall(WidgetTester t) async {
      t.view.physicalSize = const Size(400, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(_poc());
      await _settle(t);
    }

    testWidgets('tap sur une étape TERMINÉE -> fiche info avec bouton Fermer', (
      t,
    ) async {
      await pumpTall(t);
      await t.tap(find.byKey(const Key('poc-node-0')));
      await _settle(t);
      expect(find.text('Première lumière'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets(
      'tap sur l’étape ACTUELLE -> CTA « Continuer mon parcours »',
      (t) async {
        await pumpTall(t);
        await t.tap(find.byKey(const Key('poc-node-3')));
        await _settle(t);
        expect(find.text('Continuer mon parcours'), findsOneWidget);
      },
    );

    testWidgets(
      'tap sur une étape VERROUILLÉE -> feedback discret « Disponible prochainement »',
      (t) async {
        await pumpTall(t);
        await t.tap(find.byKey(const Key('poc-node-4')));
        await t.pump();
        expect(find.text('Disponible prochainement'), findsOneWidget);
        expect(find.byKey(const Key('poc-locked-snackbar')), findsOneWidget);
      },
    );
  });

  group('POC — petits écrans, aucun overflow', () {
    for (final size in const [Size(360, 640), Size(412, 915)]) {
      testWidgets(
        'aucun overflow à ${size.width.toInt()}×${size.height.toInt()}',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(_poc());
          await _settle(t);
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('poc-node-3')), findsOneWidget);
        },
      );
    }
  });
}

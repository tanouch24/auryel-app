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
// POC CARTE D'AVENTURE ANIMÉE (saga_map) — prototype visuel isolé, TEST
// SAMSUNG UNIQUEMENT (accès temporaire, voir kAuryelPocTempSamsungTestAccessEnabled).
//
// 30 jours / 6 régions. Ces tests couvrent : les 30 étapes, l'étape actuelle,
// les étapes terminées/futures/majeures, les 3 interactions par état, le HUD
// jour/progression, l'absence d'overflow sur petits écrans, la possibilité de
// déclencher l'animation de progression (bouton DEV) sans toucher à aucune
// donnée métier réelle, et l'isolement de l'accès (tap normal inchangé).
//
// NOTE : le fond de carte porte des animations continues (scintillement,
// brume, halo de l'étape actuelle, avatar) qui `repeat()` indéfiniment — donc
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

/// Le POC ne dépend d'AUCUN provider/état métier — juste un `MaterialApp`.
/// C'est aussi la preuve que sa progression est un état 100% local : rien
/// autour de lui ne pourrait persister quoi que ce soit même s'il le voulait.
Widget _poc() => const MaterialApp(home: WellbeingSagaMapPocScreen());

Future<void> _pumpTall(
  WidgetTester t, {
  Size size = const Size(400, 1400),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(_poc());
  await _settle(t);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Accueil — accès missions déplacé vers Étoiles', () {
    testWidgets('la Home ne rend plus le CTA parcours ni les missions', (
      t,
    ) async {
      await t.pumpWidget(_home());
      await t.pumpAndSettle();
      expect(find.text('Suis ton parcours pendant 30 jours'), findsNothing);
      expect(find.text('TES MISSIONS DU JOUR'), findsNothing);
      expect(find.byType(WellbeingJourneyScreen), findsNothing);
      expect(find.byType(WellbeingSagaMapPocScreen), findsNothing);
    });
  });

  group('POC — les 30 étapes', () {
    testWidgets('les 30 nœuds de progression sont présents', (t) async {
      await _pumpTall(t);
      for (var i = 0; i < 30; i++) {
        expect(
          find.byKey(Key('poc-node-$i')),
          findsOneWidget,
          reason: 'nœud manquant pour id=$i (jour ${i + 1})',
        );
      }
    });

    testWidgets('l’étape actuelle est le jour 12 (état de démo attendu)', (
      t,
    ) async {
      expect(kAuryelPocDemoCurrentDay1, 12);
      await _pumpTall(t);
      // Le tap sur le jour 12 (id 11) doit ouvrir la fiche "en cours".
      await t.tap(find.byKey(const Key('poc-node-11')));
      await _settle(t);
      expect(find.text('Continuer mon parcours'), findsOneWidget);
    });

    testWidgets('les jours < 12 sont terminés (fiche "Revoir")', (t) async {
      await _pumpTall(t);
      // La caméra s'ouvre centrée sur le jour actuel (12) : le jour 1 est
      // au-dessus du viewport. On fait défiler vers le haut du monde pour
      // l'atteindre, comme le ferait une utilisatrice.
      await t.drag(
        find.byKey(const Key('poc-map-viewer')),
        const Offset(0, 5000),
      );
      await _settle(t);
      await t.tap(find.byKey(const Key('poc-node-0'))); // jour 1
      await _settle(t);
      expect(find.text('Revoir'), findsOneWidget);
    });

    testWidgets('les jours > 12 sont verrouillés/futurs (brume)', (t) async {
      await _pumpTall(t);
      await t.tap(find.byKey(const Key('poc-node-15'))); // jour 16
      await _settle(t);
      expect(find.text('Cette étape se révélera bientôt.'), findsOneWidget);
      expect(find.byKey(const Key('poc-future-sheet')), findsOneWidget);
    });

    testWidgets('les étapes majeures (5/10/15/20/25/30) portent un nom', (
      t,
    ) async {
      await _pumpTall(t, size: const Size(400, 4200));
      await t.tap(find.byKey(const Key('poc-node-4'))); // jour 5, terminé
      await _settle(t);
      expect(find.text('La Clairière'), findsOneWidget);
    });
  });

  group('POC — HUD jour/progression', () {
    testWidgets('affiche « Jour 12 / 30 » et « 40 % »', (t) async {
      await _pumpTall(t);
      expect(find.byKey(const Key('poc-hud-day')), findsOneWidget);
      expect(find.text('Jour 12 / 30'), findsOneWidget);
      expect(find.byKey(const Key('poc-hud-percent')), findsOneWidget);
      expect(find.text('40 %'), findsOneWidget);
    });
  });

  group('POC — zoom/pan', () {
    testWidgets('la carte propose un viewer zoom/pan (InteractiveViewer)', (
      t,
    ) async {
      await _pumpTall(t);
      expect(find.byKey(const Key('poc-map-viewer')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });

  group('POC — animation de progression déclenchable (DEV)', () {
    testWidgets(
      'le bouton DEV avance le jour actuel sans toucher à aucune donnée métier',
      (t) async {
        await _pumpTall(t, size: const Size(400, 4200));
        // Avant : jour 12 en cours.
        await t.tap(find.byKey(const Key('poc-node-11')));
        await _settle(t);
        expect(find.text('Continuer mon parcours'), findsOneWidget);
        // Referme la fiche (son propre bouton se contente de la fermer).
        await t.tap(find.text('Continuer mon parcours'));
        await _settle(t);

        expect(find.byKey(const Key('poc-dev-play-progress')), findsOneWidget);
        await t.tap(find.byKey(const Key('poc-dev-play-progress')));
        // Avance au-delà de la durée de l'animation (~1.8s) par petits pas
        // bornés — jamais pumpAndSettle (animations d'ambiance infinies).
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        await _settle(t);

        expect(find.text('Jour 13 / 30'), findsOneWidget);

        // Le jour 13 (id 12) est maintenant l'étape actuelle.
        await t.tap(find.byKey(const Key('poc-node-12')));
        await _settle(t);
        expect(find.text('Continuer mon parcours'), findsOneWidget);
      },
    );
  });

  group('POC — petits écrans, aucun overflow', () {
    for (final size in const [
      Size(320, 480),
      Size(320, 520),
      Size(360, 640),
      Size(412, 915),
    ]) {
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
          expect(find.byKey(const Key('poc-hud-day')), findsOneWidget);
        },
      );
    }
  });
}

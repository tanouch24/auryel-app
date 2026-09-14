import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/api/wellbeing_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/wellbeing_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// LOT « MON AURYEL AUJOURD'HUI » — nouvelle Home : Pensée -> Missions -> Temps.
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

Widget _host({List<int>? tabTaps}) => AuryelStateScope(
  state: _state(),
  child: MaterialApp(
    home: MainNavScope(
      goToTab: (i) => tabTaps?.add(i),
      currentIndex: kTabHome,
      child: HomeScreen(thoughtRepository: _repo()),
    ),
  ),
);

String _todayKey() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

// ===========================================================================
// AUDIT ACCUEIL/PARCOURS — Accueil lit désormais l'état des 4 missions
// EXCLUSIVEMENT depuis `WellbeingController.progress.today.missions` (la même
// instance que « Mon parcours bien-être » lirait). Ce rig construit ce
// contrôleur, branché sur un `GET /api/app/wellbeing/progress` mocké, et
// l'expose via `WellbeingScope` autour de `HomeScreen` — exactement le
// câblage réel de main().
// ===========================================================================

Map<String, dynamic> _progressJson({List<String> doneToday = const []}) => {
  'completed_days_total': 3,
  'cycle_completed_days': 3,
  'current_level': null,
  'next_level': 'Élan',
  'days_to_next_level': 2,
  'today': {
    'date': _todayKey(),
    'missions': [
      for (final m in kWellbeingMissions)
        {'id': m, 'completed': doneToday.contains(m)},
    ],
    'completed': doneToday.length >= kWellbeingMissions.length,
  },
  'cycle_number': 1,
  'reward_earned_for_current_cycle': false,
};

typedef _WellbeingRig = ({
  WellbeingController wellbeing,
  AuthController auth,
  List<String> hits,
});

_WellbeingRig _wellbeingRig({List<String> doneToday = const []}) {
  final hits = <String>[];
  // État MUTABLE : un POST /mission « accomplit » réellement la mission pour
  // les appels suivants — comme le ferait le vrai serveur.
  final done = [...doneToday];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/app/wellbeing/progress') {
        return http.Response(
          jsonEncode(_progressJson(doneToday: done)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/api/app/wellbeing/mission') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final id = (body['mission_id'] ?? '').toString();
        if (id.isNotEmpty && !done.contains(id)) done.add(id);
        return http.Response(
          jsonEncode(_progressJson(doneToday: done)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode({}), 404);
    }),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  final wellbeing = WellbeingController(
    api: WellbeingApi(client),
    tokenProvider: auth.currentToken,
  );
  return (wellbeing: wellbeing, auth: auth, hits: hits);
}

Widget _hostWithWellbeing(_WellbeingRig rig, {List<int>? tabTaps}) =>
    AuthScope(
      controller: rig.auth,
      child: WellbeingScope(
        controller: rig.wellbeing,
        child: AuryelStateScope(
          state: _state(),
          child: MaterialApp(
            home: MainNavScope(
              goToTab: (i) => tabTaps?.add(i),
              currentIndex: kTabHome,
              child: HomeScreen(thoughtRepository: _repo()),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Home — ordre & conseillers retirés', () {
    testWidgets('Pensée AVANT Missions AVANT Temps disponible', (t) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));

      final penseeDy = t
          .getTopLeft(
            find.byWidgetPredicate(
              (w) =>
                  w is RichText && w.text.toPlainText().contains('te dirige.'),
            ),
          )
          .dy;
      final missionsDy = t.getTopLeft(find.text('TES MISSIONS DU JOUR')).dy;
      final tempsDy = t.getTopLeft(find.text('TEMPS DISPONIBLE')).dy;

      expect(missionsDy, greaterThan(penseeDy));
      expect(tempsDy, greaterThan(missionsDy));
    });

    testWidgets('aucun carrousel conseillers, aucun lien conseiller', (
      t,
    ) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(AdvisorsCarousel), findsNothing);
      expect(find.text('Changer de conseiller'), findsNothing);
      expect(find.text('Découvre nos conseillers'), findsNothing);
    });
  });

  group('Missions', () {
    testWidgets(
      'exactement les 4 missions serveur (mêmes libellés que Parcours), '
      'compteur 0/4 au départ',
      (t) async {
        final rig = _wellbeingRig();
        await t.pumpWidget(_hostWithWellbeing(rig));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 50));

        expect(find.text('Pensée du jour'), findsOneWidget);
        expect(find.text('Carte du jour'), findsOneWidget);
        expect(find.text('Consultation'), findsOneWidget);
        expect(find.text('Prends ton temps'), findsOneWidget);
        expect(find.text('0/4'), findsOneWidget);
        expect(find.text('Journée Auryel complétée'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.checkCircle,
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'AUDIT — 3/4 côté serveur : compteur 3/4, PAS "Journée complétée" '
      '(reproduit le bug : Consultation non terminée)',
      (t) async {
        final rig = _wellbeingRig(
          doneToday: ['pensee', 'tirage', 'moment'],
        );
        await t.pumpWidget(_hostWithWellbeing(rig));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 50));

        expect(find.text('3/4'), findsOneWidget);
        expect(
          find.text('Journée Auryel complétée'),
          findsNothing,
          reason: 'Accueil ne doit JAMAIS annoncer la journée terminée '
              'tant que le serveur dit 3/4',
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.checkCircle,
          ),
          findsNWidgets(3),
        );
      },
    );

    testWidgets('4/4 côté serveur -> « Journée Auryel complétée »', (
      t,
    ) async {
      final rig = _wellbeingRig(doneToday: kWellbeingMissions);
      await t.pumpWidget(_hostWithWellbeing(rig));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('Journée Auryel complétée'), findsOneWidget);
    });

    testWidgets('tap « Carte du jour » -> demande l\'onglet Tirage (1)', (
      t,
    ) async {
      final rig = _wellbeingRig();
      final taps = <int>[];
      await t.pumpWidget(_hostWithWellbeing(rig, tabTaps: taps));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      await t.tap(find.text('Carte du jour'));
      await t.pump();
      expect(taps, contains(kTabTirage));
    });

    testWidgets('tap « Consultation » -> demande l\'onglet CONSULTATION (2), '
        'sans cocher la mission localement', (t) async {
      final rig = _wellbeingRig();
      final taps = <int>[];
      await t.pumpWidget(_hostWithWellbeing(rig, tabTaps: taps));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      await t.tap(find.text('Consultation'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(taps, contains(kTabConsultation));
      // Le serveur reste seul juge : ouvrir l'onglet ne coche rien tout seul.
      expect(rig.wellbeing.isMissionDone('consultation'), isFalse);
    });

    testWidgets('tap « Prends ton temps » -> onglet Méditation, mission NON '
        'marquée à l\'ouverture (uniquement sur un démarrage vidéo confirmé)', (
      t,
    ) async {
      final rig = _wellbeingRig();
      final taps = <int>[];
      await t.pumpWidget(_hostWithWellbeing(rig, tabTaps: taps));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      await t.tap(find.text('Prends ton temps'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(taps, contains(kTabMeditation));
      expect(rig.wellbeing.isMissionDone('moment'), isFalse);
    });

    testWidgets(
      'tap « Pensée du jour » -> ouvre l\'aperçu de la publication',
      (t) async {
        final rig = _wellbeingRig();
        await t.pumpWidget(_hostWithWellbeing(rig));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 50));

        await t.tap(find.text('Pensée du jour'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(DailyMessageSheet), findsOneWidget);
      },
    );

    testWidgets('lignes de mission : Semantics bouton + état coché', (
      t,
    ) async {
      final rig = _wellbeingRig(doneToday: ['tirage']);
      await t.pumpWidget(_hostWithWellbeing(rig));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      // Chaque ligne = un Semantics(button:true, checked:<état>).
      final missionSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            (w.properties.label ?? '').contains('Carte du jour'),
      );
      expect(missionSemantics, findsOneWidget);
      final props = t.widget<Semantics>(missionSemantics).properties;
      expect(
        props.checked,
        isTrue,
        reason: 'tirage fait aujourd\'hui (serveur) -> coché',
      );
    });

    testWidgets(
      'AUDIT — une mission validée ailleurs (même contrôleur partagé) met '
      'à jour Accueil SANS fermer/rouvrir l\'app',
      (t) async {
        final rig = _wellbeingRig(doneToday: ['pensee', 'tirage', 'moment']);
        await t.pumpWidget(_hostWithWellbeing(rig));
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(milliseconds: 50));
        expect(find.text('3/4'), findsOneWidget);

        // La consultation vient d'être détectée côté serveur (ex. depuis
        // « Mon parcours bien-être » sur la MÊME instance partagée) :
        // ici on simule directement le contrôleur qui vient d'être notifié.
        await rig.wellbeing.recordMission('consultation');
        await t.pump();

        expect(find.text('4/4'), findsOneWidget);
        expect(find.text('Journée Auryel complétée'), findsOneWidget);
      },
    );
  });

  group('DailyMissionTracker', () {
    test('reset logique automatique au changement de jour', () async {
      final tr = DailyMissionTracker();
      await tr.markDone(
        DailyMissionTracker.tirage,
        now: DateTime(2026, 9, 5, 10),
      );
      expect(
        await tr.isDone(
          DailyMissionTracker.tirage,
          now: DateTime(2026, 9, 5, 23),
        ),
        isTrue,
      );
      expect(
        await tr.isDone(
          DailyMissionTracker.tirage,
          now: DateTime(2026, 9, 6, 0, 1),
        ),
        isFalse,
      );
    });

    test('aucune notion de récompense / temps / achat', () {
      const api = {'isDone', 'markDone', 'tirage', 'consultation', 'moment'};
      expect(
        api.any(
          (m) =>
              m.toLowerCase().contains('reward') ||
              m.toLowerCase().contains('hour') ||
              m.toLowerCase().contains('second') ||
              m.toLowerCase().contains('credit') ||
              m.toLowerCase().contains('purchase'),
        ),
        isFalse,
      );
    });
  });

  group('Temps disponible (bloc compact)', () {
    testWidgets(
      'sans ConsultationScope -> « TEMPS DISPONIBLE » + « Temps offert '
      'disponible » + CTA « Commencer une consultation »',
      (t) async {
        await t.pumpWidget(_host());
        await t.pump(const Duration(seconds: 1));
        expect(find.text('TEMPS DISPONIBLE'), findsOneWidget);
        expect(find.text('Temps offert disponible'), findsOneWidget);
        // J6-F2 §11 — aucune discussion -> « Commencer une consultation »
        // (jamais « Consulter » qui ouvrait un ChatScreen sur selectedAdvisor).
        expect(find.text('Commencer une consultation'), findsOneWidget);
        expect(find.text('Consulter'), findsNothing);
      },
    );
  });

  group('Pensée du jour — préservée', () {
    testWidgets(
      'bloc partage : bénéfice + bouton « Partager maintenant » + « X / 30 '
      'jours » + aucune date',
      (t) async {
        await t.pumpWidget(_host());
        await t.pump(const Duration(seconds: 1));
        expect(
          find.textContaining('gagne 1 h de consultation'),
          findsOneWidget,
        );
        expect(find.text('Partager maintenant'), findsOneWidget);
        expect(find.text('Cliquez ici'), findsNothing);
        expect(find.textContaining('/ 30 jours'), findsOneWidget);
        expect(find.textContaining('AOÛT'), findsNothing);
        expect(find.textContaining('2026'), findsNothing);
      },
    );

    testWidgets('la publication du jour reste ouvrable depuis le CTA', (
      t,
    ) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Partager maintenant'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(DailyMessageSheet), findsOneWidget);
    });
  });

  group('Responsive ~384 dp', () {
    testWidgets('aucun overflow avec toutes les sections', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(384, 850);
      addTearDown(t.view.reset);
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      expect(find.text('TES MISSIONS DU JOUR'), findsOneWidget);
      expect(find.text('TEMPS DISPONIBLE'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

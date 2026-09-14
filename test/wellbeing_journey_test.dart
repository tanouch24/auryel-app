import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/api/wellbeing_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/meditation_audio.dart';
import 'package:auryel/data/meditation_catalog.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/meditation_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/screens/wellbeing_journey_screen.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/wellbeing_controller.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';
import 'package:auryel/widgets/relaxation_video_background.dart';

// ===========================================================================
// J7 — « Mon parcours bien-être » : API parsing, contrôleur, écran, récompense.
// Le serveur est l'autorité : aucun compteur local, la progression vient de
// GET /api/app/wellbeing/progress.
// ===========================================================================

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _progress({
  int total = 12,
  int cycleDays = 12,
  String? current = 'Ancrage',
  String? next = 'Harmonie',
  int toNext = 3,
  int cycle = 1,
  bool rewardEarned = false,
  List<String> doneToday = const [],
  Map<String, dynamic>? reward,
}) => {
  'completed_days_total': total,
  'cycle_completed_days': cycleDays,
  'current_level': current,
  'next_level': next,
  'days_to_next_level': toNext,
  'today': {
    'date': '2026-09-15',
    'missions': [
      for (final m in kWellbeingMissions)
        {'id': m, 'completed': doneToday.contains(m)},
    ],
    'completed': doneToday.length >= 4,
  },
  'cycle_number': cycle,
  'reward_earned_for_current_cycle': rewardEarned,
  'reward': ?reward,
};

typedef _Rig = ({
  WellbeingController controller,
  List<String> hits,
  List<Map<String, dynamic>> postBodies,
});

_Rig _rig({
  Future<http.Response> Function(http.Request req)? handler,
  String? token = 'tok',
}) {
  final hits = <String>[];
  final postBodies = <Map<String, dynamic>>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      if (req.method == 'POST') {
        postBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      }
      if (handler != null) return handler(req);
      if (req.url.path == '/api/app/wellbeing/progress') {
        return _json(_progress());
      }
      if (req.url.path == '/api/app/wellbeing/mission') {
        return _json(_progress());
      }
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  final controller = WellbeingController(
    api: WellbeingApi(client),
    tokenProvider: () async => token,
  );
  addTearDown(controller.dispose);
  return (controller: controller, hits: hits, postBodies: postBodies);
}

Widget _host(WellbeingController c) =>
    MaterialApp(home: WellbeingJourneyScreen(controller: c));

// --- harnais minimal pour le test « MeditationScreen -> mission moment » ---
class _FakeAudio implements MeditationAudio {
  final _done = StreamController<void>.broadcast();
  void emitComplete() => _done.add(null);
  @override
  Stream<void> get onComplete => _done.stream;
  @override
  Stream<Duration> get onPosition => const Stream.empty();
  @override
  Stream<Duration> get onDuration => const Stream.empty();
  @override
  bool get isPlaying => true;
  @override
  Future<void> prepare(String source) async {}
  @override
  Future<bool> play(String assetPath) async => true;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() => _done.close();
}

/// Surface vidéo factice minimale — sert uniquement à confirmer un
/// démarrage RÉEL (`play()` -> `true`), seul déclencheur de la mission
/// « Prends ton temps ». Aucun canal plateforme.
class _FakeVideoSurface implements RelaxationVideoSurface {
  bool _ready = false;
  @override
  bool get isReady => _ready;
  @override
  Future<bool> load(String url) async {
    _ready = true;
    return true;
  }

  @override
  Future<bool> play() async => true;
  @override
  Future<void> pause() async {}
  @override
  Widget? buildView() => _ready ? const SizedBox.shrink() : null;
  @override
  void dispose() {
    _ready = false;
  }
}

ContentRepository _repoWithOneVideo() {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path.contains('relaxation-videos')) {
        return http.Response(
          jsonEncode({
            'catalog_version': 'v1',
            'videos': [
              {
                'id': 'id-ocean',
                'slug': 'ocean',
                'title': 'Océan',
                'video_url': 'https://cdn.auryel.app/ocean.mp4',
                'category': 'calm',
                'is_generic': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json', 'etag': '"v1"'},
        );
      }
      return http.Response(jsonEncode({}), 500); // méditations -> embarqué
    }),
    baseUrl: 'http://test.local',
  );
  return ContentRepository(
    api: ContentApi(client),
    tokenProvider: () async => 'tok',
    embeddedThoughts: DailyThoughtRepository(
      seed: [
        DailyThought(
          id: 1,
          publishDate: DateTime(2026, 1, 1),
          phrase: 'x',
          interpretation: 'y',
          imageAsset: 'assets/pensees/x.webp',
        ),
      ],
    ),
    embeddedMeditations: const MeditationCatalog(),
  );
}

AuthController _authWithToken(ApiClient client, String? token) =>
    AuthController(
      repository: AuthRepository(
        api: AuthApi(client),
        tokenStore: InMemoryTokenStore(token),
      ),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  group('WellbeingProgress.fromJson', () {
    test('1 parsing complet + missions dans l’ordre serveur', () {
      final p = WellbeingProgress.fromJson(
        _progress(total: 12, cycleDays: 12, doneToday: ['pensee', 'tirage']),
      );
      expect(p.completedDaysTotal, 12);
      expect(p.cycleCompletedDays, 12);
      expect(p.currentLevel, 'Ancrage');
      expect(p.nextLevel, 'Harmonie');
      expect(p.daysToNextLevel, 3);
      expect(p.cycleNumber, 1);
      expect(p.rewardEarnedForCurrentCycle, isFalse);
      expect(p.today.date, '2026-09-15');
      expect(p.today.missions.map((m) => m.id).toList(), kWellbeingMissions);
      expect(p.today.mission('pensee')!.completed, isTrue);
      expect(p.today.mission('consultation')!.completed, isFalse);
      expect(p.rewardCreditedNow, isFalse);
    });

    test('2 current_level null -> null (pas de niveau)', () {
      final p = WellbeingProgress.fromJson(
        _progress(
          current: null,
          next: 'Élan',
          toNext: 5,
          cycleDays: 2,
          total: 2,
        ),
      );
      expect(p.currentLevel, isNull);
      expect(p.nextLevel, 'Élan');
    });

    test('3 bloc reward du POST (credited=true)', () {
      final p = WellbeingProgress.fromJson(
        _progress(reward: {'credited': true, 'credited_seconds': 900}),
      );
      expect(p.rewardCreditedNow, isTrue);
      expect(p.rewardCreditedSeconds, 900);
    });
  });

  // -------------------------------------------------------------------------
  group('WellbeingApi', () {
    test('4 getProgress -> GET /api/app/wellbeing/progress + Bearer', () async {
      final rig = _rig();
      await rig.controller.refresh();
      expect(rig.hits, contains('GET /api/app/wellbeing/progress'));
    });

    test('5 recordMission -> POST body { mission_id }', () async {
      final rig = _rig();
      await rig.controller.recordMission('moment');
      expect(rig.hits, contains('POST /api/app/wellbeing/mission'));
      expect(rig.postBodies.single, {'mission_id': 'moment'});
    });

    test('6 recordMission 409 -> WellbeingMissionActionMissing', () async {
      final client = ApiClient(
        httpClient: MockClient(
          (_) async => _json({'error': 'mission_action_missing'}, 409),
        ),
        baseUrl: 'http://test.local',
      );
      final api = WellbeingApi(client);
      expect(
        () => api.recordMission(bearer: 'tok', missionId: 'tirage'),
        throwsA(isA<WellbeingMissionActionMissing>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('WellbeingController', () {
    testWidgets('7 refresh charge la progression', (t) async {
      final rig = _rig();
      await rig.controller.refresh();
      expect(rig.controller.progress!.completedDaysTotal, 12);
      expect(rig.controller.error, isNull);
    });

    testWidgets('8 échec réseau -> error, dernière progression conservée', (
      t,
    ) async {
      var call = 0;
      final rig = _rig(
        handler: (req) async {
          call++;
          if (call == 1) return _json(_progress(total: 5, cycleDays: 5));
          throw http.ClientException('offline');
        },
      );
      await rig.controller.refresh();
      expect(rig.controller.progress!.completedDaysTotal, 5);
      await rig.controller.refresh();
      expect(rig.controller.progress!.completedDaysTotal, 5); // conservée
      expect(rig.controller.error, isNotNull);
    });

    testWidgets('9 recordMission met à jour la progression', (t) async {
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/app/wellbeing/mission') {
            return _json(
              _progress(
                total: 13,
                cycleDays: 13,
                doneToday: kWellbeingMissions,
              ),
            );
          }
          return _json(_progress());
        },
      );
      await rig.controller.recordMission('moment');
      expect(rig.controller.progress!.completedDaysTotal, 13);
      expect(rig.controller.progress!.today.completed, isTrue);
    });

    testWidgets('10 pendingRewardCycle : 1x par cycle puis acquitté', (
      t,
    ) async {
      final rig = _rig(
        handler: (_) async => _json(
          _progress(
            total: 30,
            cycleDays: 30,
            current: 'Rayonnement',
            next: null,
            toNext: 0,
            cycle: 1,
            rewardEarned: true,
          ),
        ),
      );
      await rig.controller.refresh();
      expect(rig.controller.pendingRewardCycle, 1);
      await rig.controller.acknowledgeReward(1);
      expect(rig.controller.pendingRewardCycle, isNull);
      // rechargé : ne réapparaît pas (ack persisté).
      await rig.controller.refresh();
      expect(rig.controller.pendingRewardCycle, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('WellbeingJourneyScreen', () {
    testWidgets('11 titre + état de chargement', (t) async {
      final rig = _rig();
      await t.pumpWidget(_host(rig.controller));
      expect(find.text('Mon parcours bien-être'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('12 données : cycle, niveau, prochain niveau, missions', (
      t,
    ) async {
      final rig = _rig(
        handler: (_) async => _json(
          _progress(
            total: 12,
            cycleDays: 12,
            current: 'Ancrage',
            next: 'Harmonie',
            toNext: 3,
            doneToday: ['pensee'],
          ),
        ),
      );
      await t.pumpWidget(_host(rig.controller));
      await t.pumpAndSettle();

      // Carte de progression (game map) : en-tête + niveau + cycle.
      expect(find.text('12 journées validées'), findsOneWidget);
      expect(find.text('Niveau Ancrage'), findsOneWidget);
      expect(find.text('CYCLE 1'), findsOneWidget);
      // Étape du jour + 4 missions nommées.
      expect(find.textContaining('ÉTAPE DU JOUR'), findsOneWidget);
      expect(find.text('Pensée du jour'), findsOneWidget);
      expect(find.text('Carte du jour'), findsOneWidget);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Moment'), findsOneWidget);
      // pensee faite -> « Terminée » ; les autres ont un CTA.
      expect(find.text('Terminée'), findsOneWidget);
      expect(find.text('Découvrir ma carte'), findsOneWidget);
      expect(find.text('Prendre un moment'), findsOneWidget);
      // ligne récompense — désormais tout en haut de l'écran (FINITIONS UX),
      // déjà visible sans scroll ; `scrollUntilVisible` est un no-op ici.
      await t.scrollUntilVisible(
        find.textContaining('15 minutes de consultation offertes'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Chaque journée compte, même après une pause'),
        findsOneWidget,
      );
    });

    testWidgets(
      'CORRECTIF UX FINAL — ordre exact : récompense, PUIS étape du jour, '
      'PUIS SEULEMENT ENSUITE la carte/chemin des 30 jours (rien dupliqué)',
      (t) async {
        final rig = _rig(
          handler: (_) async => _json(
            _progress(
              total: 3,
              cycleDays: 3,
              current: 'Ancrage',
              doneToday: ['pensee'],
            ),
          ),
        );
        await t.pumpWidget(_host(rig.controller));
        await t.pumpAndSettle();

        // Un seul exemplaire de chaque bloc (pas de duplication).
        expect(
          find.textContaining('15 minutes de consultation offertes'),
          findsOneWidget,
        );
        expect(find.textContaining('ÉTAPE DU JOUR'), findsOneWidget);

        // Comprendre le principe/la récompense, PUIS l'étape du jour,
        // AVANT la carte/chemin des 30 jours (en-tête stats + chemin peint).
        final rewardY = t
            .getTopLeft(
              find.textContaining('15 minutes de consultation offertes'),
            )
            .dy;
        final todayStepY = t
            .getTopLeft(find.textContaining('ÉTAPE DU JOUR'))
            .dy;
        final cycleHeaderY = t.getTopLeft(find.text('CYCLE 1')).dy;
        expect(
          rewardY,
          lessThan(todayStepY),
          reason: 'le texte explicatif/récompense précède l’étape du jour',
        );
        expect(
          todayStepY,
          lessThan(cycleHeaderY),
          reason:
              'l’étape du jour (4 actions) doit apparaître AVANT la carte/le '
              'chemin des 30 jours, pas après',
        );
      },
    );

    testWidgets('12 bis — CARTE DE PROGRESSION type jeu : chemin peint, '
        'étapes validées / du jour / verrouillées', (t) async {
      final rig = _rig(
        handler: (_) async => _json(_progress(total: 3, cycleDays: 3)),
      );
      await t.pumpWidget(_host(rig.controller));
      await t.pumpAndSettle();

      // chemin dessiné (CustomPaint) reliant les nœuds — pas une liste.
      expect(find.byType(CustomPaint), findsWidgets);
      // étape du jour mise en valeur.
      expect(find.textContaining('AUJOURD'), findsOneWidget);
      // le nœud « du jour » porte le n° 4 (3 validées -> jour 4).
      expect(find.text('4'), findsWidgets);
      // journées validées + niveau + repère de cycle.
      expect(find.text('3 journées validées'), findsOneWidget);
      expect(find.textContaining('ÉTAPE DU JOUR'), findsOneWidget);
      // au moins un jalon de niveau (jour 5 = Élan) visible dans la carte.
      await t.scrollUntilVisible(
        find.text('Élan'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Élan'), findsWidgets);
    });

    testWidgets('13 état erreur (aucune donnée) -> Réessayer', (t) async {
      final rig = _rig(handler: (_) async => throw http.ClientException('x'));
      await t.pumpWidget(_host(rig.controller));
      await t.pumpAndSettle();
      expect(find.text('Ton parcours n’a pas pu être chargé.'), findsOneWidget);
      expect(find.text('Réessayer'), findsWidgets);
    });

    testWidgets('14 CTA « Carte du jour » ouvre le vrai TirageScreen', (
      t,
    ) async {
      final rig = _rig(handler: (_) async => _json(_progress()));
      await t.pumpWidget(_host(rig.controller));
      await t.pumpAndSettle();
      final cta = find.text('Découvrir ma carte');
      await t.ensureVisible(cta);
      await t.pumpAndSettle();
      await t.tap(cta);
      await t.pumpAndSettle();
      expect(find.byType(TirageScreen), findsOneWidget);
    });

    testWidgets('15 récompense : « Rayonnement atteint » affiché une fois', (
      t,
    ) async {
      final rig = _rig(
        handler: (_) async => _json(
          _progress(
            total: 30,
            cycleDays: 30,
            current: 'Rayonnement',
            next: null,
            toNext: 0,
            rewardEarned: true,
          ),
        ),
      );
      await t.pumpWidget(_host(rig.controller));
      await t.pumpAndSettle();

      expect(find.text('Rayonnement atteint'), findsOneWidget);
      expect(
        find.textContaining('Tu as complété 30 journées de ton parcours.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '15 minutes de consultation viennent d’être '
          'ajoutées',
        ),
        findsOneWidget,
      );

      await t.tap(find.text('Continuer'));
      await t.pumpAndSettle();
      expect(find.text('Rayonnement atteint'), findsNothing);
      expect(rig.controller.pendingRewardCycle, isNull);
    });

    for (final w in const [360.0, 384.0, 430.0]) {
      testWidgets('16 aucun overflow à ${w.toInt()} dp', (t) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = Size(w, 820);
        addTearDown(t.view.reset);
        final rig = _rig(
          handler: (_) async =>
              _json(_progress(doneToday: ['pensee', 'moment'])),
        );
        await t.pumpWidget(_host(rig.controller));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  group('MeditationScreen -> mission moment', () {
    testWidgets(
      '17 vidéo réellement démarrée -> POST /api/app/wellbeing/mission '
      '{ moment }',
      (t) async {
        final hits = <String>[];
        final bodies = <Map<String, dynamic>>[];
        final client = ApiClient(
          httpClient: MockClient((req) async {
            hits.add('${req.method} ${req.url.path}');
            if (req.method == 'POST') {
              bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            }
            return _json(_progress(doneToday: kWellbeingMissions));
          }),
          baseUrl: 'http://test.local',
        );
        final audio = _FakeAudio();
        await t.pumpWidget(
          AuthScope(
            controller: _authWithToken(client, 'tok'),
            child: MaterialApp(
              home: Scaffold(
                body: ContentScope(
                  repository: _repoWithOneVideo(),
                  child: MeditationScreen(
                    audioOverride: audio,
                    now: DateTime(2026, 1, 1),
                    wellbeingApi: WellbeingApi(client),
                    videoSurfaceFactory: () => _FakeVideoSurface(),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();

        // Règle définitive : seul un démarrage vidéo RÉELLEMENT confirmé
        // valide la mission (l'audio, à lui seul, ne la coche jamais).
        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pumpAndSettle();

        expect(hits, contains('POST /api/app/wellbeing/mission'));
        expect(bodies.single, {'mission_id': 'moment'});
      },
    );

    // -------------------------------------------------------------------
    // AUDIT ACCUEIL/PARCOURS — LOT UX FINAL : preuve directe que Méditation
    // et « Mon parcours bien-être » partagent la MÊME source de vérité. Les
    // deux écrans sont montés SIMULTANÉMENT (aucune navigation, aucun
    // fermer/rouvrir) sous le MÊME `WellbeingController` : un démarrage
    // vidéo RÉELLEMENT confirmé dans Méditation doit se refléter
    // IMMÉDIATEMENT dans Parcours.
    // -------------------------------------------------------------------
    testWidgets(
      '20 — vidéo démarrée dans Méditation met à jour EN DIRECT « Mon '
      'parcours bien-être » monté à côté, sans fermer/rouvrir l’app',
      (t) async {
        var doneToday = <String>[];
        final client = ApiClient(
          httpClient: MockClient((req) async {
            if (req.method == 'POST' &&
                req.url.path == '/api/app/wellbeing/mission') {
              final body = jsonDecode(req.body) as Map<String, dynamic>;
              final id = body['mission_id'] as String;
              if (!doneToday.contains(id)) doneToday = [...doneToday, id];
              return _json(_progress(doneToday: doneToday));
            }
            return _json(_progress(doneToday: doneToday));
          }),
          baseUrl: 'http://test.local',
        );
        final shared = WellbeingController(
          api: WellbeingApi(client),
          tokenProvider: () async => 'tok',
        );
        addTearDown(shared.dispose);
        final audio = _FakeAudio();

        await t.pumpWidget(
          AuthScope(
            controller: _authWithToken(client, 'tok'),
            child: WellbeingScope(
              controller: shared,
              child: MaterialApp(
                home: Scaffold(
                  body: Column(
                    children: [
                      SizedBox(
                        height: 400,
                        child: ContentScope(
                          repository: _repoWithOneVideo(),
                          child: MeditationScreen(
                            audioOverride: audio,
                            now: DateTime(2026, 1, 1),
                            videoSurfaceFactory: () => _FakeVideoSurface(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: WellbeingJourneyScreen(controller: shared),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();

        // Avant : Parcours affiche un CTA « Prendre un moment » (mission
        // « moment » non faite) — les DEUX écrans lisent le même contrôleur.
        expect(shared.isMissionDone('moment'), isFalse);
        expect(find.text('Prendre un moment'), findsOneWidget);

        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pumpAndSettle();

        // La vidéo a RÉELLEMENT démarré -> mission validée côté serveur, et
        // l'écran Parcours (jamais démonté, monté à côté) le reflète SANS
        // qu'aucune navigation n'ait eu lieu : même contrôleur, même
        // `notifyListeners()`.
        expect(shared.isMissionDone('moment'), isTrue);
        expect(find.text('Prendre un moment'), findsNothing);
      },
    );

    testWidgets('19 CONSULTER la Pensée du jour (ouvrir la feuille) -> '
        'POST /api/app/wellbeing/mission { pensee }, indépendant du partage', (
      t,
    ) async {
      final hits = <String>[];
      final bodies = <Map<String, dynamic>>[];
      final client = ApiClient(
        httpClient: MockClient((req) async {
          hits.add('${req.method} ${req.url.path}');
          if (req.method == 'POST') {
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          }
          return _json(_progress());
        }),
        baseUrl: 'http://test.local',
      );
      final thought = DailyThought(
        id: 1,
        publishDate: DateTime(2026, 1, 1),
        phrase: 'x',
        interpretation: 'y',
        imageAsset: 'assets/pensees/publications/01.webp',
      );
      await t.pumpWidget(
        AuthScope(
          controller: _authWithToken(client, 'tok'),
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDailyThoughtSheet(
                      ctx,
                      thought: thought,
                      wellbeingApi: WellbeingApi(client),
                      onShare: ({imageBytes, required text}) async {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump();

      expect(hits, contains('POST /api/app/wellbeing/mission'));
      expect(bodies.single, {'mission_id': 'pensee'});
      // aucune requête vers la récompense de partage J5
      expect(hits.where((h) => h.contains('rewards')), isEmpty);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
    });

    testWidgets('18 sans token -> aucun POST (sync non bloquante)', (t) async {
      final hits = <String>[];
      final client = ApiClient(
        httpClient: MockClient((req) async {
          hits.add('${req.method} ${req.url.path}');
          return _json(_progress());
        }),
        baseUrl: 'http://test.local',
      );
      final audio = _FakeAudio();
      await t.pumpWidget(
        AuthScope(
          controller: _authWithToken(client, null),
          child: MaterialApp(
            home: Scaffold(
              body: MeditationScreen(
                audioOverride: audio,
                now: DateTime(2026, 1, 1),
                wellbeingApi: WellbeingApi(client),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      audio.emitComplete();
      await t.pump();
      await t.pump();
      expect(hits.where((h) => h.contains('wellbeing')), isEmpty);
    });
  });
}

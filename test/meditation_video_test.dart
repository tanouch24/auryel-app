import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/meditation_audio.dart';
import 'package:auryel/data/meditation_catalog.dart';
import 'package:auryel/data/meditation_item.dart';
import 'package:auryel/data/relaxation_video_selector.dart';
import 'package:auryel/screens/meditation_screen.dart';
import 'package:auryel/widgets/main_nav_scope.dart';
import 'package:auryel/widgets/relaxation_video_background.dart';

// ===========================================================================
// Méditation — la SCÈNE VIDÉO est l'élément PRINCIPAL, muette, et TOTALEMENT
// indépendante de l'audio MP3 : elle ne lance / n'arrête / ne met en pause /
// ne seek JAMAIS le lecteur audio, et ne modifie jamais sa position.
// ===========================================================================

const _kVideoViewKey = Key('fake-relax-video-view');
const _kStageKey = Key('meditation-video-stage');

class _FakeSurface implements RelaxationVideoSurface {
  _FakeSurface({this.loadResult = true, this.playResult = true, this.loadGate});

  final bool loadResult;

  /// Contrôle si `play()` simule un démarrage RÉEL (true) ou un échec (false)
  /// — pour tester le signal `onStarted` de [RelaxationVideoStage].
  final bool playResult;

  /// Si fourni, `load()` attend sa complétion avant de résoudre — simule une
  /// vidéo « en cours de chargement », pour distinguer un simple tap sur play
  /// d'un démarrage vidéo RÉELLEMENT confirmé.
  final Completer<void>? loadGate;
  final List<String> calls = [];
  bool _ready = false;
  bool disposed = false;

  @override
  bool get isReady => _ready;

  @override
  Future<bool> load(String url) async {
    calls.add('load:$url');
    if (loadGate != null) await loadGate!.future;
    _ready = loadResult;
    return loadResult;
  }

  @override
  Future<bool> play() async {
    calls.add('play');
    return playResult;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Widget? buildView() => _ready
      ? const ColoredBox(key: _kVideoViewKey, color: Colors.black)
      : null;

  @override
  void dispose() {
    disposed = true;
    calls.add('dispose');
    _ready = false;
  }
}

/// Lecteur audio factice. TOUTE commande est journalisée -> si la vidéo touche
/// l'audio, `calls` le prouve.
class _FakeAudio implements MeditationAudio {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _done = StreamController<void>.broadcast();
  final List<String> calls = [];
  bool _playing = false;

  void emitDuration(Duration d) => _dur.add(d);
  void emitPosition(Duration d) => _pos.add(d);
  void emitComplete() => _done.add(null);

  @override
  Stream<Duration> get onPosition => _pos.stream;
  @override
  Stream<Duration> get onDuration => _dur.stream;
  @override
  Stream<void> get onComplete => _done.stream;
  @override
  bool get isPlaying => _playing;
  @override
  Future<void> prepare(String source) async {
    calls.add('prepare:$source');
  }

  @override
  Future<bool> play(String s) async {
    calls.add('play:$s');
    _playing = true;
    return true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing = false;
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _playing = true;
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  void dispose() => calls.add('dispose');
}

ContentRepository _repoWithVideos(List<Map<String, dynamic>> videos) {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path.contains('relaxation-videos')) {
        return http.Response(
          jsonEncode({'catalog_version': 'v1', 'videos': videos}),
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

Map<String, dynamic> _v(String slug) => {
  'id': 'id-$slug',
  'slug': slug,
  'title': 'T $slug',
  'video_url': 'https://cdn.auryel.app/$slug.mp4',
  'category': 'calm',
  'is_generic': true,
};

Map<String, dynamic> _m(String id, String title) => {
  'id': id,
  'title': title,
  'description': '',
  'duration_minutes': 4,
  'category': 'detente',
  'audio_url': 'https://cdn.auryel.app/$id.mp3',
};

/// Catalogue distant des MÉDITATIONS (pour précédent/suivant), avec en option
/// un catalogue vidéo (vide par défaut -> pas de scène vidéo, non pertinent
/// pour ces tests de navigation).
ContentRepository _repoWithMeditations(
  List<Map<String, dynamic>> meditations, {
  List<Map<String, dynamic>> videos = const [],
}) {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path.contains('relaxation-videos')) {
        return http.Response(
          jsonEncode({'catalog_version': 'v1', 'videos': videos}),
          200,
          headers: {'content-type': 'application/json', 'etag': '"v1"'},
        );
      }
      if (req.url.path.contains('meditations')) {
        return http.Response(
          jsonEncode({'catalog_version': 'v1', 'meditations': meditations}),
          200,
          headers: {'content-type': 'application/json', 'etag': '"v1"'},
        );
      }
      return http.Response(jsonEncode({}), 500);
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

MeditationItem _libItem() => const MeditationItem(
  id: 'quand-tu-attends-un-message',
  title: 'Quand tu attends un message',
  description: '',
  assetPath: '',
  duration: Duration(minutes: 4),
  category: MeditationCategory.detente,
  audioUrl: 'https://cdn.auryel.app/med.mp3',
);

Widget _host(
  MeditationAudio audio, {
  ContentRepository? content,
  RelaxationVideoSurface Function()? surfaceFactory,
  MeditationItem? item,
  bool autoplayOnOpen = false,
}) {
  final screen = MeditationScreen(
    item: item,
    audioOverride: audio,
    now: DateTime(2026, 1, 1),
    videoSelector: RelaxationVideoSelector(random: Random(0)),
    videoSurfaceFactory: surfaceFactory,
    autoplayOnOpen: autoplayOnOpen,
  );
  return MaterialApp(
    home: MainNavScope(
      goToTab: (_) {},
      currentIndex: kTabMeditation,
      child: Scaffold(
        body: content == null
            ? screen
            : ContentScope(repository: content, child: screen),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // Scène vidéo — élément principal
  // =========================================================================

  testWidgets('la scène vidéo est un élément dédié, GRAND, au premier plan', (
    t,
  ) async {
    final a = _FakeAudio();
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('ocean-1')]),
        surfaceFactory: () => _FakeSurface(),
      ),
    );
    await t.pumpAndSettle();

    // zone vidéo présente sans même avoir lancé l'audio
    expect(find.byKey(_kStageKey), findsOneWidget);
    expect(find.byType(RelaxationVideoStage), findsOneWidget);
    expect(find.byKey(_kVideoViewKey), findsOneWidget); // frame rendue
    // grande : au moins 180 px de haut
    expect(t.getSize(find.byKey(_kStageKey)).height, greaterThanOrEqualTo(180));
  });

  testWidgets('sans ContentScope : aucune vidéo, l\'écran fonctionne', (
    t,
  ) async {
    final a = _FakeAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    expect(find.byType(MeditationScreen), findsOneWidget);
    expect(find.byType(RelaxationVideoStage), findsNothing);
    expect(
      find.byKey(_kStageKey),
      findsOneWidget,
    ); // la zone reste (placeholder)

    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(a.calls.any((c) => c.startsWith('play:')), true);
    expect(t.takeException(), isNull);
  });

  // =========================================================================
  // §3 — INDÉPENDANCE AUDIO / VIDÉO (régression du bug Samsung)
  // =========================================================================

  testWidgets('DÉMARRAGE de la vidéo : n\'appelle jamais l\'audio, ne coupe '
      'pas l\'audio, ne bouge pas la position', (t) async {
    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('ocean-1')]),
        surfaceFactory: () => surface,
      ),
    );
    await t.pumpAndSettle();

    // audio lancé, puis position à 01:30
    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    a.emitDuration(const Duration(minutes: 4));
    a.emitPosition(const Duration(seconds: 90));
    await t.pumpAndSettle();
    expect(find.text('01:30'), findsOneWidget);

    final audioBefore = [...a.calls];
    // la vidéo démarre (surface.load + surface.play) — SANS toucher l'audio
    expect(surface.calls, contains('load:https://cdn.auryel.app/ocean-1.mp4'));
    expect(surface.calls, contains('play'));
    expect(a.calls, audioBefore); // aucune commande audio de plus
    expect(a.isPlaying, isTrue);

    // le MP3 continue : 01:31, 01:32…
    a.emitPosition(const Duration(seconds: 91));
    await t.pumpAndSettle();
    expect(find.text('01:31'), findsOneWidget);
    a.emitPosition(const Duration(seconds: 92));
    await t.pumpAndSettle();
    expect(find.text('01:32'), findsOneWidget);
    expect(a.calls, audioBefore);
  });

  testWidgets('vidéo en échec au 1er chargement -> placeholder, AUDIO OK', (
    t,
  ) async {
    final a = _FakeAudio();
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('broken')]),
        surfaceFactory: () => _FakeSurface(loadResult: false),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();

    expect(find.byKey(_kVideoViewKey), findsNothing);
    expect(a.isPlaying, isTrue);
    expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // =========================================================================
  // CORRECTIF UX FINAL — un catalogue non vide ne doit JAMAIS laisser l'écran
  // bloqué sur le repli statique (pictogramme feuille) si un AUTRE visuel du
  // catalogue peut, lui, être lu.
  // =========================================================================

  testWidgets(
    'échec du visuel auto-sélectionné -> retente automatiquement un AUTRE '
    'visuel du catalogue (jamais bloqué sur le repli statique)',
    (t) async {
      final a = _FakeAudio();
      final surfaces = <_FakeSurface>[];
      var n = 0;
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('a'), _v('b'), _v('c')]),
          surfaceFactory: () {
            // Le tout premier visuel tenté échoue ; les suivants réussissent.
            final s = _FakeSurface(loadResult: n > 0);
            n++;
            surfaces.add(s);
            return s;
          },
        ),
      );
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      // Le repli automatique a fonctionné : une frame vidéo est bien rendue,
      // pas le pictogramme statique.
      expect(find.byKey(_kVideoViewKey), findsOneWidget);
      expect(
        surfaces.length,
        greaterThanOrEqualTo(2),
        reason: 'un 2e visuel a été tenté après l’échec du 1er',
      );
    },
  );

  testWidgets(
    'si TOUS les visuels échouent, on abandonne proprement après un nombre '
    'BORNÉ de tentatives (jamais de boucle infinie)',
    (t) async {
      final a = _FakeAudio();
      final surfaces = <_FakeSurface>[];
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('a'), _v('b'), _v('c')]),
          surfaceFactory: () {
            final s = _FakeSurface(loadResult: false);
            surfaces.add(s);
            return s;
          },
        ),
      );
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byKey(_kVideoViewKey), findsNothing); // repli statique
      // 1 tentative initiale + au plus 2 retries -> jamais plus de 3.
      expect(surfaces.length, lessThanOrEqualTo(3));
    },
  );

  // =========================================================================
  // Cycle de vie de LA VIDÉO (jamais l'audio)
  // =========================================================================

  testWidgets(
    'pause de l\'audio -> pause de la vidéo (la vidéo suit l\'état)',
    (t) async {
      final a = _FakeAudio();
      final surface = _FakeSurface();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('ocean-1')]),
          surfaceFactory: () => surface,
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pumpAndSettle();
      surface.calls.clear();

      await t.ensureVisible(find.bySemanticsLabel('Mettre en pause'));
      await t.tap(find.bySemanticsLabel('Mettre en pause'));
      await t.pumpAndSettle();
      expect(surface.calls, contains('pause'));
    },
  );

  testWidgets(
    'arrière-plan -> pause de la vidéo (et de l\'audio par l\'écran)',
    (t) async {
      final a = _FakeAudio();
      final surface = _FakeSurface();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('ocean-1')]),
          surfaceFactory: () => surface,
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pumpAndSettle();
      surface.calls.clear();

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(a.calls, contains('pause'));
      expect(surface.calls, contains('pause'));
    },
  );

  testWidgets('dispose de l\'écran -> le contrôleur vidéo est libéré', (
    t,
  ) async {
    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('ocean-1')]),
        surfaceFactory: () => surface,
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    expect(surface.disposed, isFalse);

    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(surface.disposed, isTrue);
  });

  testWidgets(
    'CORRECTIF « double dispose » — un `audioOverride` fourni (feed) '
    'n\'est JAMAIS disposé par l\'écran lui-même : la propriété reste à '
    'l\'appelant (planterait un vrai lecteur disposé 2 fois, observé en '
    'conditions réelles Samsung)',
    (t) async {
      final a = _FakeAudio();
      await t.pumpWidget(_host(a, item: _libItem()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pumpAndSettle();

      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();

      expect(
        a.calls,
        isNot(contains('dispose')),
        reason: 'l’écran ne possède pas cet audio : il ne le dispose pas',
      );
    },
  );

  // =========================================================================
  // Petits écrans Android
  // =========================================================================

  for (final size in const [
    Size(320, 480),
    Size(320, 520),
    Size(360, 640),
    Size(412, 915),
  ]) {
    testWidgets(
      'aucun overflow à ${size.width.toInt()}×${size.height.toInt()} '
      '(scène + contrôles, visuel auto-sélectionné)',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithVideos([for (var i = 0; i < 12; i++) _v('v$i')]),
            surfaceFactory: () => _FakeSurface(),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(_kStageKey), findsOneWidget);
      },
    );
  }

  // =========================================================================
  // Mission « Prends ton temps » — validée au démarrage RÉEL de la vidéo
  // =========================================================================

  group('Mission « Prends ton temps »', () {
    testWidgets(
      'non cochée avant que la vidéo ait réellement démarré (chargement en '
      'cours)',
      (t) async {
        final a = _FakeAudio();
        final gate = Completer<void>();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithVideos([_v('ocean-1')]),
            surfaceFactory: () => _FakeSurface(loadGate: gate),
          ),
        );
        await t.pumpAndSettle();

        // Tap sur play : l'audio démarre, la vidéo est encore en cours de
        // chargement (gate non complété) -> pas de démarrage vidéo confirmé.
        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pump();
        expect(a.isPlaying, isTrue, reason: 'l’audio, lui, a bien démarré');
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isFalse,
          reason: 'simple tap : la vidéo n’a pas encore réellement démarré',
        );

        // La vidéo termine de charger et démarre réellement -> mission validée.
        gate.complete();
        await t.pumpAndSettle();
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isTrue,
          reason: 'confirmation effective du démarrage vidéo',
        );
      },
    );

    testWidgets('vidéo réellement démarrée -> mission cochée immédiatement '
        '(pas besoin d’attendre la fin)', (t) async {
      final a = _FakeAudio();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('ocean-1')]),
          surfaceFactory: () => _FakeSurface(),
        ),
      );
      await t.pumpAndSettle();
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
      );

      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pumpAndSettle();
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isTrue,
      );
    });

    testWidgets('vidéo qui échoue à charger -> AUCUN repli, mission NON cochée '
        '(même avec l’audio en lecture)', (t) async {
      final a = _FakeAudio();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('broken')]),
          surfaceFactory: () => _FakeSurface(loadResult: false),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pumpAndSettle();
      expect(find.byKey(_kVideoViewKey), findsNothing); // placeholder
      expect(a.isPlaying, isTrue, reason: 'l’audio, lui, joue bien');
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
        reason: 'échec de chargement confirmé -> aucun repli sur l’audio',
      );
    });

    testWidgets(
      'vidéo chargée mais qui échoue à RÉELLEMENT démarrer (play() renvoie '
      'false) -> AUCUN repli, mission NON cochée',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithVideos([_v('ocean-1')]),
            surfaceFactory: () => _FakeSurface(playResult: false),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pumpAndSettle();
        expect(a.isPlaying, isTrue, reason: 'l’audio, lui, joue bien');
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isFalse,
          reason:
              'play() vidéo a échoué -> jamais de démarrage confirmé, '
              'aucun repli sur l’audio',
        );
      },
    );

    testWidgets(
      'validation idempotente : un seul markDone malgré plusieurs signaux '
      '(tap, démarrage vidéo, pause puis reprise -> nouveau démarrage vidéo)',
      (t) async {
        var markCalls = 0;
        final tracker = _CountingMissionTracker(() => markCalls++);
        final a = _FakeAudio();
        await t.pumpWidget(
          MaterialApp(
            home: MainNavScope(
              goToTab: (_) {},
              currentIndex: kTabMeditation,
              child: Scaffold(
                body: ContentScope(
                  repository: _repoWithVideos([_v('a'), _v('b')]),
                  child: MeditationScreen(
                    item: _libItem(),
                    audioOverride: a,
                    now: DateTime(2026, 1, 1),
                    missionTracker: tracker,
                    videoSelector: RelaxationVideoSelector(random: Random(0)),
                    videoSurfaceFactory: () => _FakeSurface(),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pumpAndSettle();
        expect(markCalls, 1);

        // Pause puis reprise : la vidéo redevient active -> re-déclenche le
        // signal `onStarted`, mais ne doit PAS re-marquer la mission.
        await t.ensureVisible(find.bySemanticsLabel('Mettre en pause'));
        await t.tap(find.bySemanticsLabel('Mettre en pause'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pumpAndSettle();

        expect(
          markCalls,
          1,
          reason:
              'un seul markDone malgré plusieurs '
              'démarrages vidéo',
        );
      },
    );

    testWidgets(
      'état persistant : la mission reste cochée après un rebuild complet '
      'de l’écran (nouvelle navigation)',
      (t) async {
        SharedPreferences.setMockInitialValues({});
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithVideos([_v('ocean-1')]),
            surfaceFactory: () => _FakeSurface(),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pumpAndSettle();
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isTrue,
        );

        // Écran totalement démonté puis remonté (navigation aller-retour) :
        // la coche vient de SharedPreferences, pas de l'état du widget.
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await t.pumpWidget(
          _host(
            _FakeAudio(),
            item: _libItem(),
            content: _repoWithVideos([_v('ocean-1')]),
            surfaceFactory: () => _FakeSurface(),
          ),
        );
        await t.pumpAndSettle();
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isTrue,
          reason: 'la coche survit à un démontage/remontage complet',
        );
      },
    );

    testWidgets(
      'FINITIONS UX — précédent/suivant démarrent l\'audio automatiquement '
      'mais, SANS vidéo disponible, ne cochent JAMAIS la mission (aucun '
      'repli)',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithMeditations([
              _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
              _m('deuxieme', 'Deuxième séance'),
            ]), // pas de vidéo dans ce catalogue
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('meditation-next-button')));
        await t.tap(find.byKey(const Key('meditation-next-button')));
        await t.pumpAndSettle();

        expect(
          a.isPlaying,
          isTrue,
          reason: 'l’audio, lui, a bien démarré automatiquement',
        );
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isFalse,
          reason:
              'démarrage audio automatique via suivant -> aucun repli, '
              'mission non cochée',
        );
      },
    );
  });

  // =========================================================================
  // Refonte épurée — plus de gros encadrement doré autour de la vidéo
  // =========================================================================

  testWidgets(
    'la scène vidéo n’a plus de bordure dorée décorative (design épuré)',
    (t) async {
      final a = _FakeAudio();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithVideos([_v('ocean-1')]),
          surfaceFactory: () => _FakeSurface(),
        ),
      );
      await t.pumpAndSettle();

      final decoratedBox = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(_kStageKey),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(
        decoration.border,
        isNull,
        reason: 'plus de gros encadrement doré autour du média',
      );
    },
  );

  // =========================================================================
  // Contrôles précédent / play / suivant
  // =========================================================================

  group('Contrôles précédent / play / suivant', () {
    const kPrevBtn = Key('meditation-previous-button');
    const kNextBtn = Key('meditation-next-button');

    testWidgets('les 3 contrôles sont présents (précédent, play, suivant)', (
      t,
    ) async {
      final a = _FakeAudio();
      await t.pumpWidget(_host(a, item: _libItem()));
      await t.pumpAndSettle();
      expect(find.byKey(kPrevBtn), findsOneWidget);
      expect(find.bySemanticsLabel('Lancer le moment'), findsOneWidget);
      expect(find.byKey(kNextBtn), findsOneWidget);
    });

    testWidgets(
      'sur le PREMIER élément du catalogue : tap sur précédent ne fait rien '
      '(pas de crash, pas de changement)',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithMeditations([
              _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
              _m('deuxieme', 'Deuxième séance'),
            ]),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(kPrevBtn));
        await t.tap(find.byKey(kPrevBtn));
        await t.pumpAndSettle();
        expect(find.text('Quand tu attends un message'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('suivant charge la méditation suivante du catalogue', (
      t,
    ) async {
      final a = _FakeAudio();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithMeditations([
            _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
            _m('deuxieme', 'Deuxième séance'),
          ]),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Quand tu attends un message'), findsOneWidget);

      await t.ensureVisible(find.byKey(kNextBtn));
      await t.tap(find.byKey(kNextBtn));
      await t.pumpAndSettle();
      expect(find.text('Deuxième séance'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('FINITIONS UX — suivant démarre AUTOMATIQUEMENT l\'audio de la '
        'nouvelle méditation (sans repasser par Play), position à zéro', (
      t,
    ) async {
      final a = _FakeAudio();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithMeditations([
            _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
            _m('deuxieme', 'Deuxième séance'),
          ]),
        ),
      );
      await t.pumpAndSettle();
      expect(a.calls, isEmpty, reason: 'jamais d’autoplay à l’ouverture');

      await t.ensureVisible(find.byKey(kNextBtn));
      await t.tap(find.byKey(kNextBtn));
      await t.pumpAndSettle();

      expect(find.text('Deuxième séance'), findsWidgets);
      expect(a.calls, contains('stop'), reason: 'nouvelle piste = reset');
      expect(
        a.calls.any((c) => c.startsWith('play:')),
        isTrue,
        reason: 'la nouvelle méditation démarre automatiquement',
      );
      expect(a.isPlaying, isTrue);
      expect(
        find.bySemanticsLabel('Mettre en pause'),
        findsOneWidget,
        reason: 'le bouton central reflète immédiatement la lecture en cours',
      );
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets(
      'FINITIONS UX — précédent démarre AUTOMATIQUEMENT l\'audio de la '
      'méditation précédente',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithMeditations([
              _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
              _m('deuxieme', 'Deuxième séance'),
            ]),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(kNextBtn));
        await t.tap(find.byKey(kNextBtn));
        await t.pumpAndSettle();
        a.calls.clear();

        await t.ensureVisible(find.byKey(kPrevBtn));
        await t.tap(find.byKey(kPrevBtn));
        await t.pumpAndSettle();

        expect(find.text('Quand tu attends un message'), findsWidgets);
        expect(a.calls, contains('stop'));
        expect(a.calls.any((c) => c.startsWith('play:')), isTrue);
        expect(a.isPlaying, isTrue);
        expect(find.text('00:00'), findsOneWidget);
      },
    );

    testWidgets(
      'précédent charge la méditation précédente ; sur le DERNIER élément, '
      'suivant est désactivé',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithMeditations([
              _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
              _m('deuxieme', 'Deuxième séance'),
            ]),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(kNextBtn));
        await t.tap(find.byKey(kNextBtn));
        await t.pumpAndSettle();
        expect(find.text('Deuxième séance'), findsOneWidget);

        // Dernier élément : suivant ne doit plus rien faire.
        await t.ensureVisible(find.byKey(kNextBtn));
        await t.tap(find.byKey(kNextBtn));
        await t.pumpAndSettle();
        expect(find.text('Deuxième séance'), findsOneWidget);
        expect(t.takeException(), isNull);

        // Précédent revient au premier élément.
        await t.ensureVisible(find.byKey(kPrevBtn));
        await t.tap(find.byKey(kPrevBtn));
        await t.pumpAndSettle();
        expect(find.text('Quand tu attends un message'), findsOneWidget);
      },
    );

    testWidgets(
      'changer de méditation ne touche pas au visuel choisi (sauf nécessité '
      'technique réelle)',
      (t) async {
        final a = _FakeAudio();
        final surfaces = <_FakeSurface>[];
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithMeditations(
              [
                _m(
                  'quand-tu-attends-un-message',
                  'Quand tu attends un message',
                ),
                _m('deuxieme', 'Deuxième séance'),
              ],
              videos: [_v('ocean-1')],
            ),
            surfaceFactory: () {
              final s = _FakeSurface();
              surfaces.add(s);
              return s;
            },
          ),
        );
        await t.pumpAndSettle();
        expect(surfaces, hasLength(1), reason: 'une seule vidéo initialisée');

        await t.ensureVisible(find.byKey(kNextBtn));
        await t.tap(find.byKey(kNextBtn));
        await t.pumpAndSettle();
        // Deux occurrences attendues : le titre des contrôles + la légende
        // posée sur la vidéo (le visuel, lui, n'a pas changé).
        expect(find.text('Deuxième séance'), findsWidgets);
        expect(
          surfaces,
          hasLength(1),
          reason: 'le changement de méditation n’a pas recréé de vidéo',
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('changer de méditation réinitialise la position audio à zéro '
        '(nouvelle piste = nouvelle position, pas un bug de l’indépendance '
        'audio/vidéo)', (t) async {
      final a = _FakeAudio();
      await t.pumpWidget(
        _host(
          a,
          item: _libItem(),
          content: _repoWithMeditations([
            _m('quand-tu-attends-un-message', 'Quand tu attends un message'),
            _m('deuxieme', 'Deuxième séance'),
          ]),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pumpAndSettle();
      a.emitDuration(const Duration(minutes: 4));
      a.emitPosition(const Duration(seconds: 90));
      await t.pumpAndSettle();
      expect(find.text('01:30'), findsOneWidget);

      await t.ensureVisible(find.byKey(kNextBtn));
      await t.tap(find.byKey(kNextBtn));
      await t.pumpAndSettle();
      expect(find.text('00:00'), findsOneWidget);
      expect(a.calls, contains('stop'));
    });
  });

  // =========================================================================
  // CORRECTIF UX FINAL — `autoplayOnOpen` : supprime le temps mort perçu au
  // tap dans la bibliothèque. Opt-in explicite (défaut `false`) : AUCUN
  // impact sur tous les autres appelants/tests de ce fichier.
  // =========================================================================

  group('autoplayOnOpen', () {
    testWidgets('true -> l\'audio démarre IMMÉDIATEMENT, sans aucun tap', (
      t,
    ) async {
      final a = _FakeAudio();
      await t.pumpWidget(_host(a, item: _libItem(), autoplayOnOpen: true));
      await t.pumpAndSettle();

      expect(a.isPlaying, isTrue);
      expect(
        a.calls.any((c) => c.startsWith('play:')),
        isTrue,
        reason: 'aucun tap requis : la lecture a démarré dès l’ouverture',
      );
      expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    });

    testWidgets(
      'false (défaut) -> AUCUN autoplay, comportement historique inchangé',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(_host(a, item: _libItem()));
        await t.pumpAndSettle();

        expect(a.calls, isEmpty);
        expect(a.isPlaying, isFalse);
        expect(find.bySemanticsLabel('Lancer le moment'), findsOneWidget);
      },
    );

    testWidgets(
      'true + un visuel disponible -> le visuel démarre aussi, la mission '
      '« Prends ton temps » se coche sur le VRAI démarrage vidéo',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(
          _host(
            a,
            item: _libItem(),
            content: _repoWithVideos([_v('ocean-1')]),
            surfaceFactory: () => _FakeSurface(),
            autoplayOnOpen: true,
          ),
        );
        await t.pumpAndSettle();

        expect(a.isPlaying, isTrue);
        expect(find.byKey(_kVideoViewKey), findsOneWidget);
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isTrue,
        );
      },
    );

    testWidgets(
      'true SANS aucune vidéo disponible -> l\'audio joue quand même, mais '
      'AUCUN repli : la mission reste NON cochée',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(_host(a, item: _libItem(), autoplayOnOpen: true));
        await t.pumpAndSettle();

        expect(a.isPlaying, isTrue, reason: 'l’audio, lui, démarre bien');
        expect(
          await DailyMissionTracker().isDone(DailyMissionTracker.moment),
          isFalse,
          reason: 'démarrage automatique de l’audio -> aucun repli mission',
        );
      },
    );
  });

  // =========================================================================
  // FINITIONS UX — contrôles « façon lecteur vidéo moderne » : visibles à
  // l'ouverture, auto-hide après inactivité, tap pour basculer.
  // =========================================================================

  group('Auto-hide des contrôles', () {
    List<double> opacities(WidgetTester t) => t
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .map((w) => w.opacity)
        .toList();

    testWidgets('contrôles visibles dès l\'ouverture', (t) async {
      final a = _FakeAudio();
      await t.pumpWidget(_host(a, item: _libItem()));
      await t.pump();
      final op = opacities(t);
      expect(op, isNotEmpty);
      expect(op, everyElement(1.0));
    });

    testWidgets(
      'un tap simple sur la vidéo masque les contrôles ; un second tap les '
      'réaffiche',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(_host(a, item: _libItem()));
        await t.pump();

        await t.tap(find.byKey(const Key('meditation-video-stage')));
        await t.pump();
        expect(
          opacities(t),
          everyElement(0.0),
          reason: 'un tap sur la vidéo masque les contrôles',
        );

        await t.tap(find.byKey(const Key('meditation-video-stage')));
        await t.pump();
        expect(
          opacities(t),
          everyElement(1.0),
          reason: 'un second tap les réaffiche',
        );
      },
    );

    testWidgets('disparition automatique après un délai d\'inactivité', (
      t,
    ) async {
      final a = _FakeAudio();
      await t.pumpWidget(_host(a, item: _libItem()));
      await t.pump();
      expect(opacities(t), everyElement(1.0));

      await t.pump(const Duration(seconds: 5));
      expect(
        opacities(t),
        everyElement(0.0),
        reason: 'auto-hide après quelques secondes sans interaction',
      );
    });

    testWidgets(
      'le timer d\'auto-hide est annulé proprement au dispose (pas de timer '
      'résiduel)',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(_host(a, item: _libItem()));
        await t.pump();
        // Démonte l'écran AVANT l'échéance du timer : si `dispose()` ne
        // l'annulait pas, flutter_test ferait échouer ce test (timer
        // résiduel détecté par le framework).
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'interagir avec un contrôle (Play) relance le délai d\'auto-hide',
      (t) async {
        final a = _FakeAudio();
        await t.pumpWidget(_host(a, item: _libItem()));
        await t.pump(const Duration(seconds: 3)); // < 4 s : encore visible
        await t.tap(find.bySemanticsLabel('Lancer le moment'));
        await t.pump(); // interaction -> délai relancé
        await t.pump(const Duration(seconds: 3)); // 3 s depuis l'interaction
        expect(
          opacities(t),
          everyElement(1.0),
          reason: 'le délai a été relancé par l’interaction, pas encore écoulé',
        );
        await t.pump(const Duration(seconds: 2)); // 5 s depuis l'interaction
        expect(opacities(t), everyElement(0.0));
      },
    );
  });
}

/// Tracker qui compte les `markDone` sans jamais persister.
class _CountingMissionTracker extends DailyMissionTracker {
  _CountingMissionTracker(this.onMark);
  final void Function() onMark;
  final Set<String> _done = {};

  @override
  Future<void> markDone(String mission, {DateTime? now}) async {
    onMark();
    _done.add(mission);
  }

  @override
  Future<bool> isDone(String mission, {DateTime? now}) async =>
      _done.contains(mission);
}

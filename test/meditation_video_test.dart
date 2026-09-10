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
  _FakeSurface({this.loadResult = true});

  final bool loadResult;
  final List<String> calls = [];
  bool _ready = false;
  bool disposed = false;

  @override
  bool get isReady => _ready;

  @override
  Future<bool> load(String url) async {
    calls.add('load:$url');
    _ready = loadResult;
    return loadResult;
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Widget? buildView() =>
      _ready ? const ColoredBox(key: _kVideoViewKey, color: Colors.black) : null;

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
}) {
  final screen = MeditationScreen(
    item: item,
    audioOverride: audio,
    now: DateTime(2026, 1, 1),
    videoSelector: RelaxationVideoSelector(random: Random(0)),
    videoSurfaceFactory: surfaceFactory,
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

/// Slug ('a'..) du visuel actuellement chargé par la dernière surface.
String _currentSlug(List<_FakeSurface> surfaces) {
  final load = surfaces.last.calls.firstWhere((c) => c.startsWith('load:'));
  return load.split('/').last.split('.').first;
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

  testWidgets('sans ContentScope : aucune vidéo, l\'écran fonctionne', (t) async {
    final a = _FakeAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    expect(find.byType(MeditationScreen), findsOneWidget);
    expect(find.byType(RelaxationVideoStage), findsNothing);
    expect(find.byKey(_kStageKey), findsOneWidget); // la zone reste (placeholder)

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

  testWidgets('CHANGEMENT de visuel : seul le contrôleur vidéo est remplacé — '
      'l\'audio (commandes, état, position) est INCHANGÉ', (t) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('a'), _v('b'), _v('c')]),
        surfaceFactory: () {
          final s = _FakeSurface();
          surfaces.add(s);
          return s;
        },
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    a.emitDuration(const Duration(minutes: 4));
    a.emitPosition(const Duration(seconds: 90));
    await t.pumpAndSettle();
    expect(find.text('01:30'), findsOneWidget);

    final audioBefore = [...a.calls];
    final firstSurface = surfaces.last;
    final autoSlug = _currentSlug(surfaces);
    final target = ['a', 'b', 'c'].firstWhere((s) => s != autoSlug);

    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    await t.tap(find.text('T $target'));
    await t.pumpAndSettle();

    // AUDIO strictement inchangé
    expect(a.calls, audioBefore, reason: 'aucune commande audio pendant le '
        'changement de visuel');
    expect(a.isPlaying, isTrue);
    // position toujours 01:30, puis continue
    expect(find.text('01:30'), findsOneWidget);
    a.emitPosition(const Duration(seconds: 91));
    await t.pumpAndSettle();
    expect(find.text('01:31'), findsOneWidget);

    // VIDÉO : ancien contrôleur disposé, nouveau sur une autre URL, relancé
    expect(firstSurface.disposed, isTrue);
    expect(surfaces.last, isNot(same(firstSurface)));
    expect(_currentSlug(surfaces), target);
    expect(surfaces.last.calls, contains('play'));
  });

  testWidgets('option « Aléatoire » : re-tire un visuel, audio INTACT', (
    t,
  ) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('a'), _v('b'), _v('c'), _v('d')]),
        surfaceFactory: () {
          final s = _FakeSurface();
          surfaces.add(s);
          return s;
        },
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    a.emitDuration(const Duration(minutes: 4));
    a.emitPosition(const Duration(seconds: 42));
    await t.pumpAndSettle();
    final audioBefore = [...a.calls];

    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    await t.tap(find.text('Aléatoire'));
    await t.pumpAndSettle();

    expect(a.calls, audioBefore);
    expect(a.isPlaying, isTrue);
    expect(find.text('00:42'), findsOneWidget); // position conservée
    expect(t.takeException(), isNull);
  });

  testWidgets('ÉCHEC de chargement du nouveau visuel -> AUDIO CONTINUE, '
      'placeholder statique', (t) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    var n = 0;
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('a'), _v('b'), _v('c')]),
        surfaceFactory: () {
          final s = _FakeSurface(loadResult: n++ == 0);
          surfaces.add(s);
          return s;
        },
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    a.emitDuration(const Duration(minutes: 4));
    a.emitPosition(const Duration(seconds: 30));
    await t.pumpAndSettle();
    expect(find.byKey(_kVideoViewKey), findsOneWidget);
    final audioBefore = [...a.calls];

    final autoSlug = _currentSlug(surfaces);
    final target = ['a', 'b', 'c'].firstWhere((s) => s != autoSlug);
    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    await t.tap(find.text('T $target'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(a.calls, audioBefore); // audio jamais touché
    expect(a.isPlaying, isTrue);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.byKey(_kVideoViewKey), findsNothing); // placeholder
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
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();

    expect(find.byKey(_kVideoViewKey), findsNothing);
    expect(a.isPlaying, isTrue);
    expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // =========================================================================
  // Cycle de vie de LA VIDÉO (jamais l'audio)
  // =========================================================================

  testWidgets('pause de l\'audio -> pause de la vidéo (la vidéo suit l\'état)', (
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
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    surface.calls.clear();

    await t.tap(find.bySemanticsLabel('Mettre en pause'));
    await t.pumpAndSettle();
    expect(surface.calls, contains('pause'));
  });

  testWidgets('arrière-plan -> pause de la vidéo (et de l\'audio par l\'écran)', (
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
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    surface.calls.clear();

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(a.calls, contains('pause'));
    expect(surface.calls, contains('pause'));
  });

  testWidgets('dispose de l\'écran -> le contrôleur vidéo est libéré', (t) async {
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
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    expect(surface.disposed, isFalse);

    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(surface.disposed, isTrue);
  });

  // =========================================================================
  // « Choisir le visuel » — présence / absence / perf
  // =========================================================================

  testWidgets('bouton « Choisir le visuel » visible avec catalogue vidéo', (
    t,
  ) async {
    final a = _FakeAudio();
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([_v('a'), _v('b')]),
        surfaceFactory: () => _FakeSurface(),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Choisir le visuel'), findsOneWidget);
  });

  testWidgets('bouton « Choisir le visuel » ABSENT si aucun visuel', (t) async {
    final a = _FakeAudio();
    await t.pumpWidget(
      _host(a, item: _libItem(), content: _repoWithVideos(const [])),
    );
    await t.pumpAndSettle();
    expect(find.text('Choisir le visuel'), findsNothing);
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(a.isPlaying, isTrue);
  });

  testWidgets('la sheet n\'initialise AUCUNE vidéo réelle en plus (perf)', (
    t,
  ) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    await t.pumpWidget(
      _host(
        a,
        item: _libItem(),
        content: _repoWithVideos([for (var i = 0; i < 12; i++) _v('v$i')]),
        surfaceFactory: () {
          final s = _FakeSurface();
          surfaces.add(s);
          return s;
        },
      ),
    );
    await t.pumpAndSettle();
    expect(surfaces, hasLength(1)); // 1 seule vidéo (la scène)

    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    expect(find.text('Aléatoire'), findsOneWidget);
    expect(find.text('T v0'), findsOneWidget);
    expect(surfaces, hasLength(1)); // ouvrir la sheet n'a rien initialisé
    expect(find.byType(RelaxationVideoStage), findsOneWidget);
  });

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
      '(scène + contrôles + « Choisir le visuel »)',
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

        final btn = find.text('Choisir le visuel');
        await t.ensureVisible(btn);
        await t.tap(btn);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Aléatoire'), findsOneWidget);
      },
    );
  }
}

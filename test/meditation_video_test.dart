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
// LOT 9 — habillage vidéo (muet) de « Ton Moment » : l'audio prime, la vidéo
// ne bloque jamais, cycle de vie propre, échec = fond statique.
// ===========================================================================

const _kVideoViewKey = Key('fake-relax-video-view');

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sans ContentScope : aucune vidéo, l\'écran fonctionne', (t) async {
    final a = _FakeAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    expect(find.byType(MeditationScreen), findsOneWidget);
    expect(find.byType(RelaxationVideoBackground), findsNothing);

    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(a.calls.any((c) => c.startsWith('play:')), true);
    expect(t.takeException(), isNull);
  });

  testWidgets('vidéo montée seulement APRÈS le 1er play (data mobile)', (t) async {
    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
        content: _repoWithVideos([_v('ocean-1')]),
        surfaceFactory: () => surface,
      ),
    );
    await t.pumpAndSettle();

    expect(find.byType(RelaxationVideoBackground), findsNothing);
    expect(surface.calls, isEmpty);

    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();

    expect(find.byType(RelaxationVideoBackground), findsOneWidget);
    expect(surface.calls, contains('load:https://cdn.auryel.app/ocean-1.mp4'));
    expect(surface.calls, contains('play')); // active car audio en lecture
    expect(find.byKey(_kVideoViewKey), findsOneWidget);
  });

  testWidgets('vidéo en échec (404/format) -> fond statique, AUDIO CONTINUE', (
    t,
  ) async {
    final a = _FakeAudio();
    final surface = _FakeSurface(loadResult: false);
    await t.pumpWidget(
      _host(
        a,
        content: _repoWithVideos([_v('broken')]),
        surfaceFactory: () => surface,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();

    expect(find.byKey(_kVideoViewKey), findsNothing); // pas de rendu vidéo
    expect(a.isPlaying, true); // ...mais l'audio joue
    expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('pause de l\'audio -> pause de la vidéo', (t) async {
    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
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

  testWidgets('app en arrière-plan -> pause de la vidéo (comme l\'audio)', (
    t,
  ) async {
    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
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
    expect(a.calls, contains('pause')); // audio suspendu
    expect(surface.calls, contains('pause')); // vidéo suspendue de la même façon
  });

  testWidgets('dispose de l\'écran -> le contrôleur vidéo est libéré', (t) async {
    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
        content: _repoWithVideos([_v('ocean-1')]),
        surfaceFactory: () => surface,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pumpAndSettle();
    expect(surface.disposed, false);

    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(surface.disposed, true);
  });

  testWidgets('petit écran Android (320x480) : pas de crash', (t) async {
    t.view.physicalSize = const Size(320, 480);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final a = _FakeAudio();
    final surface = _FakeSurface();
    await t.pumpWidget(
      _host(
        a,
        content: _repoWithVideos([_v('ocean-1')]),
        surfaceFactory: () => surface,
      ),
    );
    await t.pumpAndSettle();
    final btn = find.bySemanticsLabel('Lancer le moment');
    await t.ensureVisible(btn);
    await t.pumpAndSettle();
    await t.tap(btn);
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(MeditationScreen), findsOneWidget);
    expect(find.byType(RelaxationVideoBackground), findsOneWidget);
  });

  // =========================================================================
  // LOT 11 — « Choisir le visuel »
  // =========================================================================

  MeditationItem libItem() => const MeditationItem(
    id: 'quand-tu-attends-un-message',
    title: 'Quand tu attends un message',
    description: '',
    assetPath: '',
    duration: Duration(minutes: 4),
    category: MeditationCategory.detente,
    audioUrl: 'https://cdn.auryel.app/med.mp3',
  );

  testWidgets('bouton « Choisir le visuel » visible quand le catalogue vidéo '
      'n\'est pas vide', (t) async {
    final a = _FakeAudio();
    await t.pumpWidget(
      _host(
        a,
        item: libItem(),
        content: _repoWithVideos([_v('a'), _v('b'), _v('c')]),
        surfaceFactory: () => _FakeSurface(),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Choisir le visuel'), findsOneWidget);
  });

  testWidgets('bouton « Choisir le visuel » ABSENT si aucun visuel disponible', (
    t,
  ) async {
    final a = _FakeAudio();
    await t.pumpWidget(
      _host(a, item: libItem(), content: _repoWithVideos(const [])),
    );
    await t.pumpAndSettle();
    expect(find.text('Choisir le visuel'), findsNothing);
    // et l'écran + l'audio fonctionnent normalement
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(a.isPlaying, isTrue);
  });

  testWidgets('bottom sheet : « Aléatoire » + les visuels, AUCUNE vidéo réelle '
      'initialisée en plus (perf)', (t) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    await t.pumpWidget(
      _host(
        a,
        item: libItem(),
        content: _repoWithVideos([for (var i = 0; i < 12; i++) _v('v$i')]),
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
    expect(surfaces, hasLength(1)); // 1 seule vidéo streamée (le fond)

    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    expect(find.text('Aléatoire'), findsOneWidget);
    expect(find.text('T v0'), findsOneWidget); // 1 tuile par visuel
    // ouvrir la sheet n'a créé AUCUNE nouvelle surface vidéo
    expect(surfaces, hasLength(1));
    expect(find.byType(RelaxationVideoBackground), findsOneWidget);
  });

  /// Slug ('a'..) du visuel actuellement chargé par la dernière surface.
  String currentSlug(List<_FakeSurface> surfaces) {
    final load = surfaces.last.calls.firstWhere((c) => c.startsWith('load:'));
    return load.split('/').last.split('.').first;
  }

  testWidgets('choix manuel d\'un visuel : l\'AUDIO ne bouge pas '
      '(source, position, état), la vidéo précédente est disposée', (t) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    await t.pumpWidget(
      _host(
        a,
        item: libItem(),
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
    expect(find.text('01:30'), findsOneWidget); // position affichée

    final audioCallsBefore = [...a.calls];
    final firstSurface = surfaces.last;
    final autoSlug = currentSlug(surfaces);
    final target = ['a', 'b', 'c'].firstWhere((s) => s != autoSlug);

    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    await t.tap(find.text('T $target')); // titre propre "T a"/"T b"/"T c"
    await t.pumpAndSettle();

    // AUDIO : aucune nouvelle commande, position et état conservés.
    expect(a.calls, audioCallsBefore);
    expect(a.isPlaying, isTrue);
    expect(find.text('01:30'), findsOneWidget);

    // VIDÉO : ancienne surface disposée, nouvelle sur une autre URL, relancée
    // (audio en lecture). Le muet est garanti par l'impl. réelle (setVolume 0).
    expect(firstSurface.disposed, isTrue);
    final newSurface = surfaces.last;
    expect(newSurface, isNot(same(firstSurface)));
    expect(currentSlug(surfaces), target);
    expect(newSurface.calls, contains('play'));
    expect(find.text('Aléatoire'), findsNothing); // sheet refermée
  });

  testWidgets('erreur de chargement du nouveau visuel -> AUDIO CONTINUE, '
      'fond statique', (t) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    var n = 0;
    await t.pumpWidget(
      _host(
        a,
        item: libItem(),
        content: _repoWithVideos([_v('a'), _v('b'), _v('c')]),
        // surface #0 (visuel auto) OK ; toute surface suivante ÉCHOUE.
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
    expect(find.byKey(_kVideoViewKey), findsOneWidget); // visuel auto affiché

    final autoSlug = currentSlug(surfaces);
    final target = ['a', 'b', 'c'].firstWhere((s) => s != autoSlug);
    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    await t.tap(find.text('T $target'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(a.isPlaying, isTrue); // l'audio n'est jamais coupé
    expect(find.text('00:30'), findsOneWidget); // position intacte
    expect(find.byKey(_kVideoViewKey), findsNothing); // fond statique Auryel
  });

  testWidgets('option « Aléatoire » : re-tire un visuel, audio intact', (
    t,
  ) async {
    final a = _FakeAudio();
    final surfaces = <_FakeSurface>[];
    await t.pumpWidget(
      _host(
        a,
        item: libItem(),
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
    final audioCalls = [...a.calls];

    await t.tap(find.text('Choisir le visuel'));
    await t.pumpAndSettle();
    await t.tap(find.text('Aléatoire'));
    await t.pumpAndSettle();

    expect(a.calls, audioCalls); // audio non touché
    expect(a.isPlaying, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('petit écran Android : « Choisir le visuel » + sheet sans '
      'overflow', (t) async {
    t.view.physicalSize = const Size(320, 520);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final a = _FakeAudio();
    await t.pumpWidget(
      _host(
        a,
        item: libItem(),
        content: _repoWithVideos([for (var i = 0; i < 12; i++) _v('v$i')]),
        surfaceFactory: () => _FakeSurface(),
      ),
    );
    await t.pumpAndSettle();
    final btn = find.text('Choisir le visuel');
    await t.ensureVisible(btn);
    await t.tap(btn);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Aléatoire'), findsOneWidget);
  });
}

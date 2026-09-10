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
}) {
  final screen = MeditationScreen(
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
}

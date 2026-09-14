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
import 'package:auryel/data/feed_swipe_hint_store.dart';
import 'package:auryel/data/meditation_audio.dart';
import 'package:auryel/data/meditation_catalog.dart';
import 'package:auryel/data/meditation_feed_order.dart';
import 'package:auryel/data/meditation_item.dart';
import 'package:auryel/screens/meditation_feed_screen.dart';
import 'package:auryel/screens/meditation_library_screen.dart';
import 'package:auryel/screens/meditation_screen.dart';
import 'package:auryel/widgets/relaxation_video_background.dart';

// ===========================================================================
// GROS LOT « feed méditation + réveil vocal » — feed vertical : 1 page = 1
// méditation (audio + visuel auto), ordre mélangé anti-répétition, autoplay
// sur la page active seulement, contrôleurs minimaux.
// ===========================================================================

Map<String, dynamic> _m(String id) => {
  'id': id,
  'title': 'T $id',
  'description': '',
  'duration_minutes': 4,
  'category': 'detente',
  'audio_url': 'https://cdn.auryel.app/$id.mp3',
};

MeditationItem _item(String id) => MeditationItem(
  id: id,
  title: 'T $id',
  description: '',
  assetPath: '',
  duration: const Duration(minutes: 4),
  category: MeditationCategory.detente,
  audioUrl: 'https://cdn.auryel.app/$id.mp3',
);

Map<String, dynamic> _v(String slug) => {
  'id': 'id-$slug',
  'slug': slug,
  'title': 'T $slug',
  'video_url': 'https://cdn.auryel.app/$slug.mp4',
  'category': 'calm',
  'is_generic': true,
};

ContentRepository _repoWithMeditations(
  List<Map<String, dynamic>> meditations, {
  List<Map<String, dynamic>> videos = const [],
}) {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path.contains('meditations')) {
        return http.Response(
          jsonEncode({'catalog_version': 'v1', 'meditations': meditations}),
          200,
          headers: {'content-type': 'application/json', 'etag': '"v1"'},
        );
      }
      // relaxation-videos.
      return http.Response(
        jsonEncode({'catalog_version': 'v1', 'videos': videos}),
        200,
        headers: {'content-type': 'application/json', 'etag': '"v1"'},
      );
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

/// Mémorisation de l'indication de swipe, contrôlable en test (pas de
/// SharedPreferences réel nécessaire, mais on le garde cohérent).
class _FakeHintStore extends FeedSwipeHintStore {
  _FakeHintStore({this.shown = false});
  bool shown;

  @override
  Future<bool> hasBeenShown() async => shown;

  @override
  Future<void> markShown() async => shown = true;
}

/// Lecteur audio factice — pas de canal plateforme réel en test (mêmes
/// bases que `meditation_video_test.dart`), TOUJOURS un `play()` réussi pour
/// que l'autoplay du feed soit observable.
class _FakeAudio implements MeditationAudio {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _done = StreamController<void>.broadcast();
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
  Future<void> prepare(String source) async {}
  @override
  Future<bool> play(String s) async {
    _playing = true;
    return true;
  }

  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> resume() async => _playing = true;
  @override
  Future<void> stop() async => _playing = false;
  @override
  void dispose() {}
}

class _FakeSurface implements RelaxationVideoSurface {
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
  Widget? buildView() =>
      _ready ? const ColoredBox(color: Colors.black) : null;
  @override
  void dispose() => _ready = false;
}

/// Lecteur audio traçable — enregistre chaque commande, pour prouver QUAND
/// (et si) `play()` a été appelé, indépendamment de `prepare()`.
class _TrackedAudio implements MeditationAudio {
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
  Future<void> prepare(String source) async => calls.add('prepare:$source');
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

/// Surface vidéo « à contrôle manuel » — `load()` n'aboutit que lorsque
/// [gate] (s'il est fourni) est complété : simule une vidéo distante trop
/// lente à initialiser.
class _GatedSurface implements RelaxationVideoSurface {
  _GatedSurface({this.gate});

  final Completer<bool>? gate;
  bool _ready = false;
  final List<String> calls = [];

  @override
  bool get isReady => _ready;
  @override
  Future<bool> load(String url) async {
    calls.add('load:$url');
    final ok = gate == null ? true : await gate!.future;
    _ready = ok;
    return ok;
  }

  @override
  Future<bool> play() async {
    calls.add('play');
    return true;
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Widget? buildView() =>
      _ready ? const ColoredBox(key: Key('gated-surface-view'), color: Colors.black) : null;
  @override
  void dispose() => calls.add('dispose');
}

Widget _host(
  ContentRepository content, {
  MeditationItem? initialItem,
  FeedSwipeHintStore? hintStore,
  MeditationFeedOrder? feedOrder,
}) {
  return MaterialApp(
    home: ContentScope(
      repository: content,
      child: MeditationFeedScreen(
        initialItem: initialItem,
        hintStore: hintStore ?? _FakeHintStore(shown: true),
        feedOrder: feedOrder ?? MeditationFeedOrder(random: Random(0)),
        audioFactory: () => _FakeAudio(),
        videoSurfaceFactory: () => _FakeSurface(),
      ),
    ),
  );
}

/// Variante « traçable » — expose les instances audio/vidéo RÉELLEMENT
/// créées (une par slot préparé, dans l'ordre de préparation), pour observer
/// PRÉCISÉMENT ce qui se passe par page.
typedef _TrackedEnv = ({
  Widget widget,
  List<_TrackedAudio> audios,
  List<RelaxationVideoSurface> surfaces,
});

_TrackedEnv _hostTracked(
  ContentRepository content, {
  RelaxationVideoSurface Function(int index)? surfaceAt,
}) {
  final audios = <_TrackedAudio>[];
  final surfaces = <RelaxationVideoSurface>[];
  var surfaceCalls = 0;
  final widget = MaterialApp(
    home: ContentScope(
      repository: content,
      child: MeditationFeedScreen(
        hintStore: _FakeHintStore(shown: true),
        feedOrder: MeditationFeedOrder(random: Random(0)),
        audioFactory: () {
          final a = _TrackedAudio();
          audios.add(a);
          return a;
        },
        videoSurfaceFactory: () {
          final i = surfaceCalls++;
          final s = surfaceAt != null ? surfaceAt(i) : _FakeSurface();
          surfaces.add(s);
          return s;
        },
      ),
    ),
  );
  return (widget: widget, audios: audios, surfaces: surfaces);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('catalogue distant -> feed vertical avec la 1ʳᵉ page jouable', (
    t,
  ) async {
    final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
    await t.pumpWidget(_host(repo));
    await t.pumpAndSettle();

    expect(find.byType(MeditationFeedScreen), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(MeditationScreen), findsOneWidget);
  });

  testWidgets(
    'la 1ʳᵉ page démarre AUTOMATIQUEMENT (autoplay), sans aucun tap',
    (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
      await t.pumpWidget(_host(repo));
      await t.pumpAndSettle();

      expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    },
  );

  testWidgets(
    'swipe vers le haut -> passe à la page/méditation suivante, celle-ci '
    'démarre automatiquement',
    (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
      await t.pumpWidget(_host(repo));
      await t.pumpAndSettle();
      final firstTitle = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .firstWhere((s) => s.startsWith('T '));

      await t.fling(
        find.byKey(const Key('meditation-feed-page-view')),
        const Offset(0, -600),
        1200,
      );
      await t.pumpAndSettle();

      final secondTitle = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .firstWhere((s) => s.startsWith('T '));
      expect(secondTitle, isNot(firstTitle));
      // La nouvelle page active a démarré toute seule.
      expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    },
  );

  testWidgets(
    'jamais plus de 3 lecteurs (`MeditationScreen`) instanciés en même '
    'temps, quelle que soit la taille du catalogue',
    (t) async {
      final repo = _repoWithMeditations([
        for (var i = 0; i < 12; i++) _m('med-$i'),
      ]);
      await t.pumpWidget(_host(repo));
      await t.pumpAndSettle();
      expect(
        t.widgetList<MeditationScreen>(find.byType(MeditationScreen)).length,
        lessThanOrEqualTo(3),
      );

      await t.fling(
        find.byKey(const Key('meditation-feed-page-view')),
        const Offset(0, -600),
        1200,
      );
      await t.pumpAndSettle();
      expect(
        t.widgetList<MeditationScreen>(find.byType(MeditationScreen)).length,
        lessThanOrEqualTo(3),
      );
    },
  );

  testWidgets(
    'entrée depuis la bibliothèque (initialItem) -> cette séance est la 1ʳᵉ '
    'page, immédiatement jouée',
    (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
      await t.pumpWidget(_host(repo, initialItem: _item('b')));
      await t.pumpAndSettle();

      expect(find.text('T b'), findsWidgets);
      expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    },
  );

  testWidgets('sans ContentScope -> repli embarqué, aucun crash', (t) async {
    await t.pumpWidget(
      const MaterialApp(home: MeditationFeedScreen()),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(MeditationFeedScreen), findsOneWidget);
  });

  testWidgets(
    'bouton « Toutes les méditations » ouvre la bibliothèque existante',
    (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b')]);
      await t.pumpWidget(_host(repo));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('meditation-feed-library-button')));
      await t.pumpAndSettle();
      expect(find.byType(MeditationLibraryScreen), findsOneWidget);
    },
  );

  group('Indication de swipe (1er usage uniquement)', () {
    testWidgets('jamais montrée -> visible à l\'ouverture', (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
      await t.pumpWidget(
        _host(repo, hintStore: _FakeHintStore(shown: false)),
      );
      await t.pumpAndSettle();

      expect(
        find.text('Fais glisser pour découvrir une autre méditation'),
        findsOneWidget,
      );
      final opacity = t
          .widget<AnimatedOpacity>(
            find.byKey(const Key('meditation-feed-swipe-hint')),
          )
          .opacity;
      expect(opacity, 1.0);
    });

    testWidgets('déjà montrée -> masquée d\'emblée', (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
      await t.pumpWidget(_host(repo, hintStore: _FakeHintStore(shown: true)));
      await t.pumpAndSettle();

      final opacity = t
          .widget<AnimatedOpacity>(
            find.byKey(const Key('meditation-feed-swipe-hint')),
          )
          .opacity;
      expect(opacity, 0.0);
    });

    testWidgets('se masque et se mémorise dès le 1er VRAI swipe', (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b'), _m('c')]);
      final hint = _FakeHintStore(shown: false);
      await t.pumpWidget(_host(repo, hintStore: hint));
      await t.pumpAndSettle();
      expect(
        t
            .widget<AnimatedOpacity>(
              find.byKey(const Key('meditation-feed-swipe-hint')),
            )
            .opacity,
        1.0,
      );

      await t.fling(
        find.byKey(const Key('meditation-feed-page-view')),
        const Offset(0, -600),
        1200,
      );
      await t.pumpAndSettle();

      expect(
        t
            .widget<AnimatedOpacity>(
              find.byKey(const Key('meditation-feed-swipe-hint')),
            )
            .opacity,
        0.0,
      );
      expect(hint.shown, isTrue, reason: 'jamais gênant après le 1er swipe');
    });
  });

  // ===========================================================================
  // CORRECTIF BLOQUANT — « lecture synchronisée » : la page suivante doit
  // être PRÊTE (vidéo initialisée + audio préparé) AVANT que l'utilisateur y
  // arrive ; au swipe, vidéo ET audio démarrent ENSEMBLE ; si la page n'est
  // pas prête, JAMAIS de son sans image.
  // ===========================================================================
  group('Lecture synchronisée (préchargement + readiness)', () {
    testWidgets(
      'la page suivante est préchargée PENDANT la lecture de la page '
      'courante (avant tout swipe)',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1')],
        );
        final env = _hostTracked(repo);
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();

        // Page 0 en lecture -> les slots 0 ET 1 (fenêtre N, N+1) doivent déjà
        // avoir leur propre lecteur audio ET leur propre surface vidéo créés
        // et préparés, SANS aucun swipe.
        expect(
          env.audios.length,
          greaterThanOrEqualTo(2),
          reason: 'audio de la page suivante déjà préparé à l’avance',
        );
        expect(
          env.surfaces.length,
          greaterThanOrEqualTo(2),
          reason: 'vidéo de la page suivante déjà chargée à l’avance',
        );
        expect(env.audios[1].calls, contains('prepare:https://cdn.auryel.app/b.mp3'));
      },
    );

    testWidgets(
      'page suivante DÉJÀ prête au swipe -> vidéo ET audio démarrent '
      'ENSEMBLE (aucun rattrapage différé)',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1')],
        );
        final env = _hostTracked(repo);
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle(); // page 0 prête + en lecture

        await t.fling(
          find.byKey(const Key('meditation-feed-page-view')),
          const Offset(0, -600),
          1200,
        );
        await t.pumpAndSettle();

        expect(find.byKey(const Key('meditation-feed-preparing')), findsNothing);
        expect(env.audios[1].calls, contains('play:https://cdn.auryel.app/b.mp3'));
      },
    );

    testWidgets(
      'vidéo lente à initialiser -> écran de transition, AUCUN audio de '
      'cette page tant qu\'elle n\'est pas prête (même la toute 1ʳᵉ page, '
      'où le même mécanisme de readiness s\'applique — pas de swipe requis '
      'pour prouver le mécanisme, exercé ici sur le cas le plus direct)',
      (t) async {
        final gate = Completer<bool>();
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0')],
        );
        // Slot 0 (1ʳᵉ page) : vidéo VOLONTAIREMENT bloquée -> simule un
        // réseau lent, dès l'ouverture du feed.
        final env = _hostTracked(
          repo,
          surfaceAt: (i) => i == 0 ? _GatedSurface(gate: gate) : _FakeSurface(),
        );
        await t.pumpWidget(env.widget);
        // Jamais `pumpAndSettle` ici : le média de la page est délibérément
        // bloqué, un indicateur de chargement indéterminé tourne encore.
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));

        // La page n'est PAS prête (vidéo toujours bloquée) -> transition
        // calme affichée, et surtout AUCUN `play:` audio pour cette page.
        expect(
          find.byKey(const Key('meditation-feed-preparing')),
          findsOneWidget,
          reason: 'jamais de fond vide/noir brut : transition calme affichée',
        );
        expect(
          env.audios[0].calls.any((c) => c.startsWith('play:')),
          isFalse,
          reason: 'jamais d’audio tant que la vidéo n’est pas prête',
        );

        // La vidéo finit par être prête -> vidéo ET audio démarrent ENSEMBLE.
        gate.complete(true);
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const Key('meditation-feed-preparing')), findsNothing);
        expect(
          env.audios[0].calls.any((c) => c.startsWith('play:')),
          isTrue,
          reason: 'vidéo prête -> l’audio démarre maintenant, EN MÊME TEMPS',
        );
      },
    );

    testWidgets(
      'vidéo qui échoue DÉFINITIVEMENT (jamais prête) -> la page finit '
      'quand même par démarrer (audio seul), jamais bloquée indéfiniment',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1')],
        );
        final env = _hostTracked(
          repo,
          surfaceAt: (i) => _GatedSurface(
            gate: Completer<bool>()..complete(false), // échec immédiat
          ),
        );
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();

        await t.fling(
          find.byKey(const Key('meditation-feed-page-view')),
          const Offset(0, -600),
          1200,
        );
        await t.pumpAndSettle();

        expect(
          env.audios[1].calls.any((c) => c.startsWith('play:')),
          isTrue,
          reason:
              'un échec vidéo définitif ne doit jamais empêcher la lecture '
              'audio (fond statique)',
        );
      },
    );

    testWidgets(
      'aucune double lecture : une seule page a un audio RÉELLEMENT en '
      'lecture à la fois',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1')],
        );
        final env = _hostTracked(repo);
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();

        await t.fling(
          find.byKey(const Key('meditation-feed-page-view')),
          const Offset(0, -600),
          1200,
        );
        await t.pumpAndSettle();

        final playing = env.audios.where((a) => a.isPlaying).length;
        expect(playing, 1, reason: 'jamais deux pages actives en même temps');
      },
    );
  });
}

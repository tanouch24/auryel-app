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
import 'package:auryel/screens/meditation_screen.dart';
import 'package:auryel/screens/relaxation_video_feed_screen.dart';
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
  'object_key': 'meditations/$slug.mp4',
  'category': 'calm',
  'is_generic': true,
};

ContentRepository _repoWithMeditations(
  List<Map<String, dynamic>> meditations, {
  List<Map<String, dynamic>> videos = const [],
}) {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path.contains('meditations') &&
          req.url.queryParameters['media'] != 'video') {
        return http.Response(
          jsonEncode({'catalog_version': 'v1', 'meditations': meditations}),
          200,
          headers: {'content-type': 'application/json', 'etag': '"v1"'},
        );
      }
      // Catalogue vidéo Méditations dynamique.
      return http.Response(
        jsonEncode({'catalog_version': 'v1', 'meditation_videos': videos}),
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
    'bouton « Toutes les méditations » ouvre la bibliothèque vidéo existante',
    (t) async {
      final repo = _repoWithMeditations([_m('a'), _m('b')]);
      await t.pumpWidget(_host(repo));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('meditation-feed-library-button')));
      await t.pumpAndSettle();
      expect(find.byType(RelaxationVideoFeedScreen), findsOneWidget);
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
  // CORRECTIF UX « sans spinner ni replay manuel » — le feed doit se
  // comporter comme un feed vidéo moderne : swipe -> autoplay audio ET
  // vidéo immédiat, jamais de spinner/texte de chargement, jamais besoin de
  // retaper Play. La vidéo, elle, est alimentée par un petit pool de
  // candidats déjà chargés d'avance (bornés par un timeout court) : si l'un
  // est trop lent/cassé, il est écarté pour la session et remplacé.
  // ===========================================================================
  group('Autoplay sans spinner (pool vidéo)', () {
    testWidgets(
      'swipe vers une page dont un visuel est déjà prêt dans le pool -> '
      'audio ET vidéo démarrent automatiquement, sans aucun tap',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1'), _v('v2')],
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

        expect(
          env.audios[1].calls.any((c) => c.startsWith('play:')),
          isTrue,
          reason: 'aucun tap requis : l’audio démarre automatiquement',
        );
        expect(
          find.bySemanticsLabel('Mettre en pause'),
          findsOneWidget,
          reason: 'le lecteur affiche déjà l’état « en lecture »',
        );
      },
    );

    testWidgets(
      'aucun spinner ni texte de chargement visible, jamais, y compris '
      'juste après un swipe',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1')],
        );
        final env = _hostTracked(repo);
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();
        expect(find.textContaining('Un instant'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await t.fling(
          find.byKey(const Key('meditation-feed-page-view')),
          const Offset(0, -600),
          1200,
        );
        await t.pump(); // frame immédiate après le swipe, avant tout settle
        expect(find.textContaining('Un instant'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'vidéo lente à charger (dépasse le timeout court) -> abandonnée, '
      'une AUTRE candidate déjà rapide prend le relais',
      (t) async {
        final slow = Completer<bool>(); // ne se complète jamais
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1'), _v('v2')],
        );
        var call = 0;
        final env = _hostTracked(
          repo,
          surfaceAt: (i) {
            call++;
            // Le tout 1er candidat du pool est délibérément lent ; les
            // suivants sont rapides.
            return call == 1 ? _GatedSurface(gate: slow) : _FakeSurface();
          },
        );
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();

        // Le timeout court du pool (2,5 s) doit avoir abandonné le candidat
        // lent -> un autre visuel, rapide, a fini par être assigné, SANS
        // jamais avoir affiché de spinner entre-temps.
        for (var i = 0; i < 30 && env.surfaces.length < 2; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining('Un instant'), findsNothing);
        expect(
          env.surfaces.length,
          greaterThanOrEqualTo(2),
          reason: 'la candidate lente a été abandonnée, une autre créée',
        );
      },
    );

    testWidgets(
      'vidéo dont le chargement échoue -> écartée pour la session, jamais '
      're-tentée par un réapprovisionnement ultérieur du pool',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b')],
          videos: [_v('broken')], // 1 SEULE vidéo au catalogue, cassée
        );
        final loadCalls = <String>[];
        final env = _hostTracked(
          repo,
          surfaceAt: (i) {
            final s = _GatedSurface(gate: Completer<bool>()..complete(false));
            return s;
          },
        );
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();
        // Laisse le temps à plusieurs cycles de réapprovisionnement.
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }

        for (final s in env.surfaces) {
          loadCalls.addAll((s as _GatedSurface).calls.where((c) => c.startsWith('load:')));
        }
        // Un catalogue à 1 SEULE vidéo cassée : elle n'est tentée qu'une
        // fois (jamais reproposée par un réapprovisionnement suivant),
        // ensuite le pool abandonne proprement (catalogue épuisé).
        expect(loadCalls.length, 1, reason: 'jamais de boucle sur une vidéo cassée');
      },
    );

    testWidgets(
      'pause volontaire de l\'utilisateur : un réapprovisionnement du pool '
      'plus tard ne relance PAS la lecture',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1')],
        );
        final env = _hostTracked(repo);
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();
        expect(env.audios[0].isPlaying, isTrue);

        await t.tap(find.bySemanticsLabel('Mettre en pause'));
        await t.pumpAndSettle();
        expect(env.audios[0].isPlaying, isFalse);
        final callsAtPause = List<String>.from(env.audios[0].calls);

        // Un cycle supplémentaire de préparation (ex. la fenêtre se
        // recalcule) ne doit JAMAIS faire hériter cette page d'un
        // redémarrage qu'elle n'a pas demandé.
        await t.pump(const Duration(seconds: 1));
        expect(env.audios[0].isPlaying, isFalse);
        expect(env.audios[0].calls, callsAtPause);
      },
    );

    testWidgets(
      'chaque changement de page réactive l\'autoplay (pas seulement la '
      '1ʳᵉ transition)',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1'), _v('v2')],
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
        expect(env.audios[1].calls.any((c) => c.startsWith('play:')), isTrue);

        await t.fling(
          find.byKey(const Key('meditation-feed-page-view')),
          const Offset(0, -600),
          1200,
        );
        await t.pumpAndSettle();
        expect(
          env.audios[2].calls.any((c) => c.startsWith('play:')),
          isTrue,
          reason: 'la 2ᵉ transition autoplay tout autant que la 1ʳᵉ',
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

    testWidgets(
      'activation normale : si un visuel est affiché, l\'audio de CETTE '
      'page est bien en lecture (jamais de vidéo qui joue seule)',
      (t) async {
        final repo = _repoWithMeditations(
          [_m('a'), _m('b'), _m('c')],
          videos: [_v('v0'), _v('v1'), _v('v2')],
        );
        final env = _hostTracked(repo);
        await t.pumpWidget(env.widget);
        await t.pumpAndSettle();

        if (env.surfaces.isNotEmpty && env.surfaces.first.buildView() != null) {
          expect(env.audios[0].isPlaying, isTrue);
        }
      },
    );
  });
}

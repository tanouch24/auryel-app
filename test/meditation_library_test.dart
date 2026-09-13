import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/meditation_catalog.dart';
import 'package:auryel/screens/meditation_library_screen.dart';
import 'package:auryel/screens/meditation_screen.dart';

// ===========================================================================
// LOT 11 — Bibliothèque : 1 AUDIO = 1 FICHE, 100 % distant, jamais multiplié
// par le catalogue vidéo.
// ===========================================================================

Map<String, dynamic> _med(String id) => {
  'id': id,
  'slug': id,
  'title': _titleFor(id),
  'audio_url': 'https://pub-xxx.r2.dev/m%C3%A9ditations/$id.mp3',
  'category': 'amour',
  'duration_seconds': 240,
};

String _titleFor(String id) => id == 'quand-tu-attends-un-message'
    ? 'Quand tu attends un message'
    : 'Méditation $id';

Map<String, dynamic> _vid(String slug) => {
  'id': 'id-$slug',
  'slug': slug,
  'title': 'Ambiance $slug',
  'video_url': 'https://pub-xxx.r2.dev/relaxation-videos/$slug.mp4',
  'category': 'calm',
  'is_generic': true,
};

/// Repo qui sert `n` méditations ET `v` vidéos (catalogues séparés).
ContentRepository _repo({required int meditations, required int videos}) {
  final medList = [
    for (var i = 0; i < meditations; i++)
      _med(i == 20 ? 'quand-tu-attends-un-message' : 'med-$i'),
  ];
  final vidList = [for (var i = 0; i < videos; i++) _vid('relax-$i')];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      final body = req.url.path.contains('relaxation-videos')
          ? {'catalog_version': 'v', 'videos': vidList}
          : {'catalog_version': 'm', 'meditations': medList};
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json', 'etag': '"x"'},
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

Widget _host(ContentRepository? repo) {
  const screen = MeditationLibraryScreen();
  return MaterialApp(
    home: repo == null ? screen : ContentScope(repository: repo, child: screen),
  );
}

Finder _card() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('med-'),
  skipOffstage: false,
);

/// Écran très haut : toute la liste est réellement construite (le `ListView`
/// est paresseux) -> on peut compter toutes les fiches en une passe.
Future<void> _pumpTall(WidgetTester t, ContentRepository repo) async {
  t.view.physicalSize = const Size(420, 40000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(_host(repo));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1 audio + 12 vidéos = EXACTEMENT 1 fiche', (t) async {
    await t.pumpWidget(_host(_repo(meditations: 1, videos: 12)));
    await t.pumpAndSettle();

    expect(find.byType(MeditationLibraryScreen), findsOneWidget);
    expect(_card(), findsOneWidget);
    expect(find.text('Bibliothèque'), findsOneWidget);
  });

  testWidgets('« Quand tu attends un message » apparaît UNE SEULE fois '
      '(50 audios + 12 vidéos = 50 fiches)', (t) async {
    await _pumpTall(t, _repo(meditations: 50, videos: 12));

    expect(_card(), findsNWidgets(50));
    // le titre exact n'est rendu qu'une fois (peu importe le nb de vidéos)
    expect(find.text('Quand tu attends un message'), findsOneWidget);
  });

  testWidgets('0 vidéo : la bibliothèque fonctionne quand même (50 fiches)', (
    t,
  ) async {
    await _pumpTall(t, _repo(meditations: 50, videos: 0));
    expect(_card(), findsNWidgets(50));
  });

  testWidgets('aucun plafond : 120 méditations distantes -> 120 fiches', (
    t,
  ) async {
    await _pumpTall(t, _repo(meditations: 120, videos: 12));
    expect(_card(), findsNWidgets(120));
  });

  testWidgets('sans ContentScope -> repli embarqué, pas de crash', (t) async {
    await t.pumpWidget(_host(null));
    await t.pumpAndSettle();
    expect(_card(), findsNWidgets(MeditationCatalog.items.length));
  });

  group('Flèche de défilement (FINITIONS UX)', () {
    testWidgets('visible dès l\'arrivée sur l\'écran', (t) async {
      await t.pumpWidget(_host(_repo(meditations: 30, videos: 0)));
      await t.pumpAndSettle();
      expect(find.text('Découvrir les méditations'), findsOneWidget);
    });

    testWidgets('disparaît après un vrai scroll de l\'utilisateur', (t) async {
      await t.pumpWidget(_host(_repo(meditations: 30, videos: 0)));
      await t.pumpAndSettle();
      expect(find.text('Découvrir les méditations'), findsOneWidget);

      await t.drag(find.byType(ListView), const Offset(0, -400));
      await t.pumpAndSettle();

      final opacity = t
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('Découvrir les méditations'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(opacity, 0.0, reason: 'un vrai scroll masque l’indication');
    });
  });

  testWidgets('tap sur une fiche -> ouvre le lecteur MeditationScreen', (
    t,
  ) async {
    await t.pumpWidget(_host(_repo(meditations: 3, videos: 12)));
    await t.pumpAndSettle();

    await t.tap(_card().first);
    await t.pumpAndSettle();
    expect(find.byType(MeditationScreen), findsOneWidget);
  });

  testWidgets(
    'petit écran Android 320x480 : liste scrollable, pas d\'overflow',
    (t) async {
      t.view.physicalSize = const Size(320, 480);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await t.pumpWidget(_host(_repo(meditations: 30, videos: 12)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(MeditationLibraryScreen), findsOneWidget);
    },
  );
}

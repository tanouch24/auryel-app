import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/meditation_catalog.dart';
import 'package:auryel/data/relaxation_video.dart';
import 'package:auryel/data/relaxation_video_selector.dart';

// ===========================================================================
// LOT 9 — Vidéos apaisantes distantes : modèle, sélection auto + anti-répétition,
// couche API (ETag/304, erreurs), repository (serveur -> cache -> vide).
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json', 'etag': '"vv1"'},
);

Map<String, dynamic> _video(
  String slug, {
  String category = 'calm',
  List<String> compat = const [],
  bool? generic,
  String? url,
}) => {
  'id': 'id-$slug',
  'slug': slug,
  'title': 'T $slug',
  'video_url': url ?? 'https://cdn.auryel.app/$slug.mp4',
  'category': category,
  'tags': const <String>[],
  'compatible_meditation_categories': compat,
  'is_generic': ?generic,
};

RelaxationVideo _rv(
  String slug, {
  String category = 'calm',
  List<String> compat = const [],
  bool isGeneric = true,
}) => RelaxationVideo(
  id: 'id-$slug',
  slug: slug,
  title: 'T $slug',
  videoUrl: 'https://cdn.auryel.app/$slug.mp4',
  category: category,
  compatibleMeditationCategories: compat,
  isGeneric: isGeneric,
);

ContentRepository _repo(
  Future<http.Response> Function(http.Request) handler, {
  SharedPreferences? prefs,
  bool withApi = true,
}) {
  final client = ApiClient(
    httpClient: MockClient(handler),
    baseUrl: 'http://test.local',
  );
  return ContentRepository(
    api: withApi ? ContentApi(client) : null,
    tokenProvider: withApi ? (() async => 'tok') : null,
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
    prefs: prefs,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RelaxationVideo.tryFromJson — tolérant', () {
    test('entrée complète', () {
      final v = RelaxationVideo.tryFromJson(
        _video('ocean-1', category: 'ocean', compat: ['sommeil'], generic: false),
      )!;
      expect(v.slug, 'ocean-1');
      expect(v.category, 'ocean');
      expect(v.isGeneric, false);
      expect(v.compatibleMeditationCategories, ['sommeil']);
    });

    test('id manquant -> null (ignorée, jamais de crash)', () {
      expect(
        RelaxationVideo.tryFromJson({'video_url': 'https://x/y.mp4'}),
        isNull,
      );
    });

    test('video_url non http -> null', () {
      expect(
        RelaxationVideo.tryFromJson({'id': 'a', 'video_url': 'file:///x.mp4'}),
        isNull,
      );
    });

    test('clé inconnue ignorée, defaults sains', () {
      final v = RelaxationVideo.tryFromJson({
        'id': 'a',
        'video_url': 'https://x/y.mp4',
        'theme_experimental': 'peu importe',
      })!;
      expect(v.title, 'Ambiance apaisante');
      expect(v.category, 'calm');
      expect(v.tags, isEmpty);
      expect(v.isGeneric, true); // pas de compat listée -> générique
    });

    test('category est un TEXTE LIBRE (aucun enum fermé)', () {
      final v = RelaxationVideo.tryFromJson(
        _video('x', category: 'aurore-boreale'),
      )!;
      expect(v.category, 'aurore-boreale');
    });

    test('isCompatibleWith : générique passe toujours ; sinon match casse-insensible', () {
      expect(_rv('g').isCompatibleWith('sommeil'), true);
      final o = _rv('o', isGeneric: false, compat: ['Sommeil']);
      expect(o.isCompatibleWith('sommeil'), true);
      expect(o.isCompatibleWith('amour'), false);
    });
  });

  group('RelaxationVideoSelector — choix auto + anti-répétition', () {
    test('0 vidéo -> null', () {
      expect(
        RelaxationVideoSelector().choose(const [], meditationCategory: 'sommeil'),
        isNull,
      );
    });

    test('1 vidéo -> elle', () {
      final only = _rv('one');
      expect(
        RelaxationVideoSelector().choose([only], meditationCategory: 'amour'),
        same(only),
      );
    });

    test('filtre par compatibilité ; repli sur tout si rien de compatible', () {
      final a = _rv('a', isGeneric: false, compat: ['sommeil']);
      final b = _rv('b', isGeneric: false, compat: ['amour']);
      final sel = RelaxationVideoSelector(random: Random(1));
      // seul `a` est compatible sommeil
      for (var i = 0; i < 20; i++) {
        expect(
          sel.choose([a, b], meditationCategory: 'sommeil')!.slug,
          'a',
        );
      }
      // rien de compatible avec 'motivation' -> repli sur le catalogue entier
      final pick = sel.choose([a, b], meditationCategory: 'motivation');
      expect(pick, isNotNull);
    });

    test('Random injecté -> choix déterministe', () {
      final cat = [for (var i = 0; i < 5; i++) _rv('v$i')];
      final p1 = RelaxationVideoSelector(
        random: Random(42),
      ).choose(cat, meditationCategory: 'calm');
      final p2 = RelaxationVideoSelector(
        random: Random(42),
      ).choose(cat, meditationCategory: 'calm');
      expect(p1!.slug, p2!.slug);
    });

    test('évite les slugs récents tant qu\'un autre candidat existe', () {
      final cat = [for (var i = 0; i < 4; i++) _rv('v$i')];
      final sel = RelaxationVideoSelector(random: Random(7));
      for (var i = 0; i < 30; i++) {
        final p = sel.choose(
          cat,
          meditationCategory: 'calm',
          avoid: ['v0', 'v1', 'v2'],
        );
        expect(p!.slug, 'v3');
      }
    });

    test('catalogue <= historique -> répétition intelligente autorisée', () {
      final cat = [_rv('v0'), _rv('v1')];
      final p = RelaxationVideoSelector(random: Random(1)).choose(
        cat,
        meditationCategory: 'calm',
        avoid: ['v0', 'v1', 'v2'],
      );
      expect(p, isNotNull); // ne renvoie jamais null si le catalogue est non vide
    });

    test('pick() persiste l\'historique (max 3) via SharedPreferences', () async {
      final history = RelaxationVideoHistory(
        prefs: await SharedPreferences.getInstance(),
      );
      final sel = RelaxationVideoSelector(
        random: Random(3),
        history: history,
      );
      final cat = [for (var i = 0; i < 8; i++) _rv('v$i')];
      final seen = <String>[];
      for (var i = 0; i < 5; i++) {
        final p = await sel.pick(cat, meditationCategory: 'calm');
        seen.add(p!.slug);
      }
      final recent = await history.recent();
      expect(recent.length, 3);
      expect(recent.first, seen.last); // le plus récent en tête
      // pas de répétition immédiate d'un des 2 précédents
      for (var i = 2; i < seen.length; i++) {
        expect(seen.sublist(i - 2, i).contains(seen[i]), false);
      }
    });
  });

  group('ContentApi.relaxationVideos', () {
    ContentApi api(MockClient c) => ContentApi(
      ApiClient(httpClient: c, baseUrl: 'http://test.local'),
    );

    test('200 -> videos + catalogVersion + etag', () async {
      final res = await api(
        MockClient(
          (_) async => _json({
            'catalog_version': 'vv1',
            'videos': [_video('a'), _video('b')],
          }),
        ),
      ).relaxationVideos();
      expect(res.ok, true);
      expect(res.videos.map((v) => v.slug), ['a', 'b']);
      expect(res.catalogVersion, 'vv1');
      expect(res.etag, '"vv1"');
    });

    test('If-None-Match renvoyé ; 304 -> notModified, liste vide', () async {
      String? sent;
      final res = await api(
        MockClient((req) async {
          sent = req.headers['If-None-Match'];
          return http.Response('', 304);
        }),
      ).relaxationVideos(etag: '"vv1"');
      expect(sent, '"vv1"');
      expect(res.notModified, true);
      expect(res.videos, isEmpty);
    });

    test('catalogue vide (200, videos: []) -> ok, liste vide', () async {
      final res = await api(
        MockClient((_) async => _json({'catalog_version': 'v', 'videos': []})),
      ).relaxationVideos();
      expect(res.ok, true);
      expect(res.videos, isEmpty);
    });

    test('hors-2xx -> status renvoyé, liste vide, aucune exception', () async {
      final res = await api(
        MockClient((_) async => _json({}, 503)),
      ).relaxationVideos();
      expect(res.ok, false);
      expect(res.status, 503);
      expect(res.videos, isEmpty);
    });

    test('réseau KO -> exception absorbée en amont par le repository', () async {
      final r = _repo((_) async => throw http.ClientException('offline'));
      expect(await r.relaxationVideos(), isEmpty);
    });
  });

  group('ContentRepository.relaxationVideos — serveur -> cache -> vide', () {
    test('serveur valide -> liste + mise en cache', () async {
      final prefs = await SharedPreferences.getInstance();
      final r = _repo(
        (_) async => _json({
          'catalog_version': 'v1',
          'videos': [_video('a'), _video('b')],
        }),
        prefs: prefs,
      );
      final list = await r.relaxationVideos();
      expect(list.map((v) => v.slug), ['a', 'b']);
      // relu depuis le cache quand le serveur est indisponible
      final r2 = _repo((_) async => _json({}, 500), prefs: prefs);
      final cached = await r2.relaxationVideos();
      expect(cached.map((v) => v.slug), ['a', 'b']);
    });

    test('304 -> conserve le cache', () async {
      final prefs = await SharedPreferences.getInstance();
      await _repo(
        (_) async => _json({
          'catalog_version': 'v1',
          'videos': [_video('a')],
        }),
        prefs: prefs,
      ).relaxationVideos();
      final r2 = _repo((req) async {
        expect(req.headers['If-None-Match'], isNotNull);
        return http.Response('', 304);
      }, prefs: prefs);
      expect((await r2.relaxationVideos()).single.slug, 'a');
    });

    test('aucun serveur + aucun cache -> liste vide (jamais null, jamais throw)', () async {
      final r = _repo((_) async => _json({}, 404), withApi: false);
      expect(await r.relaxationVideos(), isEmpty);
    });

    test('serveur renvoie une 16e vidéo -> reconnue sans changement d\'app', () async {
      final many = [for (var i = 1; i <= 16; i++) _video('relaxation-$i')];
      final r = _repo(
        (_) async => _json({'catalog_version': 'v16', 'videos': many}),
      );
      final list = await r.relaxationVideos();
      expect(list, hasLength(16));
      expect(list.last.slug, 'relaxation-16');
    });
  });
}

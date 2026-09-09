import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/meditation_catalog.dart';

// ===========================================================================
// LOT CORRECTIF 2 — ContentRepository : priorité serveur -> cache -> embarqué,
// ETag / 304, catalogue vide, méditation non jouable.
// ===========================================================================

http.Response _json(
  Map<String, dynamic> b, [
  int s = 200,
  Map<String, String>? headers,
]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json', ...?headers},
);

final DateTime _now = DateTime(2026, 9, 9, 12);

DailyThought _embeddedThought() => DailyThought(
  id: 1,
  publishDate: DateTime(2026, 1, 1),
  phrase: 'Pensée EMBARQUÉE du pack local.',
  interpretation: 'Interprétation embarquée.',
  imageAsset: 'assets/pensees/x.webp',
);

DailyThoughtRepository _embeddedRepo() =>
    DailyThoughtRepository(seed: [_embeddedThought()]);

Map<String, dynamic> _serverThought({
  String phrase = 'Pensée SERVEUR du jour.',
}) => {
  'date': ContentRepository.dayString(_now),
  'daily_thought': {
    'id': 42,
    'phrase': phrase,
    'interpretation': 'Interprétation serveur.',
  },
  'daily_publication': null,
};

Map<String, dynamic> _serverCatalog({
  String version = 'cat-1',
  List<Map<String, dynamic>>? items,
}) => {
  'catalog_version': version,
  'items':
      items ??
      [
        {
          'id': 'srv_1',
          'title': 'Séance serveur',
          'description': 'Depuis le backend.',
          'audio_url': 'https://cdn/srv_1.m4a',
          'duration_seconds': 300,
          'category': 'respiration',
        },
      ],
};

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
    embeddedThoughts: _embeddedRepo(),
    embeddedMeditations: const MeditationCatalog(),
    prefs: prefs,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Pensée du jour — priorité', () {
    test('16 — serveur valide -> pensée serveur (prioritaire)', () async {
      final r = _repo((req) async {
        if (req.url.path == '/api/app/content/today') {
          return _json(_serverThought());
        }
        return _json({}, 404);
      });
      final t = await r.thoughtFor(_now);
      expect(t.phrase, 'Pensée SERVEUR du jour.');
    });

    test('17 — hors ligne, cache du jour présent -> pensée en cache', () async {
      final prefs = await SharedPreferences.getInstance();
      // 1er appel : serveur OK -> écrit le cache.
      final r1 = _repo(
        (_) async => _json(_serverThought(phrase: 'Pensée mise en CACHE.')),
        prefs: prefs,
      );
      await r1.thoughtFor(_now);

      // 2e appel : serveur KO -> doit servir le cache du jour, pas l'embarqué.
      final r2 = _repo(
        (_) async => throw http.ClientException('offline'),
        prefs: prefs,
      );
      final t = await r2.thoughtFor(_now);
      expect(t.phrase, 'Pensée mise en CACHE.');
    });

    test(
      '18 — 1er lancement hors ligne (aucun cache) -> pensée EMBARQUÉE',
      () async {
        final r = _repo((_) async => throw http.ClientException('offline'));
        final t = await r.thoughtFor(_now);
        expect(t.phrase, 'Pensée EMBARQUÉE du pack local.');
      },
    );

    test('serveur sans daily_thought -> cache absent -> embarqué', () async {
      final r = _repo(
        (_) async => _json({'daily_thought': null, 'daily_publication': null}),
      );
      final t = await r.thoughtFor(_now);
      expect(t.phrase, 'Pensée EMBARQUÉE du pack local.');
    });

    test('sans API (app non connectée) -> embarqué, aucun appel', () async {
      var hits = 0;
      final r = _repo((_) async {
        hits++;
        return _json({}, 404);
      }, withApi: false);
      final t = await r.thoughtFor(_now);
      expect(t.phrase, 'Pensée EMBARQUÉE du pack local.');
      expect(hits, 0);
    });
  });

  group('Méditations — ETag / 304 / cache / fallback', () {
    test('6 — 200 : items serveur + cache écrit (ETag + version)', () async {
      final prefs = await SharedPreferences.getInstance();
      final r = _repo(
        (_) async => _json(_serverCatalog(), 200, {'etag': 'cat-1'}),
        prefs: prefs,
      );
      final items = await r.meditations();
      expect(items.single.id, 'srv_1');
      expect(items.single.playbackSource, 'https://cdn/srv_1.m4a');

      final cached = prefs.getString('auryel.content.meditations.v1');
      expect(cached, isNotNull);
      expect(jsonDecode(cached!)['etag'], 'cat-1');
      expect(jsonDecode(cached)['catalog_version'], 'cat-1');
    });

    test(
      '4/5 — 2e appel : If-None-Match envoyé ; 304 -> cache CONSERVÉ',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await _repo(
          (_) async => _json(_serverCatalog(), 200, {'etag': 'cat-1'}),
          prefs: prefs,
        ).meditations();

        String? seenIfNoneMatch;
        final r2 = _repo((req) async {
          seenIfNoneMatch = req.headers['If-None-Match'];
          return http.Response('', 304);
        }, prefs: prefs);
        final items = await r2.meditations();
        expect(seenIfNoneMatch, 'cat-1');
        expect(items.single.id, 'srv_1'); // cache conservé, pas de fallback
      },
    );

    test('7 — erreur réseau -> cache si présent', () async {
      final prefs = await SharedPreferences.getInstance();
      await _repo(
        (_) async => _json(_serverCatalog(), 200, {'etag': 'cat-1'}),
        prefs: prefs,
      ).meditations();

      final r2 = _repo(
        (_) async => throw http.ClientException('offline'),
        prefs: prefs,
      );
      final items = await r2.meditations();
      expect(items.single.id, 'srv_1');
    });

    test('8 — aucune API + aucun cache -> catalogue EMBARQUÉ', () async {
      final r = _repo((_) async => _json({}, 404), withApi: false);
      final items = await r.meditations();
      expect(items, isNotEmpty);
      expect(items.first.id, MeditationCatalog.items.first.id);
    });

    test(
      '9 — catalogue serveur VIDE + aucun cache -> fallback embarqué propre',
      () async {
        final r = _repo((_) async => _json(_serverCatalog(items: [])));
        final items = await r.meditations();
        expect(items, isNotEmpty);
        expect(items.first.id, MeditationCatalog.items.first.id);
      },
    );

    test('9 bis — catalogue serveur vide MAIS cache non vide -> on garde le '
        'cache', () async {
      final prefs = await SharedPreferences.getInstance();
      await _repo(
        (_) async => _json(_serverCatalog(), 200, {'etag': 'cat-1'}),
        prefs: prefs,
      ).meditations();

      final r2 = _repo(
        (_) async => _json(_serverCatalog(items: [], version: 'v2')),
        prefs: prefs,
      );
      final items = await r2.meditations();
      expect(items.single.id, 'srv_1');
    });

    test('10 — momentOfDay : séance non jouable (ni URL ni asset) -> renvoyée '
        'mais hasPlayableSource == false (aucun crash)', () async {
      final r = _repo(
        (_) async => _json(
          _serverCatalog(
            items: [
              {'id': 'x', 'title': 'Sans audio', 'category': 'detente'},
            ],
          ),
        ),
      );
      final it = await r.momentOfDay(_now);
      expect(it, isNotNull);
      expect(it!.hasPlayableSource, isFalse);
      expect(it.playbackSource, '');
    });

    test('momentOfDay déterministe sur la liste résolue', () async {
      final r = _repo(
        (_) async => _json(
          _serverCatalog(
            items: [
              {'id': 'a', 'title': 'A'},
              {'id': 'b', 'title': 'B'},
              {'id': 'c', 'title': 'C'},
            ],
          ),
        ),
      );
      final i1 = await r.momentOfDay(_now);
      final i2 = await r.momentOfDay(_now);
      expect(i1!.id, i2!.id);
    });
  });
}

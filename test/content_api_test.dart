import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';

// ===========================================================================
// LOT CORRECTIF 2 — API contenu distant : ApiClient.getRaw (ETag / 304) +
// ContentApi (parsing tolérant /content/today et /content/meditations).
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

ContentApi _api(MockClient client) =>
    ContentApi(ApiClient(httpClient: client, baseUrl: 'http://test.local'));

void main() {
  group('ApiClient.getRaw', () {
    test('200 -> corps + ETag exposés, pas d\'exception', () async {
      final c = ApiClient(
        httpClient: MockClient(
          (_) async => _json({'ok': true}, 200, {'etag': 'v1'}),
        ),
        baseUrl: 'http://test.local',
      );
      final res = await c.getRaw('/x');
      expect(res.ok, isTrue);
      expect(res.notModified, isFalse);
      expect(res.body['ok'], true);
      expect(res.etag, 'v1');
    });

    test('4 — If-None-Match envoyé quand un ETag est fourni', () async {
      String? seen;
      final c = ApiClient(
        httpClient: MockClient((req) async {
          seen = req.headers['If-None-Match'];
          return _json({}, 304);
        }),
        baseUrl: 'http://test.local',
      );
      final res = await c.getRaw('/x', ifNoneMatch: 'abc');
      expect(seen, 'abc');
      expect(res.notModified, isTrue);
      expect(res.body, isEmpty); // 304 -> pas de corps
    });

    test('5 — 304 n\'est PAS une erreur', () async {
      final c = ApiClient(
        httpClient: MockClient((_) async => http.Response('', 304)),
        baseUrl: 'http://test.local',
      );
      final res = await c.getRaw('/x', ifNoneMatch: 'e');
      expect(res.statusCode, 304);
      expect(res.notModified, isTrue);
      expect(res.ok, isFalse);
    });

    test('401 -> ApiUnauthorizedException (comme les autres verbes)', () async {
      final c = ApiClient(
        httpClient: MockClient((_) async => _json({'error': 'x'}, 401)),
        baseUrl: 'http://test.local',
      );
      await expectLater(
        c.getRaw('/x'),
        throwsA(isA<ApiUnauthorizedException>()),
      );
    });

    test('réseau KO -> ApiNetworkException', () async {
      final c = ApiClient(
        httpClient: MockClient((_) async => throw http.ClientException('x')),
        baseUrl: 'http://test.local',
      );
      await expectLater(c.getRaw('/x'), throwsA(isA<ApiNetworkException>()));
    });

    test('500 -> ApiRawResponse (statut renvoyé, pas d\'exception)', () async {
      final c = ApiClient(
        httpClient: MockClient((_) async => _json({'error': 'boom'}, 500)),
        baseUrl: 'http://test.local',
      );
      final res = await c.getRaw('/x');
      expect(res.statusCode, 500);
      expect(res.ok, isFalse);
    });
  });

  group('ContentApi.today', () {
    test('1 — parsing valide (thought + publication)', () async {
      final api = _api(
        MockClient(
          (_) async => _json({
            'date': '2026-09-09',
            'daily_thought': {
              'id': 12,
              'phrase': 'Avance à ton rythme.',
              'interpretation': 'Rien ne presse aujourd\'hui.',
              'image_url': 'https://cdn/x.webp',
            },
            'daily_publication': {
              'image_url': 'https://cdn/pub.webp',
              'text': 'Partage cette force.',
            },
          }),
        ),
      );
      final res = await api.today();
      expect(res, isNotNull);
      expect(res!.serverDate, '2026-09-09');
      expect(res.thought!.phrase, 'Avance à ton rythme.');
      expect(res.thought!.interpretation, 'Rien ne presse aujourd\'hui.');
      expect(res.thought!.imageUrl, 'https://cdn/x.webp');
      expect(res.thought!.imageAsset, ''); // pas d'asset embarqué
      expect(res.publicationImageUrl, 'https://cdn/pub.webp');
    });

    test(
      '2 — champs today absents / nullables -> thought == null, pas de crash',
      () async {
        final api = _api(
          MockClient(
            (_) async => _json({
              'date': '2026-09-09',
              'daily_thought': null,
              'daily_publication': null,
            }),
          ),
        );
        final res = await api.today();
        expect(res, isNotNull);
        expect(res!.thought, isNull);
        expect(res.publicationImageUrl, isNull);
      },
    );

    test(
      '2 bis — daily_thought partiel (interpretation manquante) -> null',
      () async {
        final api = _api(
          MockClient(
            (_) async => _json({
              'daily_thought': {'phrase': 'Seule la phrase.'},
            }),
          ),
        );
        final res = await api.today();
        expect(res!.thought, isNull);
      },
    );

    test('hors-2xx -> null (ne bloque jamais)', () async {
      final api = _api(MockClient((_) async => _json({}, 503)));
      expect(await api.today(), isNull);
    });
  });

  group('ContentApi.meditations', () {
    test('3 — catalogue valide : items + catalog_version + etag', () async {
      final api = _api(
        MockClient(
          (_) async => _json(
            {
              'catalog_version': '2026-09-01',
              'items': [
                {
                  'id': 'calme_1',
                  'title': 'Respiration du calme',
                  'description': 'Trois minutes de souffle lent.',
                  'audio_url': 'https://cdn/calme_1.m4a',
                  'duration_seconds': 180,
                  'category': 'respiration',
                },
                {'id': 'bad'}, // titre manquant -> ignoré
              ],
            },
            200,
            {'etag': 'cat-v1'},
          ),
        ),
      );
      final res = await api.meditations();
      expect(res.ok, isTrue);
      expect(res.items, hasLength(1));
      expect(res.items.single.id, 'calme_1');
      expect(res.items.single.audioUrl, 'https://cdn/calme_1.m4a');
      expect(res.items.single.playbackSource, 'https://cdn/calme_1.m4a');
      expect(res.items.single.duration, const Duration(seconds: 180));
      expect(res.catalogVersion, '2026-09-01');
      expect(res.etag, 'cat-v1');
    });

    test(
      '4/5 — ETag renvoyé en If-None-Match ; 304 -> notModified, items vides',
      () async {
        String? seen;
        final api = _api(
          MockClient((req) async {
            seen = req.headers['If-None-Match'];
            return http.Response('', 304);
          }),
        );
        final res = await api.meditations(etag: 'cat-v1');
        expect(seen, 'cat-v1');
        expect(res.notModified, isTrue);
        expect(res.items, isEmpty);
        expect(res.etag, 'cat-v1'); // conservé pour le prochain appel
      },
    );

    test(
      '9 — catalogue serveur VIDE (200, items: []) -> ok, liste vide',
      () async {
        final api = _api(
          MockClient(
            (_) async => _json({'catalog_version': 'v2', 'items': []}),
          ),
        );
        final res = await api.meditations();
        expect(res.ok, isTrue);
        expect(res.items, isEmpty);
      },
    );

    test(
      'hors-2xx -> status renvoyé, items vides (pas d\'exception)',
      () async {
        final api = _api(MockClient((_) async => _json({}, 500)));
        final res = await api.meditations();
        expect(res.ok, isFalse);
        expect(res.status, 500);
        expect(res.items, isEmpty);
      },
    );
  });
}

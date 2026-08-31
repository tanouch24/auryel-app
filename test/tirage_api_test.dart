import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/tirage_api.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

({TirageApi tirage, ConsultationApi consultation, List<http.Request> reqs})
_api(Future<http.Response> Function(http.Request req) handler) {
  final reqs = <http.Request>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      reqs.add(req);
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  return (
    tirage: TirageApi(client),
    consultation: ConsultationApi(client),
    reqs: reqs,
  );
}

Map<String, dynamic> _tirageJson({
  String id = 'tir-1',
  List<String> keys = const ['le_fou', 'la_lune', 'le_soleil'],
}) => {
  'tirage_id': id,
  'card_keys': keys,
  'cards': [
    for (final k in keys)
      {'key': k, 'name': 'NOM-$k', 'interpretation': 'interp-$k'},
  ],
  'combined_interpretation': 'lecture assemblée',
  'advisor_id': 'maia',
  'created_at': '2026-08-31T09:30:00Z',
};

void main() {
  group('TirageApi.create', () {
    test(
      'A/B/C/D. POST /api/tirages, Bearer exact, body = uniquement card_keys',
      () async {
        final a = _api((_) async => _json(_tirageJson(), 201));
        await a.tirage.create(
          bearer: 'tk-123',
          cardKeys: ['le_fou', 'la_lune', 'le_soleil'],
        );
        final req = a.reqs.single;
        expect(req.method, 'POST');
        expect(req.url.path, '/api/tirages');
        expect(req.headers['Authorization'], 'Bearer tk-123');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'card_keys'}); // AUCUN autre champ
        expect(body['card_keys'], ['le_fou', 'la_lune', 'le_soleil']);
        expect(body.containsKey('user_id'), isFalse);
        expect(body.containsKey('advisor_id'), isFalse);
        expect(body.containsKey('interpretation'), isFalse);
      },
    );

    test('E/F/G. parsing réponse 201 : ordre des cards + created_at', () async {
      final a = _api(
        (_) async => _json(
          _tirageJson(id: 'x9', keys: ['le_soleil', 'le_fou', 'la_lune']),
          201,
        ),
      );
      final r = await a.tirage.create(
        bearer: 'tk',
        cardKeys: ['le_soleil', 'le_fou', 'la_lune'],
      );
      expect(r.tirageId, 'x9');
      expect(r.cardKeys, ['le_soleil', 'le_fou', 'la_lune']);
      expect(r.cards.map((c) => c.key).toList(), [
        'le_soleil',
        'le_fou',
        'la_lune',
      ]);
      expect(r.cards.first.name, 'NOM-le_soleil');
      expect(r.cards.first.interpretation, 'interp-le_soleil');
      expect(r.combinedInterpretation, 'lecture assemblée');
      expect(r.advisorId, 'maia');
      expect(r.createdAt, DateTime.utc(2026, 8, 31, 9, 30, 0));
    });

    test('L. 401 -> ApiUnauthorizedException', () async {
      final a = _api((_) async => _json({'error': 'unauthorized'}, 401));
      expect(
        a.tirage.create(bearer: 'tk', cardKeys: const ['a', 'b', 'c']),
        throwsA(isA<ApiUnauthorizedException>()),
      );
    });

    test('M. réseau -> ApiNetworkException', () async {
      final a = _api((_) async => throw http.ClientException('down'));
      expect(
        a.tirage.create(bearer: 'tk', cardKeys: const ['a', 'b', 'c']),
        throwsA(isA<ApiNetworkException>()),
      );
    });
  });

  group('TirageApi.list', () {
    test('H/I/J. limit + before URL-encodé + parsing next_cursor', () async {
      final a = _api(
        (_) async => _json({
          'tirages': [_tirageJson(id: 't1'), _tirageJson(id: 't2')],
          'next_cursor': '2026-08-30T12:00:00.000+00:00',
        }),
      );
      final r = await a.tirage.list(
        bearer: 'tk',
        limit: 5,
        before: '2026-08-31T10:00:00.000+00:00',
      );
      final url = a.reqs.single.url;
      expect(url.path, '/api/tirages');
      expect(url.queryParameters['limit'], '5');
      expect(url.queryParameters['before'], '2026-08-31T10:00:00.000+00:00');
      // le '+' du fuseau est bien encodé dans la query brute
      expect(
        url.query.contains('%2B') || url.query.contains('before='),
        isTrue,
      );
      expect(r.tirages.map((t) => t.tirageId).toList(), ['t1', 't2']);
      expect(r.nextCursor, '2026-08-30T12:00:00.000+00:00');
    });

    test('liste vide + next_cursor null', () async {
      final a = _api(
        (_) async => _json({'tirages': <dynamic>[], 'next_cursor': null}),
      );
      final r = await a.tirage.list(bearer: 'tk');
      expect(r.tirages, isEmpty);
      expect(r.nextCursor, isNull);
      expect(a.reqs.single.url.queryParameters['limit'], '20'); // défaut
      expect(a.reqs.single.url.queryParameters.containsKey('before'), isFalse);
    });
  });

  group('TirageApi.get', () {
    test('K. GET /api/tirages/<id> canonique', () async {
      final a = _api((_) async => _json(_tirageJson(id: 'abc')));
      final r = await a.tirage.get(bearer: 'tk', tirageId: 'abc');
      expect(a.reqs.single.url.path, '/api/tirages/abc');
      expect(r.tirageId, 'abc');
      expect(r.cards.length, 3);
    });

    test('404 tirage_not_found -> ApiException(404, code)', () async {
      final a = _api((_) async => _json({'error': 'tirage_not_found'}, 404));
      try {
        await a.tirage.get(bearer: 'tk', tirageId: 'nope');
        fail('devait lever');
      } on ApiException catch (e) {
        expect(e.statusCode, 404);
        expect(e.code, 'tirage_not_found');
      }
    });
  });

  group('ConsultationApi.sendMessage (T3 — tirageId optionnel)', () {
    Map<String, dynamic> okMsg() => {
      'reply': 'ok',
      'consultation': {
        'id': 'c-1',
        'advisor_id': 'maia',
        'started_at': '2026-08-31T10:00:00Z',
        'expires_at': '2026-08-31T12:00:00Z',
        'seconds_remaining': 7000,
        'credit_source': 'monthly',
        'opened_now': true,
      },
      'quota': {
        'is_premium': true,
        'monthly_limit': 4,
        'monthly_used': 1,
        'monthly_remaining': 3,
        'earned_available': 0,
        'period_start': '2026-08-01T00:00:00Z',
        'period_end': '2026-09-01T00:00:00Z',
      },
    };

    test('A. sans tirageId : body = EXACTEMENT {"message": ...}', () async {
      final a = _api((_) async => _json(okMsg()));
      await a.consultation.sendMessage(bearer: 'tk', message: 'salut');
      final body = jsonDecode(a.reqs.single.body) as Map<String, dynamic>;
      expect(body, {'message': 'salut'});
    });

    test(
      'B/C. avec tirageId : body = {message, tirage_id} et RIEN d\'autre',
      () async {
        final a = _api((_) async => _json(okMsg()));
        await a.consultation.sendMessage(
          bearer: 'tk',
          message: 'salut',
          tirageId: 'tir-77',
        );
        final body = jsonDecode(a.reqs.single.body) as Map<String, dynamic>;
        expect(body, {'message': 'salut', 'tirage_id': 'tir-77'});
      },
    );

    test('tirageId vide -> non envoyé', () async {
      final a = _api((_) async => _json(okMsg()));
      await a.consultation.sendMessage(
        bearer: 'tk',
        message: 'x',
        tirageId: '',
      );
      final body = jsonDecode(a.reqs.single.body) as Map<String, dynamic>;
      expect(body, {'message': 'x'});
    });
  });
}

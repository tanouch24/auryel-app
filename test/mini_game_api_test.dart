import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/mini_game_api.dart';

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(httpClient: MockClient(handler), baseUrl: _base);

void main() {
  group('DTO', () {
    test('MiniGameSession.fromJson', () {
      final s = MiniGameSession.fromJson(const {
        'session_id': 's-1',
        'game_key': 'sequence_recall',
        'started_at': '2026-09-15T12:00:00+00:00',
        'expires_at': '2026-09-15T12:05:00+00:00',
      });
      expect(s.sessionId, 's-1');
      expect(s.gameKey, 'sequence_recall');
      expect(s.expiresAt, '2026-09-15T12:05:00+00:00');
    });

    test('MiniGameResult.fromJson — rewarded', () {
      final r = MiniGameResult.fromJson(const {
        'status': 'completed',
        'outcome': 'rewarded',
        'awarded': true,
        'stars_awarded': 15,
        'new_balance': 40,
      });
      expect(r.awarded, isTrue);
      expect(r.starsAwarded, 15);
      expect(r.newBalance, 40);
      expect(r.isDailyLimitReached, isFalse);
      expect(r.isExpired, isFalse);
    });

    test('MiniGameResult.fromJson — plafond quotidien / expiré', () {
      final d = MiniGameResult.fromJson(const {
        'status': 'completed',
        'outcome': 'daily_limit_reached',
        'awarded': false,
        'stars_awarded': 0,
      });
      expect(d.isDailyLimitReached, isTrue);
      expect(d.newBalance, isNull);

      final e = MiniGameResult.fromJson(const {
        'status': 'expired',
        'outcome': 'expired',
        'awarded': false,
        'stars_awarded': 0,
      });
      expect(e.isExpired, isTrue);
    });
  });

  group('MiniGameApi', () {
    test('start : POST { game_key } seulement', () async {
      http.Request? seen;
      Map<String, dynamic>? body;
      final api = MiniGameApi(_client((req) async {
        seen = req;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'session_id': 's-9',
          'game_key': 'hidden_card',
          'started_at': '2026-09-15T12:00:00+00:00',
          'expires_at': '2026-09-15T12:05:00+00:00',
        });
      }));
      final s = await api.start(bearer: 'tok', gameKey: 'hidden_card');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/app/minigame/start');
      expect(seen!.headers['Authorization'], 'Bearer tok');
      expect(body, {'game_key': 'hidden_card'});
      expect(s.sessionId, 's-9');
    });

    test('finish : POST { session_id } UNIQUEMENT — aucun résultat de '
        'performance envoyé', () async {
      Map<String, dynamic>? body;
      final api = MiniGameApi(_client((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'status': 'completed',
          'outcome': 'rewarded',
          'awarded': true,
          'stars_awarded': 15,
          'new_balance': 15,
        });
      }));
      final r = await api.finish(bearer: 'tok', sessionId: 's-1');
      expect(body, {'session_id': 's-1'});
      expect(body!.containsKey('correct'), isFalse);
      expect(body!.containsKey('elapsed_seconds'), isFalse);
      expect(r.awarded, isTrue);
    });
  });
}

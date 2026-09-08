import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/memory_api.dart';
import 'package:auryel/data/memory_game.dart';
import 'package:auryel/state/memory_rewards_controller.dart';

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(httpClient: MockClient(handler), baseUrl: _base);

void main() {
  // =========================================================================
  // Mapping enum <-> API
  // =========================================================================
  test('GameDifficulty <-> chaîne API + valeurs d\'affichage 20/40/80 · 5/10/15',
      () {
    expect(GameDifficulty.facile.apiDifficulty, 'easy');
    expect(GameDifficulty.moyen.apiDifficulty, 'medium');
    expect(GameDifficulty.intense.apiDifficulty, 'hard');
    expect(GameDifficulty.intense.label, 'Difficile');

    expect(GameDifficulty.facile.rewardThresholdSeconds, 20);
    expect(GameDifficulty.moyen.rewardThresholdSeconds, 40);
    expect(GameDifficulty.intense.rewardThresholdSeconds, 80);
    expect(GameDifficulty.facile.rewardMinutes, 5);
    expect(GameDifficulty.moyen.rewardMinutes, 10);
    expect(GameDifficulty.intense.rewardMinutes, 15);

    expect(GameDifficulty.fromApi('hard'), GameDifficulty.intense);
    expect(GameDifficulty.fromApi('nope'), isNull);
  });

  // =========================================================================
  // DTO
  // =========================================================================
  group('DTO', () {
    test('MemoryGameSession.fromJson', () {
      final s = MemoryGameSession.fromJson(const {
        'game_id': 'g-1',
        'difficulty': 'medium',
        'threshold_seconds': 40,
        'reward_seconds': 600,
        'pair_count': 6,
        'started_at': '2026-09-15T12:00:00+00:00',
        'expires_at': '2026-09-15T12:10:00+00:00',
      });
      expect(s.gameId, 'g-1');
      expect(s.difficulty, 'medium');
      expect(s.thresholdSeconds, 40);
      expect(s.rewardSeconds, 600);
      expect(s.pairCount, 6);
      expect(s.expiresAt, '2026-09-15T12:10:00+00:00');
    });

    test('MemoryCompleteResult : récompense créditée', () {
      final r = MemoryCompleteResult.fromJson(const {
        'status': 'completed',
        'difficulty': 'easy',
        'elapsed_seconds': 12,
        'reward_credited': true,
        'credited_seconds': 300,
        'reward_seconds': 300,
        'outcome': 'rewarded',
        'next_eligible_at': '2026-09-22T12:00:00+00:00',
      });
      expect(r.rewardCredited, isTrue);
      expect(r.creditedSeconds, 300);
      expect(r.outcome, 'rewarded');
      expect(r.isTimeExceeded, isFalse);
      expect(r.isCooldown, isFalse);
      expect(r.nextEligibleAt, '2026-09-22T12:00:00+00:00');
    });

    test('MemoryCompleteResult : temps dépassé / cooldown / expiré', () {
      final t = MemoryCompleteResult.fromJson(const {
        'status': 'completed',
        'difficulty': 'medium',
        'elapsed_seconds': 55,
        'reward_credited': false,
        'credited_seconds': 0,
        'outcome': 'time_limit_exceeded',
      });
      expect(t.isTimeExceeded, isTrue);
      expect(t.rewardCredited, isFalse);

      final c = MemoryCompleteResult.fromJson(const {
        'status': 'completed',
        'reward_credited': false,
        'outcome': 'cooldown_active',
        'next_eligible_at': '2026-09-20T12:00:00+00:00',
      });
      expect(c.isCooldown, isTrue);

      final e = MemoryCompleteResult.fromJson(const {
        'status': 'expired',
        'reward_credited': false,
        'outcome': 'expired',
      });
      expect(e.isExpired, isTrue);
    });

    test('MemoryProgress.fromJson + forDifficulty + valeurs par défaut', () {
      final p = MemoryProgress.fromJson(const {
        'window_days': 7,
        'max_window_seconds': 1800,
        'difficulties': [
          {
            'difficulty': 'easy',
            'threshold_seconds': 20,
            'reward_seconds': 300,
            'eligible_now': false,
            'last_reward_at': '2026-09-14T12:00:00+00:00',
            'next_eligible_at': '2026-09-21T12:00:00+00:00',
            'remaining_seconds': 400000,
          },
          {
            'difficulty': 'medium',
            'threshold_seconds': 40,
            'reward_seconds': 600,
            'eligible_now': true,
            'remaining_seconds': 0,
          },
        ],
      });
      expect(p.windowDays, 7);
      expect(p.maxWindowSeconds, 1800);
      expect(p.forDifficulty('easy')!.eligibleNow, isFalse);
      expect(p.forDifficulty('medium')!.eligibleNow, isTrue);
      expect(p.forDifficulty('hard'), isNull);

      final empty = MemoryProgress.fromJson(const {});
      expect(empty.windowDays, 7);
      expect(empty.maxWindowSeconds, 1800);
      expect(empty.difficulties, isEmpty);
    });
  });

  // =========================================================================
  // MemoryApi — corps des requêtes : le client n'envoie JAMAIS de chrono
  // =========================================================================
  group('MemoryApi', () {
    test('start : POST { difficulty } seulement', () async {
      http.Request? seen;
      Map<String, dynamic>? body;
      final api = MemoryApi(_client((req) async {
        seen = req;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'game_id': 'g-9',
          'difficulty': 'hard',
          'threshold_seconds': 80,
          'reward_seconds': 900,
          'pair_count': 8,
        });
      }));
      final s = await api.start(bearer: 'tok', difficulty: 'hard');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/app/memory/start');
      expect(seen!.headers['Authorization'], 'Bearer tok');
      expect(body, {'difficulty': 'hard'});
      expect(s.gameId, 'g-9');
      expect(s.rewardSeconds, 900);
    });

    test('complete : POST { game_id } UNIQUEMENT — aucun elapsed_seconds', () async {
      Map<String, dynamic>? body;
      http.Request? seen;
      final api = MemoryApi(_client((req) async {
        seen = req;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'status': 'completed',
          'difficulty': 'easy',
          'elapsed_seconds': 15,
          'reward_credited': true,
          'credited_seconds': 300,
          'outcome': 'rewarded',
        });
      }));
      final r = await api.complete(bearer: 'tok', gameId: 'g-1');
      expect(seen!.url.path, '/api/app/memory/complete');
      expect(body, {'game_id': 'g-1'});
      expect(body!.containsKey('elapsed_seconds'), isFalse);
      expect(body!.containsKey('reward_seconds'), isFalse);
      expect(r.rewardCredited, isTrue);
    });

    test('getProgress : GET, lecture seule', () async {
      http.Request? seen;
      final api = MemoryApi(_client((req) async {
        seen = req;
        return _json({
          'window_days': 7,
          'max_window_seconds': 1800,
          'difficulties': const [],
        });
      }));
      await api.getProgress('tok');
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/api/app/memory/progress');
    });
  });

  // =========================================================================
  // MemoryRewardsController
  // =========================================================================
  group('MemoryRewardsController', () {
    MemoryApi apiThatReturns({
      Map<String, dynamic>? start,
      Map<String, dynamic>? complete,
      Map<String, dynamic>? progress,
      int completeStatus = 200,
    }) {
      return MemoryApi(_client((req) async {
        if (req.url.path.endsWith('/start')) return _json(start ?? const {});
        if (req.url.path.endsWith('/complete')) {
          return _json(complete ?? const {}, completeStatus);
        }
        return _json(progress ??
            const {
              'window_days': 7,
              'max_window_seconds': 1800,
              'difficulties': [],
            });
      }));
    }

    test('refresh charge la progression ; eligibilityFor', () async {
      final c = MemoryRewardsController(
        api: apiThatReturns(progress: const {
          'window_days': 7,
          'max_window_seconds': 1800,
          'difficulties': [
            {'difficulty': 'easy', 'eligible_now': true, 'reward_seconds': 300},
            {'difficulty': 'hard', 'eligible_now': false, 'reward_seconds': 900},
          ],
        }),
        tokenProvider: () async => 'tok',
      );
      await c.refresh();
      expect(c.loading, isFalse);
      expect(c.eligibilityFor('easy')!.eligibleNow, isTrue);
      expect(c.eligibilityFor('hard')!.eligibleNow, isFalse);
      expect(c.error, isNull);
    });

    test('startGame renvoie la session ; null si pas de token', () async {
      final c = MemoryRewardsController(
        api: apiThatReturns(start: const {'game_id': 'g-1', 'difficulty': 'easy'}),
        tokenProvider: () async => 'tok',
      );
      final s = await c.startGame('easy');
      expect(s!.gameId, 'g-1');

      final noTok = MemoryRewardsController(
        api: apiThatReturns(start: const {'game_id': 'x'}),
        tokenProvider: () async => null,
      );
      expect(await noTok.startGame('easy'), isNull);
    });

    test('completeGame renvoie le verdict serveur', () async {
      final c = MemoryRewardsController(
        api: apiThatReturns(complete: const {
          'status': 'completed',
          'difficulty': 'easy',
          'reward_credited': true,
          'credited_seconds': 300,
          'outcome': 'rewarded',
        }),
        tokenProvider: () async => 'tok',
      );
      final r = await c.completeGame('g-1');
      expect(r!.rewardCredited, isTrue);
      expect(r.creditedSeconds, 300);
    });

    test('completeGame : erreur réseau -> null, non bloquant', () async {
      final c = MemoryRewardsController(
        api: MemoryApi(_client((_) async => _json(const {'error': 'boom'}, 503))),
        tokenProvider: () async => 'tok',
      );
      final r = await c.completeGame('g-1');
      expect(r, isNull);
      expect(c.error, isNotNull);
    });
  });
}

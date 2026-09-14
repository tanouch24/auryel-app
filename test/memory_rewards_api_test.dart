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
  // Mapping enum <-> API — GROS CHANTIER AURYEL (Prompt 3/5) : la récompense
  // (Étoiles) est désormais RÉSOLUE PAR LE SERVEUR, identique pour les 3
  // niveaux — seul le seuil de temps reste une valeur d'affichage locale.
  // =========================================================================
  test('GameDifficulty <-> chaîne API + seuils de jeu 20/40/80', () {
    expect(GameDifficulty.facile.apiDifficulty, 'easy');
    expect(GameDifficulty.moyen.apiDifficulty, 'medium');
    expect(GameDifficulty.intense.apiDifficulty, 'hard');
    expect(GameDifficulty.intense.label, 'Difficile');

    expect(GameDifficulty.facile.rewardThresholdSeconds, 20);
    expect(GameDifficulty.moyen.rewardThresholdSeconds, 40);
    expect(GameDifficulty.intense.rewardThresholdSeconds, 80);

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
        'stars_reward': 15,
        'pair_count': 6,
        'started_at': '2026-09-15T12:00:00+00:00',
        'expires_at': '2026-09-15T12:10:00+00:00',
      });
      expect(s.gameId, 'g-1');
      expect(s.difficulty, 'medium');
      expect(s.thresholdSeconds, 40);
      expect(s.starsReward, 15);
      expect(s.pairCount, 6);
      expect(s.expiresAt, '2026-09-15T12:10:00+00:00');
    });

    test('MemoryCompleteResult : récompense créditée', () {
      final r = MemoryCompleteResult.fromJson(const {
        'status': 'completed',
        'difficulty': 'easy',
        'elapsed_seconds': 12,
        'reward_credited': true,
        'stars_awarded': 15,
        'stars_reward': 15,
        'outcome': 'rewarded',
      });
      expect(r.rewardCredited, isTrue);
      expect(r.starsAwarded, 15);
      expect(r.outcome, 'rewarded');
      expect(r.isTimeExceeded, isFalse);
      expect(r.isDailyLimitReached, isFalse);
    });

    test('MemoryCompleteResult : temps dépassé / plafond quotidien / expiré', () {
      final t = MemoryCompleteResult.fromJson(const {
        'status': 'completed',
        'difficulty': 'medium',
        'elapsed_seconds': 55,
        'reward_credited': false,
        'stars_awarded': 0,
        'outcome': 'time_limit_exceeded',
      });
      expect(t.isTimeExceeded, isTrue);
      expect(t.rewardCredited, isFalse);

      final c = MemoryCompleteResult.fromJson(const {
        'status': 'completed',
        'reward_credited': false,
        'outcome': 'daily_limit_reached',
      });
      expect(c.isDailyLimitReached, isTrue);

      final e = MemoryCompleteResult.fromJson(const {
        'status': 'expired',
        'reward_credited': false,
        'outcome': 'expired',
      });
      expect(e.isExpired, isTrue);
    });

    test('MemoryProgress.fromJson + valeurs par défaut (plafond PARTAGÉ, plus '
        'de fenêtre par difficulté)', () {
      final p = MemoryProgress.fromJson(const {
        'eligible_today': false,
        'stars_reward': 15,
        'next_reset_at': '2026-09-16T00:00:00+00:00',
        'difficulties': [
          {'difficulty': 'easy', 'threshold_seconds': 20, 'pair_count': 4},
          {'difficulty': 'medium', 'threshold_seconds': 40, 'pair_count': 6},
        ],
      });
      expect(p.eligibleToday, isFalse);
      expect(p.starsReward, 15);
      expect(p.nextResetAt, '2026-09-16T00:00:00+00:00');
      expect(p.difficulties, hasLength(2));
      expect(p.difficulties.first.difficulty, 'easy');
      expect(p.difficulties.first.pairCount, 4);

      final empty = MemoryProgress.fromJson(const {});
      expect(empty.eligibleToday, isFalse);
      expect(empty.starsReward, 0);
      expect(empty.nextResetAt, isNull);
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
          'stars_reward': 15,
          'pair_count': 8,
        });
      }));
      final s = await api.start(bearer: 'tok', difficulty: 'hard');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/app/memory/start');
      expect(seen!.headers['Authorization'], 'Bearer tok');
      expect(body, {'difficulty': 'hard'});
      expect(s.gameId, 'g-9');
      expect(s.starsReward, 15);
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
          'stars_awarded': 15,
          'outcome': 'rewarded',
        });
      }));
      final r = await api.complete(bearer: 'tok', gameId: 'g-1');
      expect(seen!.url.path, '/api/app/memory/complete');
      expect(body, {'game_id': 'g-1'});
      expect(body!.containsKey('elapsed_seconds'), isFalse);
      expect(body!.containsKey('stars_awarded'), isFalse);
      expect(r.rewardCredited, isTrue);
    });

    test('getProgress : GET, lecture seule', () async {
      http.Request? seen;
      final api = MemoryApi(_client((req) async {
        seen = req;
        return _json({
          'eligible_today': true,
          'stars_reward': 15,
          'next_reset_at': null,
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
              'eligible_today': true,
              'stars_reward': 15,
              'difficulties': [],
            });
      }));
    }

    test('refresh charge la progression PARTAGÉE (eligibleToday/starsReward)',
        () async {
      final c = MemoryRewardsController(
        api: apiThatReturns(progress: const {
          'eligible_today': false,
          'stars_reward': 15,
          'next_reset_at': '2026-09-16T00:00:00+00:00',
          'difficulties': [
            {'difficulty': 'easy', 'threshold_seconds': 20, 'pair_count': 4},
          ],
        }),
        tokenProvider: () async => 'tok',
      );
      await c.refresh();
      expect(c.loading, isFalse);
      expect(c.eligibleToday, isFalse);
      expect(c.starsReward, 15);
      expect(c.nextResetAt, '2026-09-16T00:00:00+00:00');
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
          'stars_awarded': 15,
          'outcome': 'rewarded',
        }),
        tokenProvider: () async => 'tok',
      );
      final r = await c.completeGame('g-1');
      expect(r!.rewardCredited, isTrue);
      expect(r.starsAwarded, 15);
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

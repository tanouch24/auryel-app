import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/account_api.dart';
import 'package:auryel/api/ai_report_api.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/local_user_data.dart';
import 'package:auryel/data/share_reward_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/state/auth_controller.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // AiReportApi
  // =========================================================================
  group('AiReportApi', () {
    test('POST /api/app/ai/report avec reason + comment + consultation_id, '
        'jamais de message_id inventé', () async {
      http.Request? seen;
      Map<String, dynamic>? body;
      final api = AiReportApi(
        _client((req) async {
          seen = req;
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'status': 'ok'});
        }),
      );

      await api.report(
        bearer: 'tok',
        reason: AiReportReason.unsafe,
        consultationId: 'c-1',
        comment: '  ça me dérange ',
      );

      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/app/ai/report');
      expect(seen!.headers['Authorization'], 'Bearer tok');
      expect(body, {
        'reason': 'unsafe',
        'consultation_id': 'c-1',
        'comment': 'ça me dérange',
      });
      expect(body!.containsKey('message_id'), isFalse);
    });

    test('commentaire vide -> clé comment absente', () async {
      Map<String, dynamic>? body;
      final api = AiReportApi(
        _client((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({});
        }),
      );
      await api.report(
        bearer: 't',
        reason: AiReportReason.other,
        comment: '   ',
      );
      expect(body!.containsKey('comment'), isFalse);
      expect(body!['reason'], 'other');
    });

    test('erreur serveur -> exception propagée (pas de faux succès)', () async {
      final api = AiReportApi(_client((_) async => _json({'error': 'x'}, 500)));
      await expectLater(
        api.report(bearer: 't', reason: AiReportReason.misleading),
        throwsA(isA<ApiException>()),
      );
    });

    test('les 4 raisons ont un libellé et une valeur wire distincts', () {
      expect(AiReportReason.values.length, 4);
      expect(AiReportReason.values.map((r) => r.wire).toSet().length, 4);
      expect(AiReportReason.values.map((r) => r.label).toSet(), {
        'Réponse inappropriée',
        'Réponse dangereuse',
        'Réponse trompeuse',
        'Autre',
      });
    });
  });

  // =========================================================================
  // AccountApi + ApiClient.deleteJson
  // =========================================================================
  group('AccountApi', () {
    test(
      'DELETE /api/app/account authentifié, 200 -> pas d\'exception',
      () async {
        http.Request? seen;
        final api = AccountApi(
          _client((req) async {
            seen = req;
            return _json({'status': 'deleted'});
          }),
        );
        await api.deleteAccount('tok');
        expect(seen!.method, 'DELETE');
        expect(seen!.url.path, '/api/app/account');
        expect(seen!.headers['Authorization'], 'Bearer tok');
      },
    );

    test('204 corps vide -> accepté', () async {
      final api = AccountApi(_client((_) async => http.Response('', 204)));
      await api.deleteAccount('tok');
    });

    test('401 -> ApiUnauthorizedException', () async {
      final api = AccountApi(
        _client((_) async => _json({'error': 'unauthorized'}, 401)),
      );
      await expectLater(
        api.deleteAccount('tok'),
        throwsA(isA<ApiUnauthorizedException>()),
      );
    });

    test('500 -> ApiException', () async {
      final api = AccountApi(_client((_) async => _json({}, 500)));
      await expectLater(api.deleteAccount('tok'), throwsA(isA<ApiException>()));
    });
  });

  // =========================================================================
  // RewardsApi + ShareProgress
  // =========================================================================
  group('RewardsApi / ShareProgress', () {
    test('POST daily-share -> ShareProgress parsé (non crédité)', () async {
      http.Request? seen;
      final api = RewardsApi(
        _client((req) async {
          seen = req;
          return _json({
            'count': 12,
            'target': 30,
            'credited': false,
            'credited_seconds': 0,
          });
        }),
      );
      final p = await api.recordDailyShare('tok');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/app/rewards/daily-share');
      expect(p.count, 12);
      expect(p.target, 30);
      expect(p.credited, isFalse);
      expect(p.creditedSeconds, 0);
    });

    test('palier atteint -> credited true + 3600', () async {
      final api = RewardsApi(
        _client(
          (_) async => _json({
            'count': 30,
            'target': 30,
            'credited': true,
            'credited_seconds': 3600,
          }),
        ),
      );
      final p = await api.recordDailyShare('tok');
      expect(p.credited, isTrue);
      expect(p.creditedSeconds, 3600);
    });

    test('target absent -> défaut 30', () {
      final p = ShareProgress.fromJson({'count': 3});
      expect(p.target, 30);
      expect(p.credited, isFalse);
    });

    test('GET share-progress', () async {
      http.Request? seen;
      final api = RewardsApi(
        _client((req) async {
          seen = req;
          return _json({'count': 5, 'target': 30});
        }),
      );
      final p = await api.getShareProgress('tok');
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/api/app/rewards/share-progress');
      expect(p.count, 5);
    });
  });

  // =========================================================================
  // ShareRewardRepository — mode dégradé, jamais d'exception
  // =========================================================================
  group('ShareRewardRepository', () {
    test(
      'api null -> recordShare renvoie null (cache local non autoritaire)',
      () async {
        final repo = ShareRewardRepository(
          api: null,
          tokenProvider: () async => 'tok',
        );
        expect(repo.available, isFalse);
        expect(await repo.recordShare(), isNull);
        expect(await repo.loadProgress(), isNull);
      },
    );

    test('backend en erreur -> null, aucune exception remontée', () async {
      final repo = ShareRewardRepository(
        api: RewardsApi(_client((_) async => _json({}, 503))),
        tokenProvider: () async => 'tok',
      );
      expect(await repo.recordShare(), isNull);
    });

    test('token absent -> null', () async {
      final repo = ShareRewardRepository(
        api: RewardsApi(_client((_) async => _json({'count': 1}))),
        tokenProvider: () async => null,
      );
      expect(await repo.recordShare(), isNull);
    });

    test('succès -> ShareProgress renvoyé', () async {
      final repo = ShareRewardRepository(
        api: RewardsApi(
          _client(
            (_) async => _json({
              'count': 30,
              'target': 30,
              'credited': true,
              'credited_seconds': 3600,
            }),
          ),
        ),
        tokenProvider: () async => 'tok',
      );
      final p = await repo.recordShare();
      expect(p!.credited, isTrue);
    });
  });

  // =========================================================================
  // LocalUserData — séparation personnel / appareil
  // =========================================================================
  group('LocalUserData.clearPersonal', () {
    test(
      'supprime les clés personnelles, conserve la préférence appareil',
      () async {
        SharedPreferences.setMockInitialValues({
          'auryel.daily_mission.tirage': '2026-09-06',
          'auryel.daily_mission.moment': '2026-09-06',
          'auryel.daily_share.days': ['2026-09-01', '2026-09-02'],
          'auryel.daily_like.message.days': ['2026-09-01'],
          'auryel.daily_like.tarot.days': ['2026-09-01'],
          'auryel.memory.games_completed': 4,
          'auryel.memory.best_ms.facile': 42000,
          'auryel.memory.played.facile': true,
          'auryel.experience_intro_seen.v1': true,
          'auryel.intro_video_seen.v1': true,
          'auryel.shop_cart.v1': '{}',
          // conservée :
          'auryel.consultation.audio_muted.v1': true,
        });
        await LocalUserData().clearPersonal();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {'auryel.consultation.audio_muted.v1'});
        expect(prefs.getBool('auryel.consultation.audio_muted.v1'), isTrue);
      },
    );

    test('idempotent sur un store déjà vide', () async {
      await LocalUserData().clearPersonal();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });

  // =========================================================================
  // AuthController.deleteAccount — ordre strict
  // =========================================================================
  group('AuthController.deleteAccount', () {
    AuthController build(
      Future<http.Response> Function(http.Request) handler, {
      String? token = 'tok',
      bool withApi = true,
    }) {
      final client = _client(handler);
      final tokens = InMemoryTokenStore(token);
      return AuthController(
        repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
        profileApi: ProfileApi(client),
        consultationApi: ConsultationApi(client),
        tirageApi: TirageApi(client),
        accountApi: withApi ? AccountApi(client) : null,
        localUserData: LocalUserData(),
      );
    }

    test('pas d\'AccountApi -> unavailable, rien touché', () async {
      final c = build((_) async => _json({}), withApi: false);
      expect(await c.deleteAccount(), AccountDeletionOutcome.unavailable);
      expect(await c.currentToken(), 'tok');
    });

    test(
      'succès serveur -> token purgé + données locales purgées + signedOut',
      () async {
        SharedPreferences.setMockInitialValues({
          'auryel.daily_mission.tirage': '2026-09-06',
          'auryel.consultation.audio_muted.v1': true,
        });
        final c = build((req) async {
          expect(req.method, 'DELETE');
          return _json({'status': 'ok'});
        });
        final out = await c.deleteAccount();
        expect(out, AccountDeletionOutcome.ok);
        expect(await c.currentToken(), isNull);
        expect(c.status, AuthStatus.signedOut);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {'auryel.consultation.audio_muted.v1'});
      },
    );

    test('réseau KO -> retryable, session CONSERVÉE, rien purgé', () async {
      SharedPreferences.setMockInitialValues({
        'auryel.daily_mission.tirage': '2026-09-06',
      });
      final c = build((_) async => throw http.ClientException('boom'));
      final out = await c.deleteAccount();
      expect(out, AccountDeletionOutcome.retryable);
      expect(await c.currentToken(), 'tok');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), contains('auryel.daily_mission.tirage'));
    });

    test('5xx -> retryable, session conservée', () async {
      final c = build((_) async => _json({}, 500));
      expect(await c.deleteAccount(), AccountDeletionOutcome.retryable);
      expect(await c.currentToken(), 'tok');
    });

    test('401 -> unauthorized, jeton mort purgé, sessionExpired', () async {
      final c = build((_) async => _json({'error': 'unauthorized'}, 401));
      expect(await c.deleteAccount(), AccountDeletionOutcome.unauthorized);
      expect(await c.currentToken(), isNull);
      expect(c.status, AuthStatus.sessionExpired);
    });

    test('aucun jeton -> unauthorized sans appel', () async {
      var called = false;
      final c = build((_) async {
        called = true;
        return _json({});
      }, token: null);
      expect(await c.deleteAccount(), AccountDeletionOutcome.unauthorized);
      expect(called, isFalse);
    });
  });
}

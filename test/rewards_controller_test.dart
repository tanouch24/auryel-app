import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/state/rewards_controller.dart';

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 2/5) — RewardsController : source d'état
// PARTAGÉE (header Accueil + écran Wallet). Le serveur reste l'unique
// autorité — le contrôleur ne fait que PRÉSENTER `GET /wallet`, jamais
// recalculer de solde.
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

RewardsController _rig(
  Future<http.Response> Function(http.Request req) handler, {
  List<String>? hits,
}) {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      hits?.add('${req.method} ${req.url.path}');
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  return RewardsController(
    api: RewardsApi(client),
    tokenProvider: () async => 'tok',
  );
}

void main() {
  group('RewardsController.refresh', () {
    test('loading=true jusqu\'au 1er chargement abouti', () {
      final c = _rig((_) async => _json({'stars_balance': 0}));
      expect(c.loading, isTrue);
      expect(c.wallet, isNull);
      addTearDown(c.dispose);
    });

    test('charge le wallet et notifie', () async {
      final c = _rig(
        (_) async => _json({
          'stars_balance': 42,
          'rules': [
            {'rule_key': 'wake_completed', 'stars_amount': 5},
          ],
          'streak': {
            'current_streak': 2,
            'best_streak': 2,
            'next_reward_in_days': 5,
          },
          'recent_transactions': [],
        }),
      );
      addTearDown(c.dispose);
      var notified = false;
      c.addListener(() => notified = true);

      await c.refresh();

      expect(notified, isTrue);
      expect(c.loading, isFalse);
      expect(c.starsBalance, 42);
      expect(c.rules, hasLength(1));
      expect(c.streak.currentStreak, 2);
      expect(c.error, isNull);
    });

    test('erreur réseau : dernier wallet connu CONSERVÉ, jamais remis à 0', () async {
      var first = true;
      final c = _rig((_) async {
        if (first) {
          first = false;
          return _json({'stars_balance': 99, 'rules': [], 'recent_transactions': []});
        }
        return http.Response('boom', 500);
      });
      addTearDown(c.dispose);

      await c.refresh();
      expect(c.starsBalance, 99);

      await c.refresh();
      expect(c.starsBalance, 99, reason: 'échec réseau -> dernier wallet connu conservé');
      expect(c.error, isNotNull);
    });

    test('sans token (déconnecté) -> ne fait aucun appel réseau', () async {
      final hits = <String>[];
      final client = ApiClient(
        httpClient: MockClient((req) async {
          hits.add('${req.method} ${req.url.path}');
          return _json({'stars_balance': 0});
        }),
        baseUrl: 'http://test.local',
      );
      final c = RewardsController(
        api: RewardsApi(client),
        tokenProvider: () async => null,
      );
      addTearDown(c.dispose);

      await c.refresh();
      expect(hits, isEmpty);
    });
  });

  group('RewardsController.claim', () {
    test('awarded=true -> solde optimiste immédiat PUIS confirmé par un '
        'refresh serveur', () async {
      final hits = <String>[];
      var claimCalled = false;
      final c = _rig((req) async {
        if (req.url.path == '/api/app/rewards/claim') {
          claimCalled = true;
          return _json({
            'awarded': true,
            'reason': null,
            'stars_awarded': 5,
            'new_balance': 5,
          });
        }
        // GET /wallet — confirme le solde serveur après le claim.
        return _json({'stars_balance': 5, 'rules': [], 'recent_transactions': []});
      }, hits: hits);
      addTearDown(c.dispose);
      await c.refresh(); // état initial : wallet = 0

      final result = await c.claim('wake_completed');

      expect(claimCalled, isTrue);
      expect(result, isNotNull);
      expect(result!.awarded, isTrue);
      // Le solde reflète immédiatement le résultat du claim (optimiste)...
      expect(c.starsBalance, 5);
      // ... et un refresh a bien été déclenché derrière (fire-and-forget).
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(hits.where((h) => h == 'GET /api/app/rewards/wallet').length, 2);
    });

    test('awarded=false (déjà réclamé) -> solde INCHANGÉ, aucune erreur '
        'levée', () async {
      final c = _rig((req) async {
        if (req.url.path == '/api/app/rewards/claim') {
          return _json({
            'awarded': false,
            'reason': 'daily_limit_reached',
            'stars_awarded': 0,
            'new_balance': 5,
          });
        }
        return _json({'stars_balance': 5, 'rules': [], 'recent_transactions': []});
      });
      addTearDown(c.dispose);
      await c.refresh();

      final result = await c.claim('wake_completed');

      expect(result!.awarded, isFalse);
      expect(c.starsBalance, 5, reason: 'awarded=false ne modifie jamais le solde affiché');
    });

    test('échec réseau -> renvoie null, jamais d\'exception non rattrapée', () async {
      final c = _rig((_) async => http.Response('boom', 500));
      addTearDown(c.dispose);
      final result = await c.claim('wake_completed');
      expect(result, isNull);
    });
  });
}

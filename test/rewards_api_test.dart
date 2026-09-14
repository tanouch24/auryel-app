import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 2/5) — ÉTOILES : parsing du contrat
// GET /api/app/rewards/wallet + POST /api/app/rewards/claim. Le serveur
// reste l'unique source de vérité : ces tests vérifient uniquement que
// Flutter LIT correctement la réponse, jamais qu'il recalcule quoi que ce
// soit localement.
// ===========================================================================

void main() {
  group('RewardWallet.fromJson', () {
    test('parse un wallet complet', () {
      final wallet = RewardWallet.fromJson({
        'stars_balance': 340,
        'rules': [
          {'rule_key': 'wake_completed', 'stars_amount': 5},
          {'rule_key': 'meditation_completed', 'stars_amount': 10},
        ],
        'streak': {
          'current_streak': 4,
          'best_streak': 9,
          'next_reward_in_days': 3,
        },
        'recent_transactions': [
          {
            'delta_stars': 10,
            'balance_after': 340,
            'reason': 'meditation_completed',
            'created_at': '2026-09-09T10:00:00Z',
          },
        ],
      });

      expect(wallet.starsBalance, 340);
      expect(wallet.rules, hasLength(2));
      expect(wallet.rules.first.ruleKey, 'wake_completed');
      expect(wallet.rules.first.starsAmount, 5);
      expect(wallet.streak.currentStreak, 4);
      expect(wallet.streak.bestStreak, 9);
      expect(wallet.streak.nextRewardInDays, 3);
      expect(wallet.recentTransactions, hasLength(1));
      expect(wallet.recentTransactions.first.deltaStars, 10);
      expect(wallet.recentTransactions.first.balanceAfter, 340);
      expect(wallet.recentTransactions.first.reason, 'meditation_completed');
      expect(wallet.recentTransactions.first.createdAt, isNotNull);
    });

    test('champs manquants -> valeurs neutres, jamais un crash', () {
      final wallet = RewardWallet.fromJson(const {});
      expect(wallet.starsBalance, 0);
      expect(wallet.rules, isEmpty);
      expect(wallet.streak.currentStreak, 0);
      expect(wallet.streak.nextRewardInDays, 7);
      expect(wallet.recentTransactions, isEmpty);
    });

    test('wallet.empty ne fabrique aucun solde', () {
      expect(RewardWallet.empty.starsBalance, 0);
      expect(RewardWallet.empty.rules, isEmpty);
    });

    test('une règle future désactivée absente du JSON reste absente côté '
        'Flutter (le serveur ne l\'envoie jamais)', () {
      final wallet = RewardWallet.fromJson({
        'stars_balance': 0,
        'rules': [
          {'rule_key': 'wake_completed', 'stars_amount': 5},
        ],
      });
      expect(
        wallet.rules.map((r) => r.ruleKey),
        isNot(contains('mini_game_completed')),
      );
    });
  });

  group('RewardClaimResult.fromJson', () {
    test('awarded=true', () {
      final r = RewardClaimResult.fromJson({
        'awarded': true,
        'reason': null,
        'stars_awarded': 5,
        'new_balance': 5,
      });
      expect(r.awarded, isTrue);
      expect(r.reason, isNull);
      expect(r.starsAwarded, 5);
      expect(r.newBalance, 5);
    });

    test('awarded=false n\'est PAS une erreur (ex. déjà réclamé)', () {
      final r = RewardClaimResult.fromJson({
        'awarded': false,
        'reason': 'daily_limit_reached',
        'stars_awarded': 0,
        'new_balance': 5,
      });
      expect(r.awarded, isFalse);
      expect(r.reason, 'daily_limit_reached');
      expect(r.newBalance, 5);
    });
  });

  group('RewardsApi', () {
    http.Response jsonResp(Map<String, dynamic> b, [int s = 200]) =>
        http.Response(
          jsonEncode(b),
          s,
          headers: {'content-type': 'application/json'},
        );

    test('getWallet appelle GET /api/app/rewards/wallet avec le Bearer', () async {
      String? seenPath;
      String? seenAuth;
      final client = ApiClient(
        httpClient: MockClient((req) async {
          seenPath = req.url.path;
          seenAuth = req.headers['Authorization'];
          return jsonResp({'stars_balance': 12, 'rules': [], 'recent_transactions': []});
        }),
        baseUrl: 'http://test.local',
      );
      final wallet = await RewardsApi(client).getWallet('tok-abc');
      expect(seenPath, '/api/app/rewards/wallet');
      expect(seenAuth, 'Bearer tok-abc');
      expect(wallet.starsBalance, 12);
    });

    test('claimAction poste { action_key } et rien d\'autre — AUCUN montant '
        'n\'est jamais envoyé par Flutter', () async {
      Map<String, dynamic>? sentBody;
      String? seenPath;
      final client = ApiClient(
        httpClient: MockClient((req) async {
          seenPath = req.url.path;
          sentBody = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResp({
            'awarded': true,
            'reason': null,
            'stars_awarded': 5,
            'new_balance': 5,
          });
        }),
        baseUrl: 'http://test.local',
      );
      final result = await RewardsApi(
        client,
      ).claimAction(bearer: 'tok', actionKey: 'wake_completed');

      expect(seenPath, '/api/app/rewards/claim');
      expect(sentBody, {'action_key': 'wake_completed'});
      expect(sentBody!.containsKey('stars_amount'), isFalse);
      expect(sentBody!.containsKey('amount'), isFalse);
      expect(result.awarded, isTrue);
      expect(result.starsAwarded, 5);
    });

    test('getWallet propage une erreur réseau (jamais un solde inventé)', () async {
      final client = ApiClient(
        httpClient: MockClient((req) async => http.Response('boom', 500)),
        baseUrl: 'http://test.local',
      );
      expect(
        () => RewardsApi(client).getWallet('tok'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

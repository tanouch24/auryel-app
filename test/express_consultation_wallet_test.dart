import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/state/rewards_controller.dart';

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 3/5) — CONSULTATION EXPRESS, section « Utiliser
// mes Étoiles » de l'écran Wallet. Coût/durée TOUJOURS résolus serveur —
// jamais un montant en dur côté Flutter. Confirmation obligatoire (jamais un
// achat en un seul tap).
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _walletJson({
  int stars = 1000,
  List<Map<String, dynamic>>? expressProducts,
}) => {
  'stars_balance': stars,
  'rules': [],
  'streak': {'current_streak': 0, 'best_streak': 0, 'next_reward_in_days': 7},
  'recent_transactions': [],
  'express_products':
      expressProducts ??
      [
        {
          'product_key': 'express_consultation_10min',
          'stars_cost': 500,
          'seconds_granted': 600,
        },
      ],
};

RewardsController _rewards(
  Future<http.Response> Function(http.Request req) handler,
) {
  final client = ApiClient(
    httpClient: MockClient(handler),
    baseUrl: 'http://test.local',
  );
  return RewardsController(
    api: RewardsApi(client),
    tokenProvider: () async => 'tok',
  );
}

Widget _host(RewardsController rewards) =>
    MaterialApp(home: RewardsWalletScreen(controller: rewards));

void main() {
  testWidgets('affiche le coût/durée résolus serveur, jamais en dur', (
    t,
  ) async {
    final rewards = _rewards((_) async => _json(_walletJson(stars: 1000)));
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('UTILISER MES ÉTOILES'), findsOneWidget);
    expect(find.text('Consultation express'), findsOneWidget);
    expect(find.text('10 min de consultation'), findsOneWidget);
    expect(find.text('500 ⭐'), findsOneWidget);
    expect(find.text('Débloquer 10 min'), findsOneWidget);
  });

  testWidgets('sans produit express actif -> section absente', (t) async {
    final rewards = _rewards(
      (_) async => _json(_walletJson(stars: 1000, expressProducts: [])),
    );
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(find.text('UTILISER MES ÉTOILES'), findsNothing);
  });

  testWidgets('solde insuffisant -> bouton désactivé + "Il te manque X ⭐"', (
    t,
  ) async {
    final rewards = _rewards((_) async => _json(_walletJson(stars: 200)));
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(find.text('Il te manque 300 ⭐'), findsOneWidget);
    final button = t.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Débloquer 10 min'),
    );
    expect(button.onPressed, isNull, reason: 'bouton désactivé, solde insuffisant');
  });

  testWidgets('tap -> modal de confirmation, PAS un achat direct en un tap', (
    t,
  ) async {
    var purchaseCalled = false;
    final rewards = _rewards((req) async {
      if (req.url.path.endsWith('/express-consultation')) {
        purchaseCalled = true;
        return _json({
          'success': true,
          'stars_spent': 500,
          'stars_balance': 500,
          'seconds_granted': 600,
          'balances': {},
        });
      }
      return _json(_walletJson(stars: 1000));
    });
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Débloquer 10 min'));
    await t.pumpAndSettle();

    expect(purchaseCalled, isFalse, reason: 'le tap initial ouvre une confirmation');
    expect(
      find.text('Débloquer 10 minutes de consultation pour 500 ⭐ ?'),
      findsOneWidget,
    );
    expect(find.text('Solde actuel'), findsOneWidget);
    expect(find.text('1000 ⭐'), findsOneWidget);
    expect(find.text('Solde après achat'), findsOneWidget);
    expect(find.text('500 ⭐'), findsWidgets); // coût ET solde après achat
    expect(find.text('Confirmer'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
  });

  testWidgets('Annuler -> aucun appel réseau d\'achat', (t) async {
    var purchaseCalled = false;
    final rewards = _rewards((req) async {
      if (req.url.path.endsWith('/express-consultation')) {
        purchaseCalled = true;
      }
      return _json(_walletJson(stars: 1000));
    });
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Débloquer 10 min'));
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();

    expect(purchaseCalled, isFalse);
    expect(find.text('Confirmer'), findsNothing);
  });

  testWidgets('Confirmer -> achat, feedback +10 min + nouveau solde', (
    t,
  ) async {
    final hits = <String>[];
    Map<String, dynamic>? sentBody;
    var balance = 1000;
    final rewards = _rewards((req) async {
      hits.add(req.url.path);
      if (req.url.path.endsWith('/express-consultation')) {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        balance = 500;
        return _json({
          'success': true,
          'stars_spent': 500,
          'stars_balance': 500,
          'seconds_granted': 600,
          'balances': {},
        });
      }
      return _json(_walletJson(stars: balance));
    });
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Débloquer 10 min'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmer'));
    await t.pumpAndSettle();

    // AUCUN montant/coût/durée envoyé par le client.
    expect(sentBody, isNotNull);
    expect(sentBody!.keys.toSet(), {'product_key', 'idempotency_key'});
    expect(sentBody!['product_key'], 'express_consultation_10min');

    expect(find.text('+10 min de consultation'), findsOneWidget);
    expect(find.text('Nouveau solde : 500 ⭐'), findsOneWidget);
  });

  testWidgets('échec réseau sur confirmation -> message, retry possible', (
    t,
  ) async {
    var attempt = 0;
    final rewards = _rewards((req) async {
      if (req.url.path.endsWith('/express-consultation')) {
        attempt++;
        if (attempt == 1) return http.Response('boom', 500);
        return _json({
          'success': true,
          'stars_spent': 500,
          'stars_balance': 500,
          'seconds_granted': 600,
          'balances': {},
        });
      }
      return _json(_walletJson(stars: 1000));
    });
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Débloquer 10 min'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmer'));
    await t.pumpAndSettle();

    expect(find.text('Connexion impossible — réessaie.'), findsOneWidget);
    expect(find.text('Confirmer'), findsOneWidget); // toujours là, retry possible

    await t.tap(find.text('Confirmer'));
    await t.pumpAndSettle();
    expect(find.text('+10 min de consultation'), findsOneWidget);
    expect(attempt, 2);
  });
}

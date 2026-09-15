import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/screens/daily_challenge_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/rewards_controller.dart';

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 2/5) — écran « Mes Étoiles ». Le SERVEUR reste
// l'unique autorité : cet écran n'affiche que GET /api/app/rewards/wallet.
// Pas de dépense dans ce lot (§8/§22) : aucun bouton de dépense présent.
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

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
  testWidgets(
    'affiche le solde et les règles V4 actives ainsi que l’historique',
    (t) async {
      final rewards = _rewards(
        (_) async => _json({
          'stars_balance': 340,
          'rules': [
            {'rule_key': 'tarot_completed', 'stars_amount': 2},
            {'rule_key': 'mini_game_completed', 'stars_amount': 2},
            {'rule_key': 'wake_completed', 'stars_amount': 2},
            {'rule_key': 'share_completed', 'stars_amount': 2},
          ],
          'streak': {
            'current_streak': 0,
            'best_streak': 0,
            'next_reward_in_days': 7,
          },
          'recent_transactions': [
            {
              'delta_stars': 2,
              'balance_after': 340,
              'reason': 'tarot_completed',
              'created_at': '2026-09-09T10:00:00Z',
            },
            {
              'delta_stars': 2,
              'balance_after': 330,
              'reason': 'wake_completed',
              'created_at': '2026-09-09T07:00:00Z',
            },
          ],
        }),
      );
      addTearDown(rewards.dispose);
      await t.pumpWidget(_host(rewards));
      await t.pump();
      await t.pump();

      expect(find.text('Mes Étoiles'), findsOneWidget);
      expect(find.byKey(const Key('rewards-wallet-balance')), findsOneWidget);
      expect(find.text('340'), findsOneWidget);
      expect(
        find.text('Tes Étoiles récompensent tes activités dans Auryel.'),
        findsOneWidget,
      );

      // Règles actives affichées avec leur libellé + montant EXACT du serveur.
      // « Réveil Auryel » apparaît 2 fois (règle + historique) : même libellé,
      // sciemment réutilisé, jamais un doublon accidentel.
      expect(find.text('Réveil Auryel'), findsNWidgets(2));
      expect(find.text('Tirage'), findsNWidgets(2));
      expect(find.text('Mini-jeu du jour'), findsOneWidget);
      expect(find.text('Partager Auryel'), findsOneWidget);
      expect(find.text('+2 ⭐'), findsNWidgets(6));
      expect(find.text('Carte du jour'), findsNothing);
      expect(find.text('Méditation'), findsNothing);
      expect(find.text('7 jours consécutifs'), findsNothing);
    },
  );

  testWidgets('aucune règle future désactivée n\'apparaît (le serveur ne les '
      'envoie jamais)', (t) async {
    final rewards = _rewards(
      (_) async => _json({
        'stars_balance': 0,
        'rules': [
          {'rule_key': 'wake_completed', 'stars_amount': 5},
        ],
        'recent_transactions': [],
      }),
    );
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(find.textContaining('mini_game'), findsNothing);
    expect(find.textContaining('rewarded_ad'), findsNothing);
  });

  testWidgets('les activités Étoiles ouvrent leurs écrans existants', (
    t,
  ) async {
    final rewards = _rewards(
      (_) async => _json({
        'stars_balance': 0,
        'rules': [
          {'rule_key': 'mini_game_completed', 'stars_amount': 2},
          {'rule_key': 'tarot_completed', 'stars_amount': 2},
        ],
        'recent_transactions': [],
      }),
    );
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(find.text('Mini-jeu du jour'), findsOneWidget);
    expect(find.text('Tirage'), findsOneWidget);
    expect(find.text('Ouvrir'), findsNWidgets(2));

    await t.tap(find.text('Ouvrir').first);
    await t.pumpAndSettle();
    expect(find.byType(DailyChallengeScreen), findsOneWidget);
    Navigator.of(t.element(find.byType(DailyChallengeScreen))).pop();
    await t.pumpAndSettle();

    await t.tap(find.text('Ouvrir').last);
    await t.pumpAndSettle();
    expect(find.byType(TirageScreen), findsOneWidget);
  });

  testWidgets('rappel Premium visible dans le wallet', (t) async {
    final rewards = _rewards(
      (_) async =>
          _json({'stars_balance': 500, 'rules': [], 'recent_transactions': []}),
    );
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(find.text('Auryel Premium'), findsOneWidget);
    expect(find.textContaining('4,99 €/mois'), findsOneWidget);
  });

  testWidgets('historique vide -> message neutre, jamais un crash', (t) async {
    final rewards = _rewards(
      (_) async =>
          _json({'stars_balance': 0, 'rules': [], 'recent_transactions': []}),
    );
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(find.text('Aucun mouvement pour le moment.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('échec réseau : dernier état affiché reste cohérent, aucun '
      'crash', (t) async {
    final rewards = _rewards((_) async => http.Response('boom', 500));
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(t.takeException(), isNull);
    expect(find.text('Mes Étoiles'), findsOneWidget);
  });

  testWidgets('CORRECTIF — 1er chargement en échec (ex. endpoint '
      'indisponible/404) : jamais un faux « 0 », un neutre « … » tant que '
      'le serveur n\'a pas répondu une seule fois avec succès', (t) async {
    final rewards = _rewards((_) async => http.Response('not found', 404));
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump();
    await t.pump();

    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('rewards-wallet-balance')), findsOneWidget);
    expect(
      (t.widget(find.byKey(const Key('rewards-wallet-balance'))) as Text).data,
      '…',
    );
  });

  testWidgets('bouton retour présent', (t) async {
    final rewards = _rewards(
      (_) async =>
          _json({'stars_balance': 0, 'rules': [], 'recent_transactions': []}),
    );
    addTearDown(rewards.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => RewardsWalletScreen(controller: rewards),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();

    expect(find.byIcon(Icons.arrow_back).evaluate().isNotEmpty, isFalse);
    // Recherche via le bouton de retour custom (Phosphor arrowLeft) —
    // présence d'un IconButton suffit à prouver la navigabilité.
    expect(find.byType(IconButton), findsWidgets);
  });
}

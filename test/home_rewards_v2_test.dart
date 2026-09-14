import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/rewards_controller.dart';

AuryelState _state() => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u',
    selectedAdvisor: 'Séléna',
    firstName: 'N',
    birthDate: DateTime(1994, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: true,
  ),
);

RewardsController _rewards() => RewardsController(
  api: RewardsApi(
    ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'stars_balance': 235,
            'rules': [
              {
                'rule_key': 'meditation_completed',
                'stars_amount': 10,
                'daily_limit': 1,
              },
            ],
            'recent_transactions': [],
            'express_products': [
              {
                'product_key': 'express_consultation_10min',
                'stars_cost': 400,
                'seconds_granted': 600,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      baseUrl: 'http://test.local',
    ),
  ),
  tokenProvider: () async => 'tok',
);

Widget _home(RewardsController rewards) => AuryelStateScope(
  state: _state(),
  child: RewardsScope(
    controller: rewards,
    child: const MaterialApp(home: HomeScreen()),
  ),
);

void main() {
  testWidgets('Home affiche les offres et aucune mission', (tester) async {
    final rewards = _rewards();
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await tester.pumpWidget(_home(rewards));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('home-stars-pill')), findsOneWidget);
    expect(find.text('DÉCOUVRE LES OFFRES DE CONSULTATION'), findsOneWidget);
    expect(find.text('Auryel Premium'), findsOneWidget);
    expect(find.text('4 h de consultation par mois'), findsOneWidget);
    expect(find.text('4,99 €/mois'), findsOneWidget);
    expect(find.text('Sans publicité'), findsOneWidget);
    expect(
      find.text('Gagne des minutes de consultation gratuitement'),
      findsOneWidget,
    );
    expect(find.text('TES MISSIONS DU JOUR'), findsNothing);
    expect(find.text('Pensée du jour'), findsNothing);
    expect(find.text('Carte du jour'), findsNothing);
  });

  testWidgets('La pilule ouvre le wallet avec le solde et les règles serveur', (
    tester,
  ) async {
    final rewards = _rewards();
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await tester.pumpWidget(_home(rewards));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('home-stars-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RewardsWalletScreen), findsOneWidget);
    expect(find.byKey(const Key('rewards-wallet-balance')), findsOneWidget);
    expect(
      (tester.widget(
        find.byKey(const Key('rewards-wallet-balance')),
      ) as Text).data,
      '235',
    );
    expect(find.textContaining('Plus que 165 ⭐'), findsOneWidget);
    expect(find.text('Méditation'), findsOneWidget);
    expect(find.text('+10 ⭐'), findsOneWidget);
  });
}

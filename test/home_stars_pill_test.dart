import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/rewards_controller.dart';

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 2/5) — pilule « ⭐ solde » à côté de « Mon
// compte » sur l'Accueil. Décision produit EXPLICITE (§6/§23) : visible,
// zone tactile confortable, solde RÉEL serveur (jamais un montant en dur).
// ===========================================================================

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

DailyThoughtRepository _repo() => DailyThoughtRepository(
  seed: [
    DailyThought(
      id: 1,
      publishDate: DateTime(2026, 9, 4),
      phrase: 'x',
      interpretation: 'x',
      imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
    ),
  ],
);

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

Widget _host(RewardsController? rewards) {
  final tree = AuryelStateScope(
    state: _state(),
    child: MaterialApp(home: HomeScreen(thoughtRepository: _repo())),
  );
  return rewards == null
      ? tree
      : RewardsScope(controller: rewards, child: tree);
}

void main() {
  testWidgets('sans RewardsScope câblé -> aucune pilule Étoiles (jamais un '
      'faux solde)', (t) async {
    await t.pumpWidget(_host(null));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('home-stars-pill')), findsNothing);
    // « Mon compte » reste présent, inchangé.
    expect(find.byKey(const Key('home-my-account-button')), findsOneWidget);
  });

  testWidgets('RewardsScope câblé mais wallet pas encore chargé -> pas de '
      'pilule tant que le solde réel n\'est pas connu (jamais « 0 »)', (
    t,
  ) async {
    final neverResolves = Completer<http.Response>();
    final rewards = _rewards((_) => neverResolves.future);
    addTearDown(rewards.dispose);
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('home-stars-pill')), findsNothing);
  });

  testWidgets('solde à 0 -> pilule affichée quand même (« 0 ⭐ », jamais '
      'masquée une fois le 1er chargement abouti)', (t) async {
    final rewards = _rewards(
      (_) async =>
          _json({'stars_balance': 0, 'rules': [], 'recent_transactions': []}),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('home-stars-pill')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('wallet chargé -> affiche le solde RÉEL du serveur', (t) async {
    final rewards = _rewards(
      (_) async => _json({
        'stars_balance': 340,
        'rules': [],
        'streak': {
          'current_streak': 0,
          'best_streak': 0,
          'next_reward_in_days': 7,
        },
        'recent_transactions': [],
      }),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('home-stars-pill')), findsOneWidget);
    expect(find.text('340'), findsOneWidget);
  });

  testWidgets('le compteur du header se met à jour dès que le contrôleur '
      'partagé notifie (même instance que le Wallet)', (t) async {
    var balance = 10;
    final rewards = _rewards(
      (_) async => _json({
        'stars_balance': balance,
        'rules': [],
        'recent_transactions': [],
      }),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('10'), findsOneWidget);

    balance = 25;
    await rewards.refresh();
    await t.pump();
    expect(find.text('25'), findsOneWidget);
    expect(find.text('10'), findsNothing);
  });

  testWidgets('tap sur la pilule Étoiles ouvre l\'écran « Mes Étoiles »', (
    t,
  ) async {
    final rewards = _rewards(
      (_) async =>
          _json({'stars_balance': 50, 'rules': [], 'recent_transactions': []}),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.byKey(const Key('home-stars-pill')));
    await t.pumpAndSettle();

    expect(find.byType(RewardsWalletScreen), findsOneWidget);
    expect(find.text('Mes Étoiles'), findsOneWidget);
  });

  testWidgets('grand solde (5 chiffres) -> aucun overflow, valeur affichée '
      'sans coupure (Samsung Galaxy A07)', (t) async {
    final rewards = _rewards(
      (_) async => _json({
        'stars_balance': 12345,
        'rules': [],
        'recent_transactions': [],
      }),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    t.view.physicalSize = const Size(720, 1600); // ~360dp @ 2.0 (Galaxy A07)
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));

    expect(find.text('12345'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('solde très grand (>= 100 000) -> compacté, jamais coupé', (
    t,
  ) async {
    final rewards = _rewards(
      (_) async => _json({
        'stars_balance': 1234567,
        'rules': [],
        'recent_transactions': [],
      }),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await t.pumpWidget(_host(rewards));
    await t.pump(const Duration(seconds: 1));

    expect(find.text('1.2M'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

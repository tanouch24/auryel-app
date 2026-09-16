import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/memory_api.dart';
import 'package:auryel/screens/daily_challenge_screen.dart';
import 'package:auryel/screens/hidden_card_screen.dart';
import 'package:auryel/screens/jeu_auryel_screen.dart';
import 'package:auryel/screens/sequence_recall_screen.dart';
import 'package:auryel/state/memory_rewards_controller.dart';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

MemoryRewardsController _controller({
  required bool eligibleToday,
  int starsReward = 15,
  String? nextResetAt,
}) {
  final api = MemoryApi(
    ApiClient(
      httpClient: MockClient(
        (_) async => _json({
          'eligible_today': eligibleToday,
          'stars_reward': starsReward,
          'next_reset_at': nextResetAt,
          'difficulties': [],
        }),
      ),
      baseUrl: 'http://test.local',
    ),
  );
  return MemoryRewardsController(api: api, tokenProvider: () async => 'tok');
}

Widget _host(MemoryRewardsController c) =>
    MaterialApp(home: DailyChallengeScreen(controller: c));

void main() {
  testWidgets('affiche les 3 jeux + la récompense du jour dynamique', (
    t,
  ) async {
    final c = _controller(eligibleToday: true, starsReward: 15);
    addTearDown(c.dispose);
    await t.pumpWidget(_host(c));
    await t.pump();
    await t.pump();

    expect(find.text('Défi du jour'), findsOneWidget);
    expect(find.text('Termine un mini-jeu aujourd’hui pour le plaisir.'), findsOneWidget);
    expect(find.text('Le Jeu Auryel'), findsOneWidget);
    expect(find.text('Suite intuitive'), findsOneWidget);
    expect(find.text('Carte cachée'), findsOneWidget);
    expect(find.textContaining('sans gain ni récompense'), findsOneWidget);
  });

  testWidgets('un ancien statut de récompense ne réapparaît pas dans les jeux', (t) async {
    final c = _controller(eligibleToday: false, starsReward: 15);
    addTearDown(c.dispose);
    await t.pumpWidget(_host(c));
    await t.pump();
    await t.pump();

    expect(find.text('Récompense du jour obtenue ✓'), findsNothing);
    // Les 3 jeux restent accessibles malgré la récompense déjà obtenue.
    expect(find.text('Le Jeu Auryel'), findsOneWidget);
    expect(find.text('Suite intuitive'), findsOneWidget);
    expect(find.text('Carte cachée'), findsOneWidget);
  });

  testWidgets('tap sur chaque jeu ouvre le bon écran', (t) async {
    final c = _controller(eligibleToday: true);
    addTearDown(c.dispose);
    await t.pumpWidget(_host(c));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Le Jeu Auryel'));
    await t.pumpAndSettle();
    expect(find.byType(JeuAuryelScreen), findsOneWidget);
  });

  testWidgets('tap sur Suite intuitive ouvre SequenceRecallScreen', (t) async {
    final c = _controller(eligibleToday: true);
    addTearDown(c.dispose);
    await t.pumpWidget(_host(c));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Suite intuitive'));
    await t.pumpAndSettle();
    expect(find.byType(SequenceRecallScreen), findsOneWidget);
  });

  testWidgets('tap sur Carte cachée ouvre HiddenCardScreen', (t) async {
    final c = _controller(eligibleToday: true);
    addTearDown(c.dispose);
    await t.pumpWidget(_host(c));
    await t.pump();
    await t.pump();

    await t.tap(find.text('Carte cachée'));
    await t.pumpAndSettle();
    expect(find.byType(HiddenCardScreen), findsOneWidget);
  });

  testWidgets('aucun vocabulaire casino / gain financier', (t) async {
    final c = _controller(eligibleToday: true);
    addTearDown(c.dispose);
    await t.pumpWidget(_host(c));
    await t.pump();
    await t.pump();

    expect(find.textContaining('jackpot'), findsNothing);
    expect(find.textContaining('coffre'), findsNothing);
    expect(find.textContaining('roue'), findsNothing);
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining('pari'), findsNothing);
  });
}

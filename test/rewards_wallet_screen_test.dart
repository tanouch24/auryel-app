import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/state/rewards_controller.dart';

RewardsController _controller(Map<String, dynamic> body, {int status = 200}) => RewardsController(
  api: RewardsApi(ApiClient(httpClient: MockClient((_) async => http.Response(
    jsonEncode(body), status, headers: {'content-type': 'application/json'},
  )), baseUrl: 'http://test.local')),
  tokenProvider: () async => 'tok',
);

void main() {
  testWidgets('affiche questions, progression et textes Rewarded', (t) async {
    final c = _controller({'questions_available': 4, 'progress': 9});
    addTearDown(c.dispose);
    await t.pumpWidget(MaterialApp(home: RewardsWalletScreen(controller: c)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Consultation gratuite'), findsOneWidget);
    expect(find.text('Questions disponibles'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('9/10 pubs vers +5 min'), findsOneWidget);
    expect(find.text('1 pub = 1 question'), findsOneWidget);
    expect(find.text('10 pubs = +5 min'), findsOneWidget);
  });

  testWidgets('échec réseau sans faux ancien solde', (t) async {
    final c = _controller({}, status: 500);
    addTearDown(c.dispose);
    await t.pumpWidget(MaterialApp(home: RewardsWalletScreen(controller: c)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Consultation gratuite'), findsOneWidget);
    expect(find.textContaining('Étoile'), findsNothing);
    expect(t.takeException(), isNull);
  });
}

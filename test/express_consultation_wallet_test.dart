import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/state/rewards_controller.dart';

void main() {
  testWidgets('l’ancien achat Express contre Stars n’est plus proposé', (t) async {
    final c = RewardsController(
      api: RewardsApi(ApiClient(httpClient: MockClient((_) async => http.Response(
        jsonEncode({'questions_available': 0, 'progress': 0}), 200,
        headers: {'content-type': 'application/json'},
      )), baseUrl: 'http://test.local')),
      tokenProvider: () async => 'tok',
    );
    addTearDown(c.dispose);
    await t.pumpWidget(MaterialApp(home: RewardsWalletScreen(controller: c)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Consultation gratuite'), findsOneWidget);
    expect(find.textContaining('Étoile'), findsNothing);
    expect(find.textContaining('Express'), findsNothing);
  });
}

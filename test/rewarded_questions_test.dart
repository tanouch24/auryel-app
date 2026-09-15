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
  test('Rewarded state parses questions and 0..9 progress from the server', () {
    final state = RewardWallet.fromJson({
      'questions_available': 3,
      'progress': 9,
      'total_rewarded': 19,
      'minutes_awarded': 5,
    });
    expect(state.questionsAvailable, 3);
    expect(state.rewardedProgress, 9);
    expect(state.totalRewarded, 19);
    expect(state.minutesAwarded, 5);
  });

  testWidgets('Consultation gratuite presents the Rewarded V1 copy', (
    tester,
  ) async {
    final client = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'questions_available': 3,
            'progress': 3,
            'total_rewarded': 3,
            'minutes_awarded': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      baseUrl: 'http://test.local',
    );
    final controller = RewardsController(
      api: RewardsApi(client),
      tokenProvider: () async => 'token',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RewardsWalletScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Consultation gratuite'), findsOneWidget);
    expect(find.text('Questions disponibles'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('3/10 pubs vers +5 min'), findsOneWidget);
    expect(find.text('1 pub = 1 question'), findsOneWidget);
    expect(find.text('10 pubs = +5 min'), findsOneWidget);
    expect(find.text('Mes Étoiles'), findsNothing);
  });
}

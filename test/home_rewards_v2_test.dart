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
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/rewards_controller.dart';

void main() {
  testWidgets('Accueil conserve Premium et la consultation gratuite', (t) async {
    final c = RewardsController(
      api: RewardsApi(ApiClient(httpClient: MockClient((_) async => http.Response(
        jsonEncode({'questions_available': 1, 'progress': 4}), 200,
        headers: {'content-type': 'application/json'},
      )), baseUrl: 'http://test.local')),
      tokenProvider: () async => 'tok',
    );
    addTearDown(c.dispose); await c.refresh();
    await t.pumpWidget(RewardsScope(controller: c, child: AuryelStateScope(
      state: AuryelState(repository: LocalOnboardingRepository(), initial: OnboardingRecord(
        userId: 'u', selectedAdvisor: 'Séléna', firstName: 'N', birthDate: DateTime(1994),
        portraitData: 'x', portraitFeedback: 'y', onboardingCompleted: true,
      )), child: const MaterialApp(home: HomeScreen()),
    )));
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('home-stars-pill')), findsOneWidget);
    expect(find.byKey(const Key('home-premium-offer')), findsOneWidget);
    expect(find.text('4 h de consultation par mois'), findsOneWidget);
    expect(find.text('4,99 €/mois'), findsOneWidget);
    expect(find.text('Sans publicité'), findsOneWidget);
    expect(find.textContaining('⭐'), findsNothing);
  });
}

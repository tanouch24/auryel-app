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

AuryelState _state() => AuryelState(repository: LocalOnboardingRepository(), initial: OnboardingRecord(
  userId: 'u', selectedAdvisor: 'Séléna', firstName: 'N', birthDate: DateTime(1994),
  portraitData: 'x', portraitFeedback: 'y', onboardingCompleted: true,
));
RewardsController _rewards(http.Response Function() response) => RewardsController(
  api: RewardsApi(ApiClient(httpClient: MockClient((_) async => response()), baseUrl: 'http://test.local')),
  tokenProvider: () async => 'tok',
);
Widget _host(RewardsController rewards) => RewardsScope(controller: rewards, child: AuryelStateScope(
  state: _state(), child: MaterialApp(home: HomeScreen(thoughtRepository: DailyThoughtRepository(seed: [
    DailyThought(id: 1, publishDate: DateTime(2026, 9, 4), phrase: 'x', interpretation: 'x', imageAsset: 'x'),
  ]))),
));
Map<String, dynamic> _payload({int questions = 3, int progress = 2}) => {
  'questions_available': questions, 'progress': progress, 'total_rewarded': 12, 'minutes_awarded': 5,
};

void main() {
  testWidgets('pilule consultation gratuite affiche les droits serveur', (t) async {
    final c = _rewards(() => http.Response(jsonEncode(_payload()), 200, headers: {'content-type': 'application/json'}));
    addTearDown(c.dispose); await c.refresh(); await t.pumpWidget(_host(c)); await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('home-stars-pill')), findsOneWidget);
    expect(find.text('3 questions'), findsOneWidget);
  });
  testWidgets('tap ouvre Consultation gratuite', (t) async {
    final c = _rewards(() => http.Response(jsonEncode(_payload()), 200, headers: {'content-type': 'application/json'}));
    addTearDown(c.dispose); await c.refresh(); await t.pumpWidget(_host(c)); await t.pump(const Duration(seconds: 1));
    await t.tap(find.byKey(const Key('home-stars-pill'))); await t.pumpAndSettle();
    expect(find.byType(RewardsWalletScreen), findsOneWidget);
    expect(find.text('Consultation gratuite'), findsOneWidget);
    expect(find.text('Questions disponibles'), findsOneWidget);
    expect(find.text('2/10 pubs vers +5 min'), findsOneWidget);
  });
  testWidgets('erreur serveur ne provoque pas de crash', (t) async {
    final c = _rewards(() => http.Response('error', 500));
    addTearDown(c.dispose); await c.refresh(); await t.pumpWidget(_host(c)); await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}

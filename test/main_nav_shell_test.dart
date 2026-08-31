import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/bibliotheque_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

AuryelState _state() => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u-1',
    selectedAdvisor: 'Maïa',
    firstName: 'Nina',
    birthDate: DateTime(1994, 1, 1),
    portraitData: 'texte',
    portraitFeedback: 'ok',
    onboardingCompleted: true,
  ),
);

AuthController _auth() {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/tirages') {
        return http.Response(
          jsonEncode({'tirages': <dynamic>[], 'next_cursor': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }),
    baseUrl: 'http://test.local',
  );
  return AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
}

Widget _wrap() => AuthScope(
  controller: _auth(),
  child: AuryelStateScope(
    state: _state(),
    child: const MaterialApp(home: MainNavShell()),
  ),
);

Finder _tab(String label) => find.widgetWithText(InkWell, label);

void main() {
  testWidgets('les 4 onglets sont présents, dans l\'ordre', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(_tab('Accueil'), findsOneWidget);
    expect(_tab('Tirage'), findsOneWidget);
    expect(_tab('Méditation'), findsOneWidget);
    expect(_tab('Bibliothèque'), findsOneWidget);
    // Pas d'onglet tableau de bord / Mon espace dans la barre.
    expect(_tab('Mon espace'), findsNothing);
    expect(_tab('Mes cartes'), findsNothing);
  });

  testWidgets('Accueil -> HomeScreen ; Tirage -> TirageScreen ; '
      'Méditation -> "Ton moment" ; Bibliothèque -> BibliothequeScreen ; '
      'retour Accueil', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Onglet initial : Accueil.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Découvrir le message du jour'), findsOneWidget);

    // Tirage.
    await tester.tap(_tab('Tirage'));
    await tester.pumpAndSettle();
    expect(find.byType(TirageScreen), findsOneWidget);
    expect(find.text('Ton tirage'), findsOneWidget);

    // Méditation (placeholder « Ton moment »).
    await tester.tap(_tab('Méditation'));
    await tester.pumpAndSettle();
    expect(find.text('Ton moment'), findsOneWidget);

    // Bibliothèque — écran réel (plus de PlaceholderScreen).
    await tester.tap(_tab('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(find.byType(BibliothequeScreen), findsOneWidget);
    expect(find.text('Mon parcours'), findsOneWidget);
    expect(
      find.text('Tes tirages et tes lectures, bientôt réunis ici.'),
      findsNothing,
    );

    // Retour Accueil.
    await tester.tap(_tab('Accueil'));
    await tester.pumpAndSettle();
    expect(find.text('Découvrir le message du jour'), findsOneWidget);
  });
}

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
import 'package:auryel/screens/consultation_screen.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/meditation_library_screen.dart';
import 'package:auryel/screens/tirage_jeu_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('nav V1 finale : 5 onglets Accueil · Tirage & Jeu · Consultation '
      '· Méditation · Mon compte (Consultation au centre)', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(_tab('Accueil'), findsOneWidget);
    expect(_tab('Tirage & Jeu'), findsOneWidget);
    expect(_tab('Consultation'), findsOneWidget);
    expect(_tab('Méditation'), findsOneWidget);
    expect(_tab('Mon compte'), findsOneWidget);
    // Boutique retirée de la bottom nav V1.
    expect(_tab('Boutique'), findsNothing);
    expect(_tab('Bibliothèque'), findsNothing);
    expect(_tab('Mon espace'), findsNothing);

    // Ordre visuel : Consultation au centre (index 2), Mon compte en dernier.
    final tirageX = tester.getCenter(_tab('Tirage & Jeu')).dx;
    final consultX = tester.getCenter(_tab('Consultation')).dx;
    final meditX = tester.getCenter(_tab('Méditation')).dx;
    final compteX = tester.getCenter(_tab('Mon compte')).dx;
    expect(consultX, greaterThan(tirageX));
    expect(meditX, greaterThan(consultX));
    expect(compteX, greaterThan(meditX));
  });

  testWidgets('Accueil -> HomeScreen ; Tirage & Jeu -> hub ; Consultation -> '
      'feed ; Méditation -> bibliothèque ; Mon compte -> Dashboard ; '
      'retour Accueil', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Onglet initial : Accueil.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('ESPACE PRIVÉ'), findsOneWidget);

    // Tirage & Jeu : ouvre le HUB, pas le TirageScreen directement.
    await tester.tap(_tab('Tirage & Jeu'));
    await tester.pumpAndSettle();
    expect(find.byType(TirageJeuScreen), findsOneWidget);
    expect(find.text('Le Jeu Auryel'), findsOneWidget);
    expect(find.byType(TirageScreen), findsNothing);

    // Consultation (J6-F2 : LISTE des discussions en cours).
    await tester.tap(_tab('Consultation'));
    await tester.pumpAndSettle();
    expect(find.byType(ConsultationScreen), findsOneWidget);
    expect(find.text('Consultations en cours'), findsOneWidget);

    // Méditation : la BIBLIOTHÈQUE (1 audio = 1 fiche ; le lecteur s'ouvre au tap).
    await tester.tap(_tab('Méditation'));
    await tester.pumpAndSettle();
    expect(find.byType(MeditationLibraryScreen), findsOneWidget);
    expect(find.text('Bibliothèque'), findsOneWidget);

    // Mon compte : réutilise le Dashboard existant (une seule implémentation).
    await tester.tap(_tab('Mon compte'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);

    // Retour Accueil.
    await tester.tap(_tab('Accueil'));
    await tester.pumpAndSettle();
    expect(find.text('ESPACE PRIVÉ'), findsOneWidget);
  });
}

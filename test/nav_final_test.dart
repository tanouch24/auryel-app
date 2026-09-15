import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// LOT « NAVIGATION FINALE + TIRAGE & JEU + MON COMPTE »
// Nav V1 : Accueil · Bien-être · CONSULTATION · Méditation · Mon compte.
// ===========================================================================

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

Widget _shell() => AuthScope(
  controller: _auth(),
  child: AuryelStateScope(
    state: _state(),
    child: const MaterialApp(home: MainNavShell()),
  ),
);

Widget _dashboard({bool showBackButton = true}) => AuthScope(
  controller: _auth(),
  child: AuryelStateScope(
    state: _state(),
    child: MaterialApp(home: DashboardScreen(showBackButton: showBackButton)),
  ),
);

// AUDIT ACCUEIL/PARCOURS — Accueil affiche désormais une mission « Consultation »
// (même libellé que le parcours bien-être serveur) : on restreint la
// recherche à la barre d'onglets elle-même (tous les onglets restent montés
// simultanément, IndexedStack).
Finder _tab(String label) => find.descendant(
  of: find.byKey(const Key('auryel-bottom-tab-bar')),
  matching: find.widgetWithText(InkWell, label),
);

Finder _backArrow() => find.byWidgetPredicate(
  (w) => w is PhosphorIcon && w.icon == PhosphorIconsRegular.arrowLeft,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // NAVIGATION (5 cas)
  // -------------------------------------------------------------------------
  group('Navigation V1', () {
    testWidgets('N1 — les 5 onglets finaux sont présents avec Boutique', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      expect(_tab('Accueil'), findsOneWidget);
      expect(_tab('Bien-être'), findsOneWidget);
      expect(_tab('Consultation'), findsOneWidget);
      expect(_tab('Boutique'), findsOneWidget);
      expect(_tab('Réveil'), findsOneWidget);
      expect(_tab('Méditation'), findsNothing);
      expect(_tab('Mon compte'), findsNothing);
    });

    testWidgets('N2 — CONSULTATION est au centre (index 2) entre Bien-être '
        'et Boutique', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      final xs = [
        t.getCenter(_tab('Accueil')).dx,
        t.getCenter(_tab('Bien-être')).dx,
        t.getCenter(_tab('Consultation')).dx,
        t.getCenter(_tab('Boutique')).dx,
        t.getCenter(_tab('Réveil')).dx,
      ];
      final sorted = [...xs]..sort();
      expect(xs, sorted, reason: 'ordre gauche→droite');
      // Consultation strictement au milieu des 5.
      expect(xs[2], sorted[2]);
    });

    testWidgets(
      'N3 — CONSULTATION mise en avant : icône centrale plus grande',
      (t) async {
        await t.pumpWidget(_shell());
        await t.pumpAndSettle();

        double iconSize(String label) =>
            t
                .widget<PhosphorIcon>(
                  find
                      .descendant(
                        of: _tab(label),
                        matching: find.byType(PhosphorIcon),
                      )
                      .first,
                )
                .size ??
            0;

        expect(
          iconSize('Consultation'),
          greaterThan(iconSize('Accueil')),
          reason: 'icône Consultation centrale plus grande',
        );
      },
    );

    testWidgets(
      'N4 — le bouton d\'en-tête « Mon compte » de l\'Accueil ouvre le '
      'Dashboard existant (pas de 2ᵉ implémentation, plus d\'onglet dédié)',
      (t) async {
        await t.pumpWidget(_shell());
        await t.pumpAndSettle();

        expect(find.byKey(const Key('home-my-account-button')), findsOneWidget);
        await t.tap(find.byKey(const Key('home-my-account-button')));
        await t.pumpAndSettle();
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.text('Mon espace'), findsOneWidget);
      },
    );

    testWidgets('N5 — Consultation reste montée quand on change d\'onglet '
        '(feed non détruit)', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      await t.tap(_tab('Consultation'));
      await t.pumpAndSettle();
      expect(find.byType(ConsultationScreen), findsOneWidget);

      await t.tap(_tab('Accueil'));
      await t.pumpAndSettle();
      // IndexedStack : l'écran Consultation reste monté (offstage), non détruit.
      expect(
        find.byType(ConsultationScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // HOME — les missions ne sont plus dans la Home (3 anciens cas remplacés)
  // -------------------------------------------------------------------------
  group('Home → espace commercial', () {
    testWidgets('H1 — aucune mission ancienne n\'est montée dans la Home', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      expect(find.text('TES MISSIONS DU JOUR'), findsNothing);
      expect(find.text('Carte du jour'), findsNothing);
      expect(find.text('Prends ton temps'), findsNothing);
      expect(find.byKey(const Key('home-premium-offer')), findsOneWidget);
      expect(
        find.text('Gagne des minutes de consultation gratuitement'),
        findsNothing,
      );
    });

    testWidgets('H2 — les onglets fonctionnels restent présents', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('auryel-bottom-tab-bar')), findsOneWidget);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('Bien-être'), findsOneWidget);
      expect(find.text('Boutique'), findsOneWidget);
      expect(find.text('Méditation'), findsNothing);
    });

    testWidgets('H3 — l\'accès consultation passe par l\'onglet dédié', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      await t.tap(find.text('Consultation').last);
      await t.pumpAndSettle();
      expect(find.byType(ConsultationScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // MON COMPTE (3 cas)
  // -------------------------------------------------------------------------
  group('Mon compte', () {
    testWidgets('MC1 — dans la bottom nav : pas de flèche retour ; '
        'poussé en secondaire : flèche retour présente', (t) async {
      await t.pumpWidget(_dashboard(showBackButton: false));
      await t.pumpAndSettle();
      expect(_backArrow(), findsNothing);

      await t.pumpWidget(_dashboard(showBackButton: true));
      await t.pumpAndSettle();
      expect(_backArrow(), findsOneWidget);
    });

    testWidgets('MC2 — déconnexion accessible', (t) async {
      await t.pumpWidget(_dashboard(showBackButton: false));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Se déconnecter'));
      expect(find.text('Se déconnecter'), findsOneWidget);
    });

    testWidgets('MC3 — espace compte nettoyé + suppression de compte présents', (t) async {
      await t.pumpWidget(_dashboard(showBackButton: false));
      await t.pumpAndSettle();

      expect(find.text('Voir ma consultation gratuite'), findsOneWidget);
      expect(find.text('Découvrir Auryel'), findsNothing);
      await t.ensureVisible(find.text('Supprimer mon compte'));
      expect(find.text('Supprimer mon compte'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // RESPONSIVE (3 cas) — 360 / 384 / 430 dp
  // -------------------------------------------------------------------------
  group('Responsive', () {
    for (final w in const [360.0, 384.0, 430.0]) {
      testWidgets('R — bottom nav + hub sans overflow à ${w.toInt()} dp', (
        t,
      ) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = Size(w, 820);
        addTearDown(t.view.reset);

        await t.pumpWidget(_shell());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'nav ${w.toInt()} dp');

        // Libellés longs lisibles / présents.
        expect(_tab('Bien-être'), findsOneWidget);
        expect(_tab('Réveil'), findsOneWidget);

        await t.tap(_tab('Bien-être'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'hub ${w.toInt()} dp');
        expect(find.text('Bien-être'), findsWidgets);
      });
    }
  });
}

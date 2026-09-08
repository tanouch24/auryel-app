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
import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/consultation_screen.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/jeu_auryel_screen.dart';
import 'package:auryel/screens/meditation_screen.dart';
import 'package:auryel/screens/tirage_jeu_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// LOT « NAVIGATION FINALE + TIRAGE & JEU + MON COMPTE »
// Nav V1 : Accueil · Tirage & Jeu · CONSULTATION · Méditation · Mon compte.
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

Finder _tab(String label) => find.widgetWithText(InkWell, label);

Finder _backArrow() => find.byWidgetPredicate(
  (w) => w is PhosphorIcon && w.icon == PhosphorIconsRegular.arrowLeft,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // NAVIGATION (5 cas)
  // -------------------------------------------------------------------------
  group('Navigation V1', () {
    testWidgets('N1 — les 5 onglets finaux sont présents, Boutique retirée', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      expect(_tab('Accueil'), findsOneWidget);
      expect(_tab('Tirage & Jeu'), findsOneWidget);
      expect(_tab('Consultation'), findsOneWidget);
      expect(_tab('Méditation'), findsOneWidget);
      expect(_tab('Mon compte'), findsOneWidget);
      expect(_tab('Boutique'), findsNothing);
    });

    testWidgets('N2 — CONSULTATION est au centre (index 2) entre Tirage & Jeu '
        'et Méditation', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      final xs = [
        t.getCenter(_tab('Accueil')).dx,
        t.getCenter(_tab('Tirage & Jeu')).dx,
        t.getCenter(_tab('Consultation')).dx,
        t.getCenter(_tab('Méditation')).dx,
        t.getCenter(_tab('Mon compte')).dx,
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

    testWidgets('N4 — « Mon compte » ouvre le Dashboard existant '
        '(pas de 2ᵉ implémentation)', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      await t.tap(_tab('Mon compte'));
      await t.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('Mon espace'), findsOneWidget);
    });

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
  // TIRAGE & JEU — hub (4 cas)
  // -------------------------------------------------------------------------
  group('Hub Tirage & Jeu', () {
    testWidgets('TJ1 — le hub affiche titre, sous-titre et 2 entrées', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      await t.tap(_tab('Tirage & Jeu'));
      await t.pumpAndSettle();

      expect(find.byType(TirageJeuScreen), findsOneWidget);
      expect(
        find.text('Écoute ton intuition, tire les cartes ou relève un défi.'),
        findsOneWidget,
      );
      expect(find.text('TIRAGE'), findsOneWidget);
      expect(find.text('JEU AURYEL'), findsOneWidget);
    });

    testWidgets('TJ2 — l\'entrée TIRAGE ouvre le vrai TirageScreen '
        '(aucune logique dupliquée)', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      await t.tap(_tab('Tirage & Jeu'));
      await t.pumpAndSettle();

      await t.tap(find.text('Faire mon tirage'));
      await t.pumpAndSettle();
      expect(find.byType(TirageScreen), findsOneWidget);
    });

    testWidgets('TJ3 — l\'entrée JEU AURYEL ouvre le vrai jeu (menu jouable), '
        'sans aucune récompense de temps', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      await t.tap(_tab('Tirage & Jeu'));
      await t.pumpAndSettle();

      await t.tap(find.text('Jouer'));
      await t.pumpAndSettle();

      expect(find.byType(JeuAuryelScreen), findsOneWidget);
      expect(find.text('Le Jeu Auryel'), findsOneWidget);
      expect(find.text('Commencer'), findsOneWidget);
      // Les 3 niveaux sont proposés.
      expect(find.text('Facile'), findsOneWidget);
      expect(find.text('Moyen'), findsOneWidget);
      expect(find.text('Intense'), findsOneWidget);
      // Aucune promesse de gain / récompense de consultation.
      expect(find.textContaining('heure offerte'), findsNothing);
      expect(find.textContaining('minutes offertes'), findsNothing);
      expect(find.textContaining('consultation offerte'), findsNothing);
      expect(find.textContaining('points'), findsNothing);
    });

    testWidgets('TJ4 — ouvrir le hub ne coche PAS la mission Tirage '
        '(seule une sauvegarde réelle la valide)', (t) async {
      final tracker = DailyMissionTracker();
      expect(await tracker.isDone(DailyMissionTracker.tirage), isFalse);

      await t.pumpWidget(_shell());
      await t.pumpAndSettle();
      await t.tap(_tab('Tirage & Jeu'));
      await t.pumpAndSettle();

      expect(
        await tracker.isDone(DailyMissionTracker.tirage),
        isFalse,
        reason: 'le hub seul ne valide rien',
      );
    });
  });

  // -------------------------------------------------------------------------
  // HOME — routage des missions (3 cas)
  // -------------------------------------------------------------------------
  group('Home → onglets', () {
    testWidgets('H1 — mission Tirage renvoie vers l\'onglet 1 (hub), pas '
        'directement TirageScreen', (t) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      await t.tap(find.text('Fais ton tirage'));
      await t.pumpAndSettle();
      expect(find.byType(TirageJeuScreen), findsOneWidget);
      expect(find.byType(TirageScreen), findsNothing);
    });

    testWidgets('H2 — mission Consultation renvoie vers l\'onglet central', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      await t.tap(find.text('Consulte ton conseiller'));
      await t.pumpAndSettle();
      expect(find.byType(ConsultationScreen), findsOneWidget);
    });

    testWidgets('H3 — mission Moment renvoie vers l\'onglet Méditation', (
      t,
    ) async {
      await t.pumpWidget(_shell());
      await t.pumpAndSettle();

      await t.tap(find.text('Prends ton Moment'));
      await t.pumpAndSettle();
      expect(find.byType(MeditationScreen), findsOneWidget);
      expect(find.text('Ton Moment du jour'), findsOneWidget);
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

    testWidgets('MC3 — replay « L\'expérience Auryel » + UI suppression de '
        'compte présents', (t) async {
      await t.pumpWidget(_dashboard(showBackButton: false));
      await t.pumpAndSettle();

      await t.ensureVisible(find.text('Découvrir Auryel'));
      expect(find.text('Découvrir Auryel'), findsOneWidget);
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
        expect(_tab('Tirage & Jeu'), findsOneWidget);
        expect(_tab('Mon compte'), findsOneWidget);

        await t.tap(_tab('Tirage & Jeu'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'hub ${w.toInt()} dp');
        expect(find.text('Tirage & Jeu'), findsWidgets);
      });
    }
  });
}

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
import 'package:auryel/data/account_service.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/daily_like_store.dart';
import 'package:auryel/data/daily_share_tracker.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/bibliotheque_screen.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// B10 — Dashboard « Mon espace ».
// ===========================================================================

AuryelState _state() => AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'uuid-technique-a-ne-pas-afficher',
        selectedAdvisor: 'Séléna',
        firstName: 'Nathanyel',
        birthDate: DateTime(1994, 3, 12),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    );

ConsultationController _consController({
  int firstFree = 0,
  int premium = 0,
  int purchased = 0,
  bool isPremium = false,
}) {
  final client = ApiClient(
    httpClient: MockClient((_) async => http.Response('{}', 404)),
    baseUrl: 'http://test.local',
  );
  final api = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: api,
    tirageApi: TirageApi(client),
  );
  final c = ConsultationController(api: api, auth: auth);
  addTearDown(c.dispose);
  c.updateFromMessageResponse(ConsultationMessageResponse.fromJson({
    'reply': 'x',
    'consultation': null,
    'time': {
      'first_free_remaining_seconds': firstFree,
      'premium_remaining_seconds': premium,
      'purchased_remaining_seconds': purchased,
      'total_remaining_seconds': firstFree + premium + purchased,
      'window_active': false,
      'window_expires_at': null,
    },
    'quota': {
      'is_premium': isPremium,
      'monthly_limit': 8,
      'monthly_used': 0,
      'monthly_remaining': 8,
      'earned_available': 0,
      'first_free_available': false,
      'period_start': '2026-08-01T00:00:00Z',
      'period_end': '2026-09-01T00:00:00Z',
    },
  }));
  return c;
}

/// B10.1 — AuthController réel branché sur un [MockClient] : sert aux tests
/// d'édition de profil (`PATCH /api/app/profile`).
AuthController _auth(MockClient client, {String? token = 'tok'}) {
  final api = ApiClient(httpClient: client, baseUrl: 'http://test.local');
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(api),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(api),
    consultationApi: ConsultationApi(api),
    tirageApi: TirageApi(api),
  );
  addTearDown(auth.dispose);
  return auth;
}

Widget _dash({
  ConsultationController? consultation,
  AuthController? auth,
  AuryelState? state,
}) {
  Widget tree = AuryelStateScope(
    state: state ?? _state(),
    child: const MaterialApp(home: DashboardScreen()),
  );
  if (consultation != null) {
    tree = ConsultationScope(controller: consultation, child: tree);
  }
  if (auth != null) {
    tree = AuthScope(controller: auth, child: tree);
  }
  return tree;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('A/B — l\'icône profil de l\'accueil ouvre le Dashboard « Mon espace »',
      (t) async {
    await t.pumpWidget(
      AuryelStateScope(
        state: _state(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await t.pump(const Duration(seconds: 1));

    final profileIcon = find.byWidgetPredicate((w) =>
        w is PhosphorIcon && w.icon == PhosphorIconsThin.userCircle);
    expect(profileIcon, findsOneWidget);
    await t.tap(profileIcon);
    await t.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Mon espace'), findsOneWidget);
  });

  testWidgets('C/D — conseiller affiché + CTA « Changer de conseiller »',
      (t) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(find.text('MON CONSEILLER'), findsOneWidget);
    expect(find.text('Séléna'), findsOneWidget);
    expect(find.text('Changer de conseiller'), findsOneWidget);
  });

  testWidgets('E — temps disponible vient de ConsultationController', (t) async {
    // 2 buckets -> le total (8 h 42 min) est distinct de chaque ligne détail.
    await t.pumpWidget(_dash(
      consultation: _consController(firstFree: 3600, premium: 27720),
    ));
    await t.pump();
    expect(find.text('Temps disponible'), findsOneWidget);
    expect(find.text('8 h 42 min'), findsOneWidget); // total
    // détail par bucket (source ConsultationTimeState, jamais inventé)
    expect(find.text('Heure offerte'), findsOneWidget);
    expect(find.text('Temps Premium'), findsOneWidget);
    expect(find.text('7 h 42 min'), findsOneWidget);
    // pas de fenêtre 5 min / expires
    expect(find.textContaining('expir'), findsNothing);
  });

  testWidgets('F — 0 min rendu proprement', (t) async {
    await t.pumpWidget(_dash(consultation: _consController()));
    await t.pump();
    expect(find.text('0 min'), findsOneWidget);
  });

  testWidgets('G — Premium non abonné : 8 h / mois + 7,99 €/mois + S\'abonner',
      (t) async {
    await t.pumpWidget(_dash(consultation: _consController(isPremium: false)));
    await t.pump();
    expect(find.text('Auryel Premium'), findsOneWidget);
    expect(find.text('8 h de consultation par mois'), findsOneWidget);
    expect(find.text('7,99 €/mois'), findsOneWidget);
    expect(find.text('S’abonner'), findsOneWidget);
  });

  testWidgets('H — « Restaurer mes achats » absent sans support d\'achat réel',
      (t) async {
    await t.pumpWidget(_dash(consultation: _consController()));
    await t.pump();
    // pas de PurchaseScope injecté -> aucune restauration affichée
    expect(find.text('Restaurer mes achats'), findsNothing);
  });

  testWidgets('I/J/K/L — Mon parcours + compteurs locaux + progression 30 j',
      (t) async {
    final prefs = await SharedPreferences.getInstance();
    await DailyLikeStore(prefs: prefs).toggleToday(now: DateTime(2026, 9, 1));
    await DailyLikeStore(prefs: prefs).toggleToday(now: DateTime(2026, 9, 2));
    final tracker = DailyShareTracker(prefs: prefs);
    await tracker.recordShareAttempt(now: DateTime(2026, 9, 1));
    await tracker.recordShareAttempt(now: DateTime(2026, 9, 2));
    await tracker.recordShareAttempt(now: DateTime(2026, 9, 3));

    await t.pumpWidget(_dash());
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('MON PARCOURS'), findsOneWidget);
    expect(find.text('2 messages aimés'), findsOneWidget);
    expect(find.text('3 jours de partage'), findsOneWidget);
    // progression 30 j + nouveau wording récompense (B10.1 §8-§9)
    expect(find.text('MES RÉCOMPENSES'), findsOneWidget);
    expect(find.text('Génère ta publication'), findsOneWidget);
    expect(
      find.text('Partage ton message du jour sur tes réseaux.'),
      findsOneWidget,
    );
    expect(
      find.text('30 jours de partage = 1 h de consultation offerte.'),
      findsOneWidget,
    );
    expect(find.text('3 / 30 jours'), findsOneWidget);
    expect(find.text('Générer ma publication'), findsOneWidget);
  });

  testWidgets('M/P — aucune heure attribuée, aucune vraie suppression',
      (t) async {
    // Aucun endpoint : les deux mécanismes sont explicitement « indisponibles ».
    expect(AccountService.deletionAvailable, isFalse);

    await t.pumpWidget(_dash());
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    // récompense NON attribuée : mention discrète, aucun crédit
    expect(
      find.textContaining('Activation de la récompense bientôt disponible'),
      findsOneWidget,
    );

    // suppression : dialogue -> action -> snackbar « bientôt », rien n'est touché
    await t.ensureVisible(find.text('Supprimer mon compte'));
    await t.tap(find.text('Supprimer mon compte'));
    await t.pumpAndSettle();
    expect(find.text('Supprimer mon compte ?'), findsOneWidget);
    // le bouton d'action du dialogue
    await t.tap(find.widgetWithText(TextButton, 'Supprimer mon compte'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('La suppression de compte sera bientôt disponible'),
      findsOneWidget,
    );
  });

  testWidgets('N/O — déconnexion + section confidentialité présentes', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(find.text('CONFIDENTIALITÉ ET DONNÉES'), findsOneWidget);
    expect(find.text('Supprimer mon compte'), findsOneWidget);
  });

  testWidgets('Q — aucun user_id technique affiché', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(find.textContaining('uuid-technique'), findsNothing);
    expect(find.textContaining('user_id'), findsNothing);
    expect(find.textContaining('userId'), findsNothing);
  });

  for (final w in const [360.0, 375.0, 384.0, 390.0, 430.0]) {
    testWidgets('R — aucun overflow Dashboard à ${w.toInt()} dp', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 900);
      addTearDown(t.view.reset);
      await t.pumpWidget(_dash(consultation: _consController(
        firstFree: 1800,
        premium: 27720,
        purchased: 3600,
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
    });
  }

  testWidgets('S/T — bottom nav toujours 4 onglets, Dashboard absent',
      (t) async {
    await t.pumpWidget(
      AuryelStateScope(
        state: _state(),
        child: const MaterialApp(home: MainNavShell()),
      ),
    );
    await t.pumpAndSettle();
    for (final label in ['Accueil', 'Tirage', 'Méditation', 'Bibliothèque']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Mon espace'), findsNothing);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  // =========================================================================
  // B10.1 — corrections Mes tirages / profil / récompenses
  // =========================================================================

  testWidgets('B10.1 A — « Voir mes tirages » ouvre la Bibliothèque AVEC une '
      'flèche retour, qui ramène au Dashboard', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();

    await t.ensureVisible(find.text('Voir mes tirages'));
    await t.tap(find.text('Voir mes tirages'));
    await t.pumpAndSettle();

    expect(find.byType(BibliothequeScreen), findsOneWidget);
    expect(find.byTooltip('Retour'), findsOneWidget);

    await t.tap(find.byTooltip('Retour'));
    await t.pumpAndSettle();

    expect(find.byType(BibliothequeScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Mon espace'), findsOneWidget);
  });

  testWidgets('B10.1 B — la Bibliothèque en onglet principal n\'a PAS de '
      'flèche retour', (t) async {
    await t.pumpWidget(const MaterialApp(home: BibliothequeScreen()));
    await t.pump();
    expect(find.byType(BibliothequeScreen), findsOneWidget);
    expect(find.byTooltip('Retour'), findsNothing);
  });

  testWidgets('B10.1 C — prénom : crayon visible, formulaire prérempli, '
      'sauvegarde via PATCH /api/app/profile puis MAJ du Dashboard', (t) async {
    final patched = <Map<String, dynamic>>[];
    final auth = _auth(MockClient((req) async {
      if (req.method == 'PATCH' && req.url.path == '/api/app/profile') {
        patched.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'user_id': 'u',
            'guide': 'maia',
            'prenom': 'Camille',
            'date_naissance': '1994-03-12',
            'chemin_de_vie': '',
            'signe_zodiaque': '',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }));

    await t.pumpWidget(_dash(auth: auth));
    await t.pump();

    // 2 crayons seulement : prénom + date de naissance (jamais l'email)
    expect(find.byTooltip('Modifier'), findsNWidgets(2));

    await t.ensureVisible(find.byTooltip('Modifier').first);
    await t.tap(find.byTooltip('Modifier').first);
    await t.pumpAndSettle();

    expect(find.text('Modifier mon prénom'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Nathanyel'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'Camille');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();

    expect(patched.single['prenom'], 'Camille');
    expect(find.text('Modifier mon prénom'), findsNothing); // feuille fermée
    expect(find.text('Prénom mis à jour.'), findsOneWidget); // snackbar
    expect(find.text('Camille'), findsWidgets); // en-tête + section compte
  });

  testWidgets('B10.1 D — prénom : PATCH en échec -> message d\'erreur, '
      'AUCUN faux succès, aucune modification locale', (t) async {
    final auth = _auth(MockClient((req) async {
      if (req.method == 'PATCH' && req.url.path == '/api/app/profile') {
        return http.Response('{"error":"server"}', 500);
      }
      return http.Response('{}', 404);
    }));

    await t.pumpWidget(_dash(auth: auth));
    await t.pump();

    await t.ensureVisible(find.byTooltip('Modifier').first);
    await t.tap(find.byTooltip('Modifier').first);
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'Camille');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();

    expect(find.textContaining('Impossible d’enregistrer'), findsOneWidget);
    expect(find.text('Modifier mon prénom'), findsOneWidget); // reste ouverte
    expect(find.text('Prénom mis à jour.'), findsNothing); // aucun faux succès
    // état local inchangé : le Dashboard affiche toujours « Nathanyel »
    expect(find.text('Nathanyel'), findsWidgets);
  });

  testWidgets('B10.1 E — date de naissance : crayon -> date picker -> '
      'sauvegarde via PATCH (date_naissance ISO)', (t) async {
    final patched = <Map<String, dynamic>>[];
    final auth = _auth(MockClient((req) async {
      if (req.method == 'PATCH' && req.url.path == '/api/app/profile') {
        patched.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'user_id': 'u',
            'guide': 'maia',
            'prenom': 'Nathanyel',
            'date_naissance': '1994-03-12',
            'chemin_de_vie': '',
            'signe_zodiaque': '',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }));

    await t.pumpWidget(_dash(auth: auth));
    await t.pump();

    await t.ensureVisible(find.byTooltip('Modifier').last);
    await t.tap(find.byTooltip('Modifier').last);
    await t.pumpAndSettle();

    // date picker themed réutilisé (même helpText que l'onboarding)
    expect(find.text('DATE DE NAISSANCE'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();

    expect(patched.single['date_naissance'], '1994-03-12');
    expect(find.text('Date de naissance mise à jour.'), findsOneWidget);
  });

  testWidgets('B10.1 F — email affiché mais NON modifiable', (t) async {
    await t.pumpWidget(_dash(
      auth: _auth(MockClient((_) async => http.Response('{}', 404))),
    ));
    await t.pump();

    expect(find.text('Email'), findsOneWidget);
    expect(
      find.text('La modification de l’email sera bientôt disponible.'),
      findsOneWidget,
    );
    // aucun crayon pour l'email -> exactement 2 (prénom + date)
    expect(find.byTooltip('Modifier'), findsNWidgets(2));
  });

  testWidgets('B10.1 G — « Générer ma publication » réutilise DailyMessageSheet '
      'et n\'attribue AUCUNE heure', (t) async {
    final c = _consController(firstFree: 3600);
    final before = c.remaining.inSeconds;

    await t.pumpWidget(_dash(consultation: c));
    await t.pump();

    await t.ensureVisible(find.text('Générer ma publication'));
    await t.tap(find.text('Générer ma publication'));
    await t.pumpAndSettle();

    expect(find.byType(DailyMessageSheet), findsOneWidget); // flow B8 réutilisé
    expect(c.remaining.inSeconds, before); // aucune heure créditée
    expect(c.time?.purchasedRemainingSeconds ?? 0, 0);
  });

  testWidgets('B10.1 H — récompense : 30/30 rendu sans overflow', (t) async {
    final prefs = await SharedPreferences.getInstance();
    final tracker = DailyShareTracker(prefs: prefs);
    for (var d = 1; d <= 30; d++) {
      await tracker.recordShareAttempt(now: DateTime(2026, 9, d));
    }
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(360, 900);
    addTearDown(t.view.reset);

    await t.pumpWidget(_dash());
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('30 / 30 jours'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

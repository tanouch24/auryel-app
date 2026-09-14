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
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/app_review_service.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/daily_like_store.dart';
import 'package:auryel/data/daily_share_tracker.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/auryel_experience_screen.dart';
import 'package:auryel/screens/bibliotheque_screen.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/rewards_wallet_screen.dart';
import 'package:auryel/screens/support_screen.dart';
import 'package:auryel/screens/wellbeing_journey_screen.dart';
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
  int earned = 0,
  int purchased = 0,
  bool isPremium = false,
  bool firstFreeAvailable = false,
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
  c.updateFromMessageResponse(
    ConsultationMessageResponse.fromJson({
      'reply': 'x',
      'consultation': null,
      'time': {
        'first_free_remaining_seconds': firstFree,
        'premium_remaining_seconds': premium,
        'earned_remaining_seconds': earned,
        'purchased_remaining_seconds': purchased,
        'total_remaining_seconds': firstFree + premium + earned + purchased,
        'window_active': false,
        'window_expires_at': null,
      },
      'quota': {
        'is_premium': isPremium,
        'monthly_limit': 8,
        'monthly_used': 0,
        'monthly_remaining': 8,
        'earned_available': 0,
        'first_free_available': firstFreeAvailable,
        'period_start': '2026-08-01T00:00:00Z',
        'period_end': '2026-09-01T00:00:00Z',
      },
    }),
  );
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
    rewardsApi: RewardsApi(api),
  );
  addTearDown(auth.dispose);
  return auth;
}

DailyThoughtRepository _thoughtRepo() => DailyThoughtRepository(
  seed: [
    DailyThought(
      id: 1,
      publishDate: DateTime(2026, 9, 4),
      phrase: 'Ce que tu n’oses pas regarder te dirige.',
      interpretation: 'x',
      imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
    ),
  ],
);

Widget _dash({
  ConsultationController? consultation,
  AuthController? auth,
  AuryelState? state,
  AppReviewService? reviewService,
}) {
  Widget tree = AuryelStateScope(
    state: state ?? _state(),
    child: MaterialApp(
      home: DashboardScreen(
        thoughtRepository: _thoughtRepo(),
        reviewService: reviewService,
      ),
    ),
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

  testWidgets('A/B — le bouton « Mon compte » de l\'accueil ouvre le Dashboard '
      '« Mon espace »', (t) async {
    await t.pumpWidget(
      AuryelStateScope(
        state: _state(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await t.pump(const Duration(seconds: 1));

    final accountButton = find.byKey(const Key('home-my-account-button'));
    expect(accountButton, findsOneWidget);
    expect(find.text('Mon compte'), findsOneWidget);
    await t.tap(accountButton);
    await t.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Mon espace'), findsOneWidget);
  });

  testWidgets('C/D — conseiller affiché + CTA « Changer de conseiller »', (
    t,
  ) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(find.text('MON CONSEILLER'), findsOneWidget);
    expect(find.text('Séléna'), findsOneWidget);
    expect(find.text('Changer de conseiller'), findsOneWidget);
  });

  testWidgets('E — temps disponible vient de ConsultationController', (
    t,
  ) async {
    // 2 buckets -> le total (8 h 42 min) est distinct de chaque ligne détail.
    await t.pumpWidget(
      _dash(consultation: _consController(firstFree: 3600, premium: 27720)),
    );
    await t.pump();
    expect(find.text('Temps disponible'), findsOneWidget);
    expect(find.text('8 h 42 min'), findsOneWidget); // total
    // détail par bucket (source ConsultationTimeState, jamais inventé)
    expect(find.text('Bienvenue'), findsOneWidget);
    expect(find.text('Temps Premium'), findsOneWidget);
    expect(find.text('7 h 42 min'), findsOneWidget);
    // pas de fenêtre 5 min / expires
    expect(find.textContaining('expir'), findsNothing);
  });

  testWidgets('14/15 — « Bonus » affiché ; total réconcilié avec les '
      'lignes visibles (ordre first_free -> premium -> bonus -> acheté)', (
    t,
  ) async {
    // 3600 (offerte) + 1800 (premium) + 900 (gagné) + 600 (acheté) = 6900 s
    // -> total « 1 h 55 min ».
    await t.pumpWidget(
      _dash(
        consultation: _consController(
          firstFree: 3600,
          premium: 1800,
          earned: 900,
          purchased: 600,
        ),
      ),
    );
    await t.pump();
    expect(find.text('Bienvenue'), findsOneWidget);
    expect(find.text('Temps Premium'), findsOneWidget);
    expect(find.text('Bonus'), findsOneWidget);
    expect(find.text('Temps acheté'), findsOneWidget);
    // total = somme des buckets visibles
    expect(find.text('1 h 55 min'), findsOneWidget);
    // ordre vertical : bonus entre Premium et acheté
    final yPremium = t.getTopLeft(find.text('Temps Premium')).dy;
    final yEarned = t.getTopLeft(find.text('Bonus')).dy;
    final yPurchased = t.getTopLeft(find.text('Temps acheté')).dy;
    expect(yPremium < yEarned, isTrue);
    expect(yEarned < yPurchased, isTrue);
  });

  testWidgets('« Bonus » absent quand earned == 0', (t) async {
    await t.pumpWidget(
      _dash(consultation: _consController(firstFree: 3600, premium: 1800)),
    );
    await t.pump();
    expect(find.text('Bonus'), findsNothing);
  });

  testWidgets(
    'F — 0 min rendu proprement (portefeuille vide, pas de gratuite)',
    (t) async {
      await t.pumpWidget(_dash(consultation: _consController()));
      await t.pump();
      expect(find.text('0 min'), findsOneWidget);
    },
  );

  testWidgets('F bis — compte neuf (bienvenue non encore ouverte, buckets à '
      '0) : Dashboard affiche un libellé neutre, JAMAIS « 0 min », JAMAIS une '
      'durée figée en dur — même vérité que l\'Accueil', (t) async {
    // Cas réel du bug : le backend renvoie first_free_available=true mais ne
    // crédite le bucket bienvenue (20 min, Migration v48) au portefeuille
    // qu'à l'ouverture de la 1re consultation.
    final c = _consController(firstFreeAvailable: true); // tous les buckets = 0
    expect(
      c.availableTimeLabel,
      'Temps offert disponible',
    ); // source unique côté controller
    await t.pumpWidget(_dash(consultation: c));
    await t.pump();
    expect(find.text('Temps disponible'), findsOneWidget);
    expect(find.text('Temps offert disponible'), findsOneWidget);
    expect(find.text('0 min'), findsNothing);
  });

  testWidgets(
    'G — Premium non abonné : 8 h / mois + 7,99 €/mois + S\'abonner',
    (t) async {
      await t.pumpWidget(
        _dash(consultation: _consController(isPremium: false)),
      );
      await t.pump();
      expect(find.text('Auryel Premium'), findsOneWidget);
      expect(find.text('8 h de consultation par mois'), findsOneWidget);
      expect(find.text('7,99 €/mois'), findsOneWidget);
      expect(find.text('S’abonner'), findsOneWidget);
    },
  );

  testWidgets(
    'H — « Restaurer mes achats » absent sans support d\'achat réel',
    (t) async {
      await t.pumpWidget(_dash(consultation: _consController()));
      await t.pump();
      // pas de PurchaseScope injecté -> aucune restauration affichée
      expect(find.text('Restaurer mes achats'), findsNothing);
    },
  );

  testWidgets('I/J/K/L — Mon parcours + compteurs locaux + progression 30 j', (
    t,
  ) async {
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
    expect(find.text('Ta pensée du jour'), findsOneWidget);
    expect(
      find.text('Partage la publication du jour avec tes contacts.'),
      findsOneWidget,
    );
    expect(
      find.text('30 jours de partage = 1 h de consultation offerte.'),
      findsOneWidget,
    );
    expect(find.text('3 / 30 jours'), findsOneWidget);
    expect(find.text('Partager ma pensée du jour'), findsOneWidget);
  });

  testWidgets('J2 — progression partage : le SERVEUR fait autorité quand '
      'GET share-progress répond', (t) async {
    final prefs = await SharedPreferences.getInstance();
    final tracker = DailyShareTracker(prefs: prefs);
    await tracker.recordShareAttempt(now: DateTime(2026, 9, 1)); // local = 1
    var hit = false;
    final auth = _auth(
      MockClient((req) async {
        if (req.url.path == '/api/app/rewards/share-progress') {
          hit = true;
          return http.Response(
            jsonEncode({'count': 12, 'target': 30, 'credited': false}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await t.pumpWidget(_dash(auth: auth));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(hit, isTrue, reason: 'GET share-progress réellement appelé');
    expect(find.text('12 / 30 jours'), findsOneWidget); // serveur
    expect(find.text('1 / 30 jours'), findsNothing); // pas le cache local
  });

  testWidgets('J2 — progression partage : endpoint indisponible -> repli sur '
      'le cache local, aucun crash', (t) async {
    final prefs = await SharedPreferences.getInstance();
    final tracker = DailyShareTracker(prefs: prefs);
    await tracker.recordShareAttempt(now: DateTime(2026, 9, 1));
    await tracker.recordShareAttempt(now: DateTime(2026, 9, 2)); // local = 2
    final auth = _auth(MockClient((_) async => http.Response('{}', 503)));

    await t.pumpWidget(_dash(auth: auth));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('2 / 30 jours'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('M/P — aucune heure attribuée, suppression = 2 confirmations', (
    t,
  ) async {
    await t.pumpWidget(_dash());
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    // récompense : mention honnête (le crédit est décidé par le serveur), aucun
    // crédit local. L'ancien hedge « en cours d'activation » a été retiré (J2).
    expect(
      find.textContaining('le crédit de l’heure sont gérés par nos serveurs'),
      findsOneWidget,
    );
    expect(find.textContaining('en cours d’activation'), findsNothing);

    // suppression : 1re confirmation (texte irréversible) -> 2e confirmation
    // (saisie « SUPPRIMER »). On annule : rien n'est touché.
    await t.ensureVisible(find.text('Supprimer mon compte'));
    await t.tap(find.text('Supprimer mon compte'));
    await t.pumpAndSettle();
    expect(find.text('Supprimer mon compte ?'), findsOneWidget);
    expect(find.textContaining('irréversible'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Supprimer mon compte'));
    await t.pumpAndSettle();
    expect(find.text('Confirmer la suppression'), findsOneWidget);
    // Bouton verrouillé tant que « SUPPRIMER » n'est pas saisi.
    await t.tap(find.text('Annuler').last);
    await t.pumpAndSettle();
    expect(find.text('Confirmer la suppression'), findsNothing);
  });

  testWidgets('N/O — déconnexion + section infos & confidentialité présentes', (
    t,
  ) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(find.text('INFORMATIONS & CONFIDENTIALITÉ'), findsOneWidget);
    expect(find.text('Politique de confidentialité'), findsOneWidget);
    expect(find.text('Conditions d’utilisation'), findsOneWidget);
    expect(find.text('Mentions légales'), findsOneWidget);
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
      await t.pumpWidget(
        _dash(
          consultation: _consController(
            firstFree: 1800,
            premium: 27720,
            purchased: 3600,
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
    });
  }

  testWidgets(
    'S/T — bottom nav V2 : « Mon compte » a QUITTÉ la barre du bas — le '
    'bouton d\'en-tête Accueil réutilise le Dashboard (une seule '
    'implémentation), Boutique absente',
    (t) async {
      await t.pumpWidget(
        AuryelStateScope(
          state: _state(),
          child: const MaterialApp(home: MainNavShell()),
        ),
      );
      await t.pumpAndSettle();
      // AUDIT ACCUEIL/PARCOURS — Accueil affiche désormais une mission
      // « Consultation » (même libellé que le parcours bien-être serveur) :
      // on restreint la recherche à la barre d'onglets elle-même, tous les
      // onglets restant montés simultanément (IndexedStack).
      final tabBar = find.byKey(const Key('auryel-bottom-tab-bar'));
      Finder tab(String label) => find.descendant(
        of: tabBar,
        matching: find.widgetWithText(InkWell, label),
      );
      for (final label in [
        'Accueil',
        'Tirage & Jeu',
        'Consultation',
        'Méditation',
        'Réveil',
      ]) {
        expect(tab(label), findsOneWidget);
      }
      expect(tab('Boutique'), findsNothing);
      expect(tab('Bibliothèque'), findsNothing);
      expect(tab('Mon compte'), findsNothing);

      // « Mon compte » = le bouton d'en-tête Accueil -> le Dashboard existant
      // (une seule implémentation).
      await t.tap(find.byKey(const Key('home-my-account-button')));
      await t.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
    },
  );

  // =========================================================================
  // B10.1 — corrections Mes tirages / profil / récompenses
  // =========================================================================

  testWidgets(
    'EXP — « Découvrir Auryel » (Dashboard) ouvre l\'écran Expérience '
    'en mode replay, sans casser le flag',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'auryel.experience_intro_seen.v1': true,
      });
      await t.pumpWidget(_dash());
      await t.pump();

      await t.ensureVisible(find.text('Découvrir Auryel'));
      await t.tap(find.text('Découvrir Auryel'));
      await t.pumpAndSettle();

      expect(find.byType(AuryelExperienceScreen), findsOneWidget);
      expect(find.text('Bienvenue dans Auryel'), findsOneWidget);
      // CTA de replay, pas le CTA du parcours auto
      expect(find.text('Retour à Auryel'), findsOneWidget);
      expect(find.text('Découvrir Auryel'), findsNothing);

      await t.tap(find.text('Retour à Auryel'));
      await t.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auryel.experience_intro_seen.v1'), isTrue);
    },
  );

  testWidgets('J7 — point d’entrée « Suivre mon parcours bien-être » ouvre '
      'l’écran du parcours', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();

    expect(find.text('Suivre mon parcours bien-être'), findsOneWidget);
    await t.ensureVisible(find.text('Suivre mon parcours bien-être'));
    await t.tap(find.text('Suivre mon parcours bien-être'));
    await t.pumpAndSettle();

    expect(find.byType(WellbeingJourneyScreen), findsOneWidget);
    expect(find.text('Mon parcours bien-être'), findsOneWidget);
  });

  testWidgets('CORRECTIF NAVIGATION — « Voir mes Étoiles » ouvre l’écran '
      '« Mes Étoiles », accessible depuis le Dashboard indépendamment de '
      'la pilule Accueil (ex. wallet pas encore chargé)', (t) async {
    final auth = _auth(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'stars_balance': 7,
            'rules': [],
            'recent_transactions': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await t.pumpWidget(_dash(auth: auth));
    await t.pump();

    await t.ensureVisible(find.text('Voir mes Étoiles'));
    await t.tap(find.text('Voir mes Étoiles'));
    await t.pumpAndSettle();

    expect(find.byType(RewardsWalletScreen), findsOneWidget);
    expect(find.text('Mes Étoiles'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

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
    final auth = _auth(
      MockClient((req) async {
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
      }),
    );

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
    final auth = _auth(
      MockClient((req) async {
        if (req.method == 'PATCH' && req.url.path == '/api/app/profile') {
          return http.Response('{"error":"server"}', 500);
        }
        return http.Response('{}', 404);
      }),
    );

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
    final auth = _auth(
      MockClient((req) async {
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
      }),
    );

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

  testWidgets('J2 — édition date de naissance : < 18 ans -> refus, aucun PATCH, '
      'état local intact', (t) async {
    final patched = <Map<String, dynamic>>[];
    final auth = _auth(
      MockClient((req) async {
        if (req.method == 'PATCH' && req.url.path == '/api/app/profile') {
          patched.add(jsonDecode(req.body) as Map<String, dynamic>);
        }
        return http.Response('{}', 404);
      }),
    );
    // État avec une date de naissance déjà mineure -> le picker s'ouvre dessus,
    // « OK » renvoie cette date < 18.
    final minorState = AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u',
        selectedAdvisor: 'Séléna',
        firstName: 'Nathanyel',
        birthDate: DateTime(DateTime.now().year - 10, 1, 1),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    );

    await t.pumpWidget(_dash(auth: auth, state: minorState));
    await t.pump();

    await t.ensureVisible(find.byTooltip('Modifier').last);
    await t.tap(find.byTooltip('Modifier').last);
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();

    // Message de refus affiché dans un SnackBar (le même texte figure aussi de
    // façon permanente dans « Informations & confidentialité » depuis J3).
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(
          'Auryel est réservé aux personnes âgées de 18 ans ou plus.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Date de naissance mise à jour.'), findsNothing);
    expect(patched, isEmpty, reason: 'aucun PATCH envoyé pour un âge < 18');
    expect(minorState.birthDate, DateTime(DateTime.now().year - 10, 1, 1));
  });

  testWidgets('B10.1 F — email affiché mais NON modifiable', (t) async {
    await t.pumpWidget(
      _dash(auth: _auth(MockClient((_) async => http.Response('{}', 404)))),
    );
    await t.pump();

    expect(find.text('Email'), findsOneWidget);
    expect(
      find.text('La modification de l’email sera bientôt disponible.'),
      findsOneWidget,
    );
    // aucun crayon pour l'email -> exactement 2 (prénom + date)
    expect(find.byTooltip('Modifier'), findsNWidgets(2));
  });

  testWidgets('B10.1 G — « Partager ma pensée du jour » ouvre l\'aperçu et '
      'n\'attribue AUCUNE heure', (t) async {
    final c = _consController(firstFree: 3600);
    final before = c.remaining.inSeconds;

    await t.pumpWidget(_dash(consultation: c));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Partager ma pensée du jour'));
    await t.tap(find.text('Partager ma pensée du jour'));
    await t.pumpAndSettle();

    expect(find.byType(DailyMessageSheet), findsOneWidget); // aperçu simplifié
    expect(find.text('Partager'), findsOneWidget);
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

  // =========================================================================
  // V1.1 — en-tête : wordmark AURYEL renforcé au-dessus de « Mon espace ».
  // =========================================================================

  testWidgets('HEADER A/B — AURYEL et « Mon espace » visibles', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(find.text('AURYEL'), findsOneWidget);
    expect(find.text('Mon espace'), findsOneWidget);
  });

  testWidgets('HEADER C — AURYEL est plus haut (avant) que « Mon espace » '
      'et typographiquement dominant', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();

    final wordmarkY = t.getTopLeft(find.text('AURYEL')).dy;
    final subtitleY = t.getTopLeft(find.text('Mon espace')).dy;
    expect(wordmarkY, lessThan(subtitleY));

    final wordmark = t.widget<Text>(find.text('AURYEL'));
    final subtitle = t.widget<Text>(find.text('Mon espace'));
    expect(wordmark.style!.fontSize!, greaterThan(subtitle.style!.fontSize!));
  });

  testWidgets('HEADER E — la flèche retour reste présente', (t) async {
    await t.pumpWidget(_dash());
    await t.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is PhosphorIcon && w.icon == PhosphorIconsRegular.arrowLeft,
      ),
      findsOneWidget,
    );
  });

  for (final w in const [360.0, 384.0, 430.0]) {
    testWidgets(
      'HEADER D — aucun overflow en-tête Dashboard à ${w.toInt()} dp',
      (t) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = Size(w, 1600);
        addTearDown(t.view.reset);

        await t.pumpWidget(_dash());
        await t.pump();
        expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
        expect(find.text('AURYEL'), findsOneWidget);
      },
    );
  }

  // ---------------------------------------------------------------------
  // AIDE — « Signaler un problème » + « Noter l'appli »
  // ---------------------------------------------------------------------
  group('Aide', () {
    testWidgets('section Aide : les deux entrées sont visibles', (t) async {
      await t.pumpWidget(_dash());
      await t.pump();
      await t.scrollUntilVisible(find.text('Signaler un problème'), 300);
      expect(find.text('AIDE'), findsOneWidget);
      expect(find.text('Signaler un problème'), findsOneWidget);
      expect(find.text('Noter l’appli'), findsOneWidget);
    });

    testWidgets('« Signaler un problème » ouvre le formulaire', (t) async {
      await t.pumpWidget(_dash());
      await t.pump();
      await t.scrollUntilVisible(find.text('Signaler un problème'), 300);
      await t.tap(find.text('Signaler un problème'));
      await t.pumpAndSettle();
      expect(find.byType(SupportScreen), findsOneWidget);
      expect(find.text('SUJET'), findsOneWidget);
    });

    testWidgets('« Noter l’appli » appelle le service de notation, '
        'aucune récompense / wallet touché', (t) async {
      final rec = RecordingReviewService();
      await t.pumpWidget(_dash(reviewService: rec));
      await t.pump();
      await t.scrollUntilVisible(find.text('Noter l’appli'), 300);
      await t.tap(find.text('Noter l’appli'));
      await t.pumpAndSettle();
      expect(rec.calls, 1);
      // aucun wording orienté
      expect(find.textContaining('5 étoiles'), findsNothing);
      expect(find.textContaining('Merci pour'), findsNothing);
    });

    testWidgets('« Noter l’appli » : service indisponible -> message neutre', (
      t,
    ) async {
      final rec = RecordingReviewService()
        ..result = AppReviewOutcome.unavailable;
      await t.pumpWidget(_dash(reviewService: rec));
      await t.pump();
      await t.scrollUntilVisible(find.text('Noter l’appli'), 300);
      await t.tap(find.text('Noter l’appli'));
      await t.pumpAndSettle();
      expect(
        find.text('La notation n’est pas disponible pour le moment.'),
        findsOneWidget,
      );
    });
  });
}

/// Faux service de notation — compte les appels, pilote le résultat.
class RecordingReviewService implements AppReviewService {
  int calls = 0;
  AppReviewOutcome result = AppReviewOutcome.requested;

  @override
  Future<AppReviewOutcome> rate() async {
    calls++;
    return result;
  }
}

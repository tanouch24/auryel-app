import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/billing_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/iap_gateway.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/premium_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/state/purchase_controller.dart';

// ===========================================================================
// AUDIT ABONNEMENT — reproduction précise des bugs de réactivité corrigés :
//
//  1. PremiumScreen n'écoutait que PurchaseController -> un resync silencieux
//     de ConsultationController (refresh()/refreshAll()) ne mettait jamais
//     à jour l'écran déjà ouvert.
//  2. DashboardScreen (_SubscriptionSection) n'écoutait ConsultationController
//     nulle part -> même symptôme.
//
// Dans les deux cas : l'écran est monté AVANT que le statut Premium ne soit
// connu (quota == null, comme au tout premier rendu après le splash), PUIS
// ConsultationController reçoit isPremium=true SANS qu'on quitte/revienne
// sur l'écran (exactement `notifyListeners()`, ex. via refresh()) — l'écran
// DOIT se reconstruire tout seul.
// ===========================================================================

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _quotaJson({required bool isPremium}) => {
  'is_premium': isPremium,
  'monthly_limit': 4,
  'monthly_used': 0,
  'monthly_remaining': 4,
  'earned_available': 0,
  'first_free_available': false,
  'period_start': '2026-09-01T00:00:00Z',
  'period_end': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> _stateJson({required bool isPremium}) => {
  'consultation': null,
  'quota': _quotaJson(isPremium: isPremium),
};

/// Gateway IAP factice : ne sert qu'à satisfaire `PurchaseController`, aucun
/// de ces tests ne déclenche d'achat.
class _NoopGateway implements IapGateway {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [], notFoundIDs: []);
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<bool> buyNonConsumable(ProductDetails product) async => false;
  @override
  Future<bool> buyConsumable(ProductDetails product) async => false;
  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}
  @override
  Future<void> restorePurchases() async {}
}

typedef _Rig = ({
  ConsultationController consultation,
  PurchaseController purchase,
  AuthController auth,
});

/// Construit un trio contrôleurs branché sur un [handler] HTTP unique pour
/// `GET /api/consultation/state` — piloté par le test pour simuler l'arrivée
/// TARDIVE de la réponse serveur (race du splash).
_Rig _rig(Future<http.Response> Function(http.Request) handler) {
  final client = ApiClient(
    httpClient: MockClient(handler),
    baseUrl: 'http://test.local',
  );
  final consultationApi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: consultationApi,
    tirageApi: TirageApi(client),
  );
  final consultation = ConsultationController(api: consultationApi, auth: auth);
  final purchase = PurchaseController(
    billing: BillingApi(client),
    gateway: _NoopGateway(),
    auth: auth,
    consultation: consultation,
    platformOverride: TargetPlatform.android,
  );
  addTearDown(() {
    purchase.dispose();
    consultation.dispose();
  });
  return (consultation: consultation, purchase: purchase, auth: auth);
}

Widget _premiumHost(_Rig rig) => PurchaseScope(
  controller: rig.purchase,
  child: ConsultationScope(
    controller: rig.consultation,
    child: const MaterialApp(home: PremiumScreen()),
  ),
);

AuryelState _appState() => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u',
    selectedAdvisor: 'Séléna',
    firstName: 'N',
    birthDate: DateTime(1994, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: true,
  ),
);

DailyThoughtRepository _thoughtRepo() => DailyThoughtRepository(
  seed: [
    DailyThought(
      id: 1,
      publishDate: DateTime(2026, 9, 4),
      phrase: 'x',
      interpretation: 'y',
      imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
    ),
  ],
);

Widget _dashHost(_Rig rig) => AuthScope(
  controller: rig.auth,
  child: ConsultationScope(
    controller: rig.consultation,
    child: AuryelStateScope(
      state: _appState(),
      child: MaterialApp(
        home: DashboardScreen(thoughtRepository: _thoughtRepo()),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1/2 — PremiumScreen se reconstruit sans navigation', () {
    testWidgets(
      'statut inconnu au 1er rendu -> isPremium=true reçu ensuite -> écran '
      'se met à jour SANS quitter/revenir',
      (t) async {
        final rig = _rig((req) async => _json(_stateJson(isPremium: true)));
        await t.pumpWidget(_premiumHost(rig));
        await t.pump();

        // Rendu initial : quota pas encore chargé -> pas Premium (repli sûr).
        expect(find.text('Premium actif'), findsNothing);
        expect(find.text('S’abonner'), findsOneWidget);

        // Le resync arrive (ex. `SplashScreen._boot`'s `refreshAll()`) —
        // AUCUNE reconstruction manuelle du widget, juste l'événement.
        await rig.consultation.refresh();
        await t.pump();

        expect(
          find.text('Premium actif'),
          findsOneWidget,
          reason: 'PremiumScreen doit refléter isPremium=true sans qu’on '
              'quitte l’écran',
        );
        expect(find.text('S’abonner'), findsNothing);

        // Aucune boucle de rebuild : pumpAndSettle doit terminer.
        await t.pumpAndSettle();
      },
    );
  });

  group('2 — DashboardScreen (section abonnement) se reconstruit sans '
      'navigation', () {
    testWidgets(
      'statut initial non-Premium -> notifyListeners Premium=true -> '
      'section abonnement seule se met à jour',
      (t) async {
        var premium = false;
        final rig = _rig(
          (req) async => _json(_stateJson(isPremium: premium)),
        );
        await rig.consultation.refresh(); // état initial résolu : false
        await t.pumpWidget(_dashHost(rig));
        await t.pumpAndSettle();

        expect(find.text('Actif'), findsNothing);
        expect(find.text('8 h de consultation par mois'), findsOneWidget);

        // Le resync arrive et change le statut, SANS navigation.
        premium = true;
        await rig.consultation.refresh();
        await t.pump();

        expect(
          find.text('Actif'),
          findsOneWidget,
          reason: 'la section abonnement doit refléter isPremium=true sans '
              'quitter/revenir sur le Dashboard',
        );
        expect(find.text('8 h de consultation par mois'), findsNothing);

        await t.pumpAndSettle();
      },
    );
  });

  group('5 — relance simulée : refresh arrive APRÈS le premier rendu', () {
    testWidgets(
      'PremiumScreen : la réponse serveur, retardée, finit par afficher '
      'Premium correctement',
      (t) async {
        final gate = Completer<void>();
        final rig = _rig((req) async {
          await gate.future; // simule une réponse réseau tardive
          return _json(_stateJson(isPremium: true));
        });
        await t.pumpWidget(_premiumHost(rig));
        await t.pump();

        // Le refresh est en vol (repli sûr : pas Premium tant que rien
        // n'est revenu).
        final pending = rig.consultation.refresh();
        await t.pump();
        expect(find.text('Premium actif'), findsNothing);

        // La réponse serveur arrive enfin.
        gate.complete();
        await pending;
        await t.pump();

        expect(find.text('Premium actif'), findsOneWidget);
      },
    );
  });

  group('6 — logout/login : ancien statut vidé, nouveau compte correct', () {
    testWidgets(
      'reset() vide immédiatement le Premium affiché ; le refresh suivant '
      'reflète le nouveau compte',
      (t) async {
        var account = 'A'; // Premium
        final rig = _rig((req) async {
          return _json(_stateJson(isPremium: account == 'A'));
        });
        await t.pumpWidget(_premiumHost(rig));
        await rig.consultation.refresh();
        await t.pump();
        expect(find.text('Premium actif'), findsOneWidget);

        // Déconnexion : reset() — comme dashboard_screen._logout /
        // adult_gate._logout — SANS quitter l'écran dans ce test (l'appli
        // réelle navigue vers EmailAuthScreen juste après).
        rig.consultation.reset();
        await t.pump();
        expect(
          find.text('Premium actif'),
          findsNothing,
          reason: 'le Premium de l’ancien compte ne doit plus être affiché '
              'dès la déconnexion',
        );

        // Login compte B (non-Premium) : le refresh qui suit reflète le
        // NOUVEAU compte, jamais l'ancien.
        account = 'B';
        await rig.consultation.refresh();
        await t.pump();
        expect(find.text('Premium actif'), findsNothing);
        expect(find.text('S’abonner'), findsOneWidget);
      },
    );
  });
}

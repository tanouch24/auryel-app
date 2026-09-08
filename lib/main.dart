import 'dart:async';

import 'package:flutter/material.dart';

import 'api/account_api.dart';
import 'api/ai_report_api.dart';
import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/billing_api.dart';
import 'api/consultation_api.dart';
import 'api/profile_api.dart';
import 'api/rewards_api.dart';
import 'api/tirage_api.dart';
import 'api/wellbeing_api.dart';
import 'data/auth_repository.dart';
import 'data/iap_gateway.dart';
import 'data/installation_id_store.dart';
import 'data/onboarding_repository.dart';
import 'data/shop_cart_store.dart';
import 'data/token_store.dart';
import 'notifications/fcm_notification_service.dart';
import 'notifications/notification_coordinator.dart';
import 'screens/splash_screen.dart';
import 'state/auryel_state.dart';
import 'state/auth_controller.dart';
import 'state/consultation_controller.dart';
import 'state/purchase_controller.dart';
import 'theme/auryel_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = LocalOnboardingRepository();
  final record = await repository.load();

  final apiClient = ApiClient();
  final consultationApi = ConsultationApi(apiClient);
  final billingApi = BillingApi(apiClient);
  final tirageApi = TirageApi(apiClient);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(apiClient),
      tokenStore: SecureTokenStore(),
    ),
    profileApi: ProfileApi(apiClient),
    consultationApi: consultationApi,
    tirageApi: tirageApi,
    aiReportApi: AiReportApi(apiClient),
    accountApi: AccountApi(apiClient),
    rewardsApi: RewardsApi(apiClient),
    wellbeingApi: WellbeingApi(apiClient),
    // Signal anti-abus « heure gratuite » (identifiant d'INSTALLATION, pas de
    // compte). Généré LAZY au 1er `auth.installationId()` ; rien n'est envoyé
    // au backend tant que le contrat ne l'accepte pas (cf. rapport / doc).
    installationIdStore: SecureInstallationIdStore(),
  );

  // UX-B §6 — changement de conseiller préféré : synchro `guide` seul via
  // l'`AuthController` existant (aucun second client HTTP).
  final state = AuryelState(
    repository: repository,
    initial: record,
    guideSync: (guideKey) => auth.syncGuide(guide: guideKey),
  );
  final consultation = ConsultationController(api: consultationApi, auth: auth);
  final purchase = PurchaseController(
    billing: billingApi,
    gateway: InAppPurchaseGateway(),
    auth: auth,
    consultation: consultation,
  );
  // Souscription à `purchaseStream` dès le démarrage (recommandation du plugin) ;
  // le chargement produit continue en tâche de fond.
  unawaited(purchase.initialize());

  // Notifications push (FCM Android). [FcmNotificationService] est la vraie
  // implémentation ; elle DÉGRADE proprement en « indisponible » tant que
  // Firebase n'est pas configuré (google-services.json + plugin Google
  // Services absents) — aucun crash, l'app fonctionne sans push. `start()` ne
  // bloque JAMAIS le démarrage (toutes les erreurs sont absorbées).
  final notifications = NotificationCoordinator(
    service: FcmNotificationService(),
  );
  unawaited(notifications.start());

  runApp(
    AuryelApp(
      state: state,
      auth: auth,
      consultation: consultation,
      purchase: purchase,
      notifications: notifications,
    ),
  );
}

class AuryelApp extends StatefulWidget {
  const AuryelApp({
    super.key,
    required this.state,
    required this.auth,
    required this.consultation,
    this.purchase,
    this.notifications,
  });

  final AuryelState state;
  final AuthController auth;
  final ConsultationController consultation;

  /// F5-B — optionnel : quand fourni (cas réel de `main()`), l'arbre est
  /// enveloppé d'un [PurchaseScope]. Absent dans les tests hérités qui ne
  /// touchent pas à l'achat.
  final PurchaseController? purchase;

  /// Optionnel : quand fourni, l'arbre est enveloppé d'un [NotificationScope]
  /// et le coordinateur est disposé avec l'app. Absent des tests hérités.
  final NotificationCoordinator? notifications;

  @override
  State<AuryelApp> createState() => _AuryelAppState();
}

class _AuryelAppState extends State<AuryelApp> with WidgetsBindingObserver {
  /// Panier boutique LOCAL — instance unique, chargée depuis le disque au
  /// démarrage. Purement local (aucun backend, aucun Stripe).
  final ShopCartStore _cart = ShopCartStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.notifications?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour de l'arrière-plan : une seule resynchro par passage au premier
    // plan — portefeuille (`/state`) ET liste des consultations (`/list`, J6-F2)
    // pour que « Consultations en cours » reflète l'activité la plus récente.
    if (state == AppLifecycleState.resumed && widget.auth.isSignedIn) {
      widget.consultation.refreshAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tree = AuryelStateScope(
      state: widget.state,
      child: ShopCartScope(
        store: _cart,
        child: MaterialApp(
          title: 'Auryel',
          debugShowCheckedModeBanner: false,
          theme: AuryelTheme.dark,
          home: const SplashScreen(),
        ),
      ),
    );
    final purchase = widget.purchase;
    if (purchase != null) {
      tree = PurchaseScope(controller: purchase, child: tree);
    }
    final notifications = widget.notifications;
    if (notifications != null) {
      tree = NotificationScope(
        service: notifications.service,
        router: notifications.router,
        child: tree,
      );
    }
    return AuthScope(
      controller: widget.auth,
      child: ConsultationScope(controller: widget.consultation, child: tree),
    );
  }
}

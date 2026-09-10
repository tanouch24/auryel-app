import 'dart:async';

import 'package:flutter/material.dart';

import 'api/account_api.dart';
import 'api/ai_report_api.dart';
import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/billing_api.dart';
import 'api/consultation_api.dart';
import 'api/content_api.dart';
import 'api/memory_api.dart';
import 'api/profile_api.dart';
import 'api/support_api.dart';
import 'api/rewards_api.dart';
import 'api/tirage_api.dart';
import 'api/wellbeing_api.dart';
import 'data/auth_repository.dart';
import 'data/content_repository.dart';
import 'data/iap_gateway.dart';
import 'data/installation_id_store.dart';
import 'data/onboarding_repository.dart';
import 'data/shop_cart_store.dart';
import 'data/token_store.dart';
import 'notifications/fcm_notification_service.dart';
import 'notifications/local_notification_presenter.dart';
import 'notifications/notification_coordinator.dart';
import 'notifications/notification_payload.dart';
import 'notifications/push_token_registrar.dart';
import 'analytics/meta_events.dart';
import 'state/meta_consent_controller.dart';
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

  // Meta App Events — INACTIF par défaut : sans config de build OU sans
  // consentement explicite persisté, `MetaEvents.create` renvoie un no-op.
  // Aucune collecte (identifiant publicitaire inclus) tant que l'utilisateur
  // n'a pas activé la mesure dans « Mon compte ».
  final metaConsentGranted = await MetaConsentController.readPersisted();
  final metaEvents = await MetaEvents.create(
    config: MetaConfig.fromEnvironment,
    consentGranted: metaConsentGranted,
  );
  final metaConsent = MetaConsentController(events: metaEvents);
  unawaited(metaConsent.load());

  final apiClient = ApiClient();
  final consultationApi = ConsultationApi(apiClient);
  final billingApi = BillingApi(apiClient);
  final tirageApi = TirageApi(apiClient);
  final contentApi = ContentApi(apiClient);
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
    memoryApi: MemoryApi(apiClient),
    supportApi: SupportApi(apiClient),
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
    onOnboardingCompleted: () => unawaited(metaEvents.logOnboardingCompleted()),
  );
  final consultation = ConsultationController(
    api: consultationApi,
    auth: auth,
    metaEvents: metaEvents,
  );
  // Contenu distant (pensée du jour + méditations) : serveur -> cache local
  // -> pack embarqué. Ne bloque jamais le démarrage ; sans réseau / session,
  // l'app sert le contenu embarqué comme avant.
  final content = ContentRepository(
    api: contentApi,
    tokenProvider: () => auth.currentToken(),
  );
  final purchase = PurchaseController(
    billing: billingApi,
    gateway: InAppPurchaseGateway(),
    auth: auth,
    consultation: consultation,
    metaEvents: metaEvents,
  );
  // Souscription à `purchaseStream` dès le démarrage (recommandation du plugin) ;
  // le chargement produit continue en tâche de fond.
  unawaited(purchase.initialize());

  // Notifications push (FCM Android). [FcmNotificationService] est la vraie
  // implémentation ; elle DÉGRADE proprement en « indisponible » tant que
  // Firebase n'est pas configuré (google-services.json absent) — aucun crash.
  // `start()` ne bloque JAMAIS le démarrage.
  //
  // Le jeton FCM est BUFFERISÉ et n'est envoyé au backend
  // (`POST /api/app/push/register`) que lorsqu'une session est valide
  // (`auth.isSignedIn`). Le désenregistrement se fait AVANT logout / suppression
  // de compte via `attachPushUnregister`.
  final notifications = NotificationCoordinator(
    service: FcmNotificationService(),
    registrar: HttpPushTokenRegistrar(
      apiClient: apiClient,
      bearerProvider: () => auth.currentToken(),
    ),
    isSignedIn: () => auth.isSignedIn,
  );
  auth.attachPushUnregister(notifications.unregisterCurrent);
  auth.addListener(() {
    if (auth.isSignedIn) unawaited(notifications.onSignedIn());
  });
  unawaited(notifications.start());

  runApp(
    AuryelApp(
      state: state,
      auth: auth,
      consultation: consultation,
      purchase: purchase,
      notifications: notifications,
      metaEvents: metaEvents,
      metaConsent: metaConsent,
      content: content,
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
    this.metaEvents,
    this.metaConsent,
    this.content,
  });

  final AuryelState state;
  final AuthController auth;
  final ConsultationController consultation;

  /// Optionnel : contenu distant (pensée du jour + méditations). Quand fourni,
  /// l'arbre est enveloppé d'un [ContentScope]. Absent des tests hérités ->
  /// les écrans lisent le contenu embarqué comme avant.
  final ContentRepository? content;

  /// F5-B — optionnel : quand fourni (cas réel de `main()`), l'arbre est
  /// enveloppé d'un [PurchaseScope]. Absent dans les tests hérités qui ne
  /// touchent pas à l'achat.
  final PurchaseController? purchase;

  /// Optionnel : quand fourni, l'arbre est enveloppé d'un [NotificationScope]
  /// et le coordinateur est disposé avec l'app. Absent des tests hérités.
  final NotificationCoordinator? notifications;

  /// Optionnel : mesure Meta (no-op sans config / sans consentement). Quand
  /// fourni, l'arbre est enveloppé d'un [AnalyticsScope].
  final MetaEvents? metaEvents;
  final MetaConsentController? metaConsent;

  @override
  State<AuryelApp> createState() => _AuryelAppState();
}

class _AuryelAppState extends State<AuryelApp> with WidgetsBindingObserver {
  /// Panier boutique LOCAL — instance unique, chargée depuis le disque au
  /// démarrage. Purement local (aucun backend, aucun Stripe).
  final ShopCartStore _cart = ShopCartStore.instance;

  /// Affiche une notif locale quand un message FCM arrive app au premier plan
  /// (Android n'affiche rien tout seul). `null` si aucun coordinateur (tests).
  StreamSubscription<NotificationPayload>? _foregroundSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = widget.notifications;
    if (notifications != null) {
      final presenter = LocalNotificationPresenter()
        ..onSelect = notifications.handleForegroundTap;
      unawaited(presenter.initialize());
      _foregroundSub = notifications.onForegroundMessage.listen(presenter.show);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundSub?.cancel();
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
        coordinator: notifications,
        child: tree,
      );
    }
    final metaEvents = widget.metaEvents;
    final metaConsent = widget.metaConsent;
    if (metaEvents != null && metaConsent != null) {
      tree = AnalyticsScope(
        events: metaEvents,
        controller: metaConsent,
        child: tree,
      );
    }
    final content = widget.content;
    if (content != null) {
      tree = ContentScope(repository: content, child: tree);
    }
    return AuthScope(
      controller: widget.auth,
      child: ConsultationScope(controller: widget.consultation, child: tree),
    );
  }
}

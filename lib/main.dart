import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/account_api.dart';
import 'api/ai_report_api.dart';
import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/billing_api.dart';
import 'api/consultation_api.dart';
import 'api/content_api.dart';
import 'api/memory_api.dart';
import 'api/mini_game_api.dart';
import 'api/profile_api.dart';
import 'api/support_api.dart';
import 'api/rewards_api.dart';
import 'api/tirage_api.dart';
import 'api/wellbeing_api.dart';
import 'api/wellbeing_program_api.dart';
import 'api/wellbeing_ebooks_api.dart';
import 'api/unread_api.dart';
import 'data/auth_repository.dart';
import 'data/content_repository.dart';
import 'data/iap_gateway.dart';
import 'data/installation_id_store.dart';
import 'data/onboarding_repository.dart';
import 'data/shop_cart_store.dart';
import 'data/token_store.dart';
import 'data/wake_video.dart';
import 'notifications/fcm_notification_service.dart';
import 'notifications/local_notification_presenter.dart';
import 'notifications/notification_coordinator.dart';
import 'notifications/notification_payload.dart';
import 'notifications/push_token_registrar.dart';
import 'analytics/meta_events.dart';
import 'analytics/first_party_analytics.dart';
import 'ads/ad_service.dart';
import 'state/meta_consent_controller.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding/email_auth_screen.dart';
import 'screens/wake_ringing_screen.dart';
import 'services/launcher_badge_channel.dart';
import 'state/auryel_state.dart';
import 'state/auth_controller.dart';
import 'state/consultation_controller.dart';
import 'state/purchase_controller.dart';
import 'state/rewards_controller.dart';
import 'state/wellbeing_controller.dart';
import 'state/wellbeing_program_controller.dart';
import 'state/wellbeing_ebooks_controller.dart';
import 'state/unread_controller.dart';
import 'theme/auryel_theme.dart';
import 'startup_trace.dart';

void main() async {
  StartupTrace.mark('process/main');
  WidgetsFlutterBinding.ensureInitialized();
  StartupTrace.mark('flutter/engine-ready');

  final repository = LocalOnboardingRepository();
  final record = await repository.load();
  StartupTrace.mark('storage/onboarding-restored');

  // Meta App Events — INACTIF par défaut : sans config de build OU sans
  // consentement explicite persisté, `MetaEvents.create` renvoie un no-op.
  // Aucune collecte (identifiant publicitaire inclus) tant que l'utilisateur
  // n'a pas activé la mesure dans « Mon compte ».
  final metaConsentGranted = await MetaConsentController.readPersisted();
  StartupTrace.mark('storage/meta-consent-read');
  final metaEvents = await MetaEvents.create(
    config: MetaConfig.fromEnvironment,
    consentGranted: metaConsentGranted,
  );
  StartupTrace.mark('analytics/ready');
  final metaConsent = MetaConsentController(events: metaEvents);
  unawaited(metaConsent.load());
  // AdMob/UMP : initialisation non bloquante et fail-open.
  unawaited(AuryelAds.instance.initialize());

  final apiClient = ApiClient();
  final consultationApi = ConsultationApi(apiClient);
  final billingApi = BillingApi(apiClient);
  final tirageApi = TirageApi(apiClient);
  final contentApi = ContentApi(apiClient);
  final wellbeingApi = WellbeingApi(apiClient);
  final wellbeingProgramApi = WellbeingProgramApi(apiClient);
  final wellbeingEbooksApi = WellbeingEbooksApi(apiClient);
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
    wellbeingApi: wellbeingApi,
    memoryApi: MemoryApi(apiClient),
    miniGameApi: MiniGameApi(apiClient),
    supportApi: SupportApi(apiClient),
    // Signal anti-abus « heure gratuite » (identifiant d'INSTALLATION, pas de
    // compte). Généré LAZY au 1er `auth.installationId()` ; rien n'est envoyé
    // au backend tant que le contrat ne l'accepte pas (cf. rapport / doc).
    installationIdStore: SecureInstallationIdStore(),
  );
  StartupTrace.mark('controllers/auth-ready');
  final firstPartyAnalytics = FirstPartyAnalytics(
    api: apiClient,
    tokenProvider: auth.currentToken,
  );

  // UX-B §6 — changement de conseiller préféré : synchro `guide` seul via
  // l'`AuthController` existant (aucun second client HTTP).
  final state = AuryelState(
    repository: repository,
    initial: record,
    guideSync: (guideKey) => auth.syncGuide(guide: guideKey),
    onOnboardingCompleted: () {
      unawaited(metaEvents.logOnboardingCompleted());
      unawaited(firstPartyAnalytics.log('onboarding_completed'));
    },
  );
  final consultation = ConsultationController(
    api: consultationApi,
    auth: auth,
    metaEvents: metaEvents,
    userIdProvider: () => state.userId,
  );
  // AUDIT ACCUEIL/PARCOURS — instance UNIQUE et PARTAGÉE (cf. WellbeingScope) :
  // Le parcours bien-être reste disponible dans son écran dédié ; la Home
  // n'affiche plus les missions et le wallet Étoiles porte les règles actives.
  // notifient désormais le MÊME contrôleur. Corrige l'incohérence où Accueil
  // pouvait annoncer la journée terminée pendant que Parcours affichait 3/4
  // (deux systèmes de suivi indépendants qui pouvaient diverger).
  final wellbeing = WellbeingController(
    api: wellbeingApi,
    tokenProvider: auth.currentToken,
  );
  final wellbeingProgram = WellbeingProgramController(
    api: wellbeingProgramApi,
    tokenProvider: auth.currentToken,
  );
  final wellbeingEbooks = WellbeingEbooksController(
    api: wellbeingEbooksApi,
    tokenProvider: auth.currentToken,
    authReadyProvider: () => auth.status != AuthStatus.unknown,
  );
  final unread = UnreadController(
    api: UnreadApi(apiClient),
    tokenProvider: auth.currentToken,
    badgeChannel: MethodChannelLauncherBadge(),
  );
  // GROS CHANTIER AURYEL (Prompt 2/5) — ÉTOILES : instance UNIQUE et PARTAGÉE
  // (cf. RewardsScope), même schéma que WellbeingController ci-dessus. Le
  // header Accueil et l'écran « Mes Étoiles » lisent et notifient le MÊME
  // contrôleur : jamais deux soldes affichés qui pourraient diverger.
  final rewards = RewardsController(
    api: auth.rewardsApi ?? RewardsApi(apiClient),
    tokenProvider: auth.currentToken,
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
    if (auth.isSignedIn) {
      unawaited(firstPartyAnalytics.logSessionStarted());
      unawaited(notifications.onSignedIn());
      unawaited(wellbeingProgram.refresh());
      unawaited(wellbeingEbooks.refresh());
      unawaited(unread.refresh());
    } else {
      consultation.reset();
      unread.clear();
    }
  });
  unawaited(notifications.start());
  StartupTrace.mark('initializations/scheduled');

  runApp(
    AuryelApp(
      state: state,
      auth: auth,
      consultation: consultation,
      wellbeing: wellbeing,
      wellbeingProgram: wellbeingProgram,
      wellbeingEbooks: wellbeingEbooks,
      rewards: rewards,
      purchase: purchase,
      notifications: notifications,
      analytics: firstPartyAnalytics,
      metaEvents: metaEvents,
      metaConsent: metaConsent,
      content: content,
      unread: unread,
    ),
  );
  StartupTrace.mark('runApp-called');
}

class AuryelApp extends StatefulWidget {
  const AuryelApp({
    super.key,
    required this.state,
    required this.auth,
    required this.consultation,
    this.wellbeing,
    this.wellbeingProgram,
    this.wellbeingEbooks,
    this.rewards,
    this.purchase,
    this.notifications,
    this.analytics,
    this.metaEvents,
    this.metaConsent,
    this.content,
    this.unread,
  });

  final AuryelState state;
  final AuthController auth;
  final ConsultationController consultation;

  /// AUDIT ACCUEIL/PARCOURS — optionnel : quand fourni (cas réel de `main()`),
  /// l'arbre est enveloppé d'un [WellbeingScope] PARTAGÉ par Accueil et
  /// « Mon parcours bien-être ». Absent des tests hérités qui ne touchent pas
  /// au parcours bien-être — ces écrans retombent alors sur leur ancien
  /// comportement (contrôleur local / repli local).
  final WellbeingController? wellbeing;
  final WellbeingProgramController? wellbeingProgram;
  final WellbeingEbooksController? wellbeingEbooks;

  /// GROS CHANTIER AURYEL (Prompt 2/5) — optionnel : quand fourni (cas réel
  /// de `main()`), l'arbre est enveloppé d'un [RewardsScope] PARTAGÉ par le
  /// header Accueil et l'écran « Mes Étoiles ». Absent des tests hérités qui
  /// ne touchent pas aux Étoiles.
  final RewardsController? rewards;

  /// Optionnel : contenu distant (pensée du jour + méditations). Quand fourni,
  /// l'arbre est enveloppé d'un [ContentScope]. Absent des tests hérités ->
  /// les écrans lisent le contenu embarqué comme avant.
  final ContentRepository? content;
  final UnreadController? unread;

  /// F5-B — optionnel : quand fourni (cas réel de `main()`), l'arbre est
  /// enveloppé d'un [PurchaseScope]. Absent dans les tests hérités qui ne
  /// touchent pas à l'achat.
  final PurchaseController? purchase;

  /// Optionnel : quand fourni, l'arbre est enveloppé d'un [NotificationScope]
  /// et le coordinateur est disposé avec l'app. Absent des tests hérités.
  final NotificationCoordinator? notifications;
  final FirstPartyAnalytics? analytics;

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
  bool _wasBackgrounded = false;
  bool _routingToLogin = false;
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _wakeAlarmPlatformChannel = MethodChannel('auryel/wake_alarm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_handleAuthChanged);
    _wakeAlarmPlatformChannel.setMethodCallHandler(_handleWakeAlarmCall);
    final notifications = widget.notifications;
    if (notifications != null) {
      final presenter = LocalNotificationPresenter()
        ..onSelect = notifications.handleForegroundTap;
      unawaited(presenter.initialize());
      _foregroundSub = notifications.onForegroundMessage.listen((payload) {
        widget.unread?.noteConsultationAdvisor(
          payload.type == NotificationType.personalGuidance
              ? payload.advisor
              : null,
        );
        unawaited(presenter.show(payload));
        unawaited(widget.unread?.refresh() ?? Future<void>.value());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_handleAuthChanged);
    _foregroundSub?.cancel();
    widget.notifications?.dispose();
    _wakeAlarmPlatformChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleWakeAlarmCall(MethodCall call) async {
    if (call.method != 'wakeRingingIntent') return;
    unawaited(widget.analytics?.log('wake_triggered') ?? Future<void>.value());
    final raw = call.arguments;
    final map = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final video = WakeVideo.tryFromJson({
      'id': map['wakeVideoId'],
      'video_url': map['wakeVideoUrl'],
      'title': map['wakeVideoTitle'],
    });
    if (!mounted || video == null) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => WakeRingingScreen(video: video)),
    );
  }

  void _handleAuthChanged() {
    if (!mounted || widget.auth.status != AuthStatus.sessionExpired) return;
    if (_routingToLogin) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _routingToLogin = true;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
    }
    // Retour de l'arrière-plan : une seule resynchro par passage au premier
    // plan — portefeuille (`/state`) ET liste des consultations (`/list`, J6-F2)
    // pour que « Consultations en cours » reflète l'activité la plus récente.
    if (state == AppLifecycleState.resumed && widget.auth.isSignedIn) {
      widget.consultation.refreshAll();
      unawaited(widget.unread?.refresh() ?? Future<void>.value());
      widget.wellbeing?.refresh();
      widget.wellbeingProgram?.refresh();
      widget.wellbeingEbooks?.refresh();
      widget.rewards?.refresh();
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        unawaited(
          AuryelAds.instance.showAppOpenIfEligible(
            // Le statut Premium inconnu ne doit jamais être traité comme
            // Free : une App Open ne peut être tentée qu'après un état quota
            // réellement fourni par le backend.
            isFree:
                widget.consultation.quota != null &&
                widget.consultation.quota!.isPremium == false,
            authenticated: widget.auth.isSignedIn,
            onboardingComplete:
                widget.state.onboardingCompleted &&
                !AuryelAds.instance.onboardingFlowActive,
            blocked: widget.consultation.hasActiveSession,
          ),
        );
      }
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
          navigatorKey: _navigatorKey,
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
    final wellbeing = widget.wellbeing;
    if (wellbeing != null) {
      tree = WellbeingScope(controller: wellbeing, child: tree);
    }
    final wellbeingProgram = widget.wellbeingProgram;
    if (wellbeingProgram != null) {
      tree = WellbeingProgramScope(controller: wellbeingProgram, child: tree);
    }
    final wellbeingEbooks = widget.wellbeingEbooks;
    if (wellbeingEbooks != null) {
      tree = WellbeingEbooksScope(controller: wellbeingEbooks, child: tree);
    }
    final rewards = widget.rewards;
    if (rewards != null) {
      tree = RewardsScope(controller: rewards, child: tree);
    }
    final unread = widget.unread;
    if (unread != null) {
      tree = UnreadScope(controller: unread, child: tree);
    }
    final analytics = widget.analytics;
    if (analytics != null) {
      tree = FirstPartyAnalyticsScope(analytics: analytics, child: tree);
    }
    return AuthScope(
      controller: widget.auth,
      child: ConsultationScope(controller: widget.consultation, child: tree),
    );
  }
}

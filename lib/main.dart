import 'dart:async';

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/billing_api.dart';
import 'api/consultation_api.dart';
import 'api/profile_api.dart';
import 'api/tirage_api.dart';
import 'data/auth_repository.dart';
import 'data/iap_gateway.dart';
import 'data/onboarding_repository.dart';
import 'data/token_store.dart';
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

  runApp(
    AuryelApp(
      state: state,
      auth: auth,
      consultation: consultation,
      purchase: purchase,
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
  });

  final AuryelState state;
  final AuthController auth;
  final ConsultationController consultation;

  /// F5-B — optionnel : quand fourni (cas réel de `main()`), l'arbre est
  /// enveloppé d'un [PurchaseScope]. Absent dans les tests hérités qui ne
  /// touchent pas à l'achat.
  final PurchaseController? purchase;

  @override
  State<AuryelApp> createState() => _AuryelAppState();
}

class _AuryelAppState extends State<AuryelApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour de l'arrière-plan : une seule resynchro par passage au premier plan.
    if (state == AppLifecycleState.resumed && widget.auth.isSignedIn) {
      widget.consultation.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tree = AuryelStateScope(
      state: widget.state,
      child: MaterialApp(
        title: 'Auryel',
        debugShowCheckedModeBanner: false,
        theme: AuryelTheme.dark,
        home: const SplashScreen(),
      ),
    );
    final purchase = widget.purchase;
    if (purchase != null) {
      tree = PurchaseScope(controller: purchase, child: tree);
    }
    return AuthScope(
      controller: widget.auth,
      child: ConsultationScope(controller: widget.consultation, child: tree),
    );
  }
}

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/consultation_api.dart';
import 'api/profile_api.dart';
import 'data/auth_repository.dart';
import 'data/onboarding_repository.dart';
import 'data/token_store.dart';
import 'screens/splash_screen.dart';
import 'state/auryel_state.dart';
import 'state/auth_controller.dart';
import 'state/consultation_controller.dart';
import 'theme/auryel_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = LocalOnboardingRepository();
  final record = await repository.load();
  final state = AuryelState(repository: repository, initial: record);

  final apiClient = ApiClient();
  final consultationApi = ConsultationApi(apiClient);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(apiClient),
      tokenStore: SecureTokenStore(),
    ),
    profileApi: ProfileApi(apiClient),
    consultationApi: consultationApi,
  );
  final consultation = ConsultationController(api: consultationApi, auth: auth);

  runApp(AuryelApp(state: state, auth: auth, consultation: consultation));
}

class AuryelApp extends StatefulWidget {
  const AuryelApp({
    super.key,
    required this.state,
    required this.auth,
    required this.consultation,
  });

  final AuryelState state;
  final AuthController auth;
  final ConsultationController consultation;

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
    return AuthScope(
      controller: widget.auth,
      child: ConsultationScope(
        controller: widget.consultation,
        child: AuryelStateScope(
          state: widget.state,
          child: MaterialApp(
            title: 'Auryel',
            debugShowCheckedModeBanner: false,
            theme: AuryelTheme.dark,
            home: const SplashScreen(),
          ),
        ),
      ),
    );
  }
}

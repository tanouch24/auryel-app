import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/profile_api.dart';
import 'data/auth_repository.dart';
import 'data/onboarding_repository.dart';
import 'data/token_store.dart';
import 'screens/splash_screen.dart';
import 'state/auryel_state.dart';
import 'state/auth_controller.dart';
import 'theme/auryel_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = LocalOnboardingRepository();
  final record = await repository.load();
  final state = AuryelState(repository: repository, initial: record);

  final apiClient = ApiClient();
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(apiClient),
      tokenStore: SecureTokenStore(),
    ),
    profileApi: ProfileApi(apiClient),
  );

  runApp(AuryelApp(state: state, auth: auth));
}

class AuryelApp extends StatelessWidget {
  const AuryelApp({super.key, required this.state, required this.auth});

  final AuryelState state;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      controller: auth,
      child: AuryelStateScope(
        state: state,
        child: MaterialApp(
          title: 'Auryel',
          debugShowCheckedModeBanner: false,
          theme: AuryelTheme.dark,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

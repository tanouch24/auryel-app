import 'package:flutter/material.dart';

import 'data/onboarding_repository.dart';
import 'screens/splash_screen.dart';
import 'state/auryel_state.dart';
import 'theme/auryel_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = LocalOnboardingRepository();
  final record = await repository.load();
  final state = AuryelState(repository: repository, initial: record);
  runApp(AuryelApp(state: state));
}

class AuryelApp extends StatelessWidget {
  const AuryelApp({super.key, required this.state});

  final AuryelState state;

  @override
  Widget build(BuildContext context) {
    return AuryelStateScope(
      state: state,
      child: MaterialApp(
        title: 'Auryel',
        debugShowCheckedModeBanner: false,
        theme: AuryelTheme.dark,
        home: const SplashScreen(),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../state/auryel_state.dart';
import '../state/auth_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/main_nav_shell.dart';
import 'onboarding/advisor_selection_screen.dart';
import 'onboarding/email_auth_screen.dart';

/// Écran d'ouverture : le wordmark s'illumine, court et élégant (~2s), pendant
/// que la session est restaurée en arrière-plan, puis fondu vers l'écran
/// approprié. Vu à chaque lancement — ne doit jamais lasser.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Après la première frame : le contexte peut alors résoudre les scopes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    // Restauration de session + durée mini de splash, en parallèle.
    final auth = AuthScope.of(context);
    await Future.wait([
      auth.restore(),
      Future<void>.delayed(const Duration(milliseconds: 2000)),
    ]);
    if (!mounted) return;
    _goToNext(auth);
  }

  void _goToNext(AuthController auth) {
    if (!mounted) return;
    final onboardingCompleted =
        AuryelStateScope.of(context).onboardingCompleted;

    final Widget next;
    if (!onboardingCompleted) {
      // Parcours d'onboarding depuis le début (le login OTP en est l'étape 5).
      next = const AdvisorSelectionScreen();
    } else {
      // Onboarding terminé : SEUL un vrai jeton donne accès à l'app.
      // Un onboarding local terminé et/ou un ancien `temp_xxx` ne comptent
      // jamais comme une authentification.
      switch (auth.status) {
        case AuthStatus.signedIn:
        case AuthStatus.networkError:
          // Jeton présent et accepté, OU présent mais backend momentanément
          // injoignable (jeton conservé) → accueil, éventuellement en mode
          // dégradé/offline.
          next = const MainNavShell();
        case AuthStatus.signedOut:
        case AuthStatus.sessionExpired:
        case AuthStatus.unknown:
          // Aucun jeton, ou jeton rejeté en 401 (déjà purgé) → connexion.
          next = const EmailAuthScreen();
      }
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, secondaryAnimation) => next,
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _Halo()
                    .animate()
                    .fadeIn(duration: 1300.ms, curve: Curves.easeOut)
                    .scale(
                      begin: const Offset(0.55, 0.55),
                      end: const Offset(1, 1),
                      duration: 1500.ms,
                      curve: Curves.easeOutCubic,
                    ),
                _SplashWordmark()
                    .animate()
                    .fadeIn(
                      delay: 150.ms,
                      duration: 850.ms,
                      curve: Curves.easeOut,
                    )
                    .slideY(
                      begin: 0.06,
                      end: 0,
                      delay: 150.ms,
                      duration: 850.ms,
                      curve: Curves.easeOutCubic,
                    ),
              ],
            ),
            const SizedBox(height: 22),
            _SplashOrnament()
                .animate()
                .fadeIn(delay: 950.ms, duration: 450.ms)
                .scaleXY(
                  begin: 0,
                  end: 1,
                  delay: 950.ms,
                  duration: 500.ms,
                  curve: Curves.easeOutCubic,
                ),
          ],
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AuryelColors.gold.withValues(alpha: 0.22),
            AuryelColors.gold.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

class _SplashWordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) =>
          AuryelColors.goldGradient.createShader(bounds),
      child: Text(
        'AURYEL',
        style: AuryelText.display(
          fontSize: 38,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 9,
        ),
      ),
    );
  }
}

class _SplashOrnament extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.45),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
        Container(
          width: 26,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.45),
        ),
      ],
    );
  }
}

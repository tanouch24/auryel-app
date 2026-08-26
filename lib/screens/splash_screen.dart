import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../state/auryel_state.dart';
import '../theme/auryel_theme.dart';
import '../widgets/main_nav_shell.dart';
import 'onboarding/advisor_selection_screen.dart';

/// Écran d'ouverture : le wordmark s'illumine, court et élégant (~2,2s),
/// puis fondu vers l'accueil. Vu à chaque lancement — ne doit jamais lasser.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2000), _goToNext);
  }

  void _goToNext() {
    if (!mounted) return;
    // Onboarding déjà terminé (restauré depuis la persistance mock) → accueil
    // direct. Sinon → parcours d'onboarding, à chaque fois depuis le début.
    final onboardingCompleted = AuryelStateScope.of(context)
        .onboardingCompleted;
    final next = onboardingCompleted
        ? const MainNavShell()
        : const AdvisorSelectionScreen();
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

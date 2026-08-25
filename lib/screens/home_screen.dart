import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';

/// Écran d'accueil "Consulter". Contenu en dur pour l'instant — structuré
/// pour être branché sur des données réelles (phrase du jour, conseiller
/// assigné) plus tard.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AuryelColors.backgroundGradient),
      child: Stack(
        children: [
          // Halo chaud radial derrière la phrase du jour — chaleur subtile mais perceptible.
          Positioned(
            top: 210,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AuryelColors.gold.withValues(alpha: 0.16),
                        AuryelColors.gold.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Wordmark().animate().fadeIn(duration: 600.ms),
                  const SizedBox(height: 10),
                  Text(
                    'MARDI 25 AOÛT · ESPACE PRIVÉ',
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AuryelColors.textMuted,
                      letterSpacing: 2.4,
                    ),
                  ).animate().fadeIn(delay: 150.ms, duration: 600.ms),
                  const SizedBox(height: 56),
                  const _Ornament().animate().fadeIn(delay: 250.ms, duration: 600.ms),
                  const SizedBox(height: 22),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: AuryelText.display(
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        height: 1.32,
                      ),
                      children: [
                        const TextSpan(text: 'Ce que tu n’oses pas regarder '),
                        TextSpan(
                          text: 'te dirige.',
                          style: AuryelText.display(
                            fontSize: 30,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            color: AuryelColors.goldLight,
                            height: 1.32,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 350.ms, duration: 700.ms).slideY(
                        begin: 0.08,
                        end: 0,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 28),
                  _TapToRead().animate().fadeIn(delay: 550.ms, duration: 600.ms),
                  const SizedBox(height: 44),
                  const _AdvisorPanel().animate().fadeIn(delay: 650.ms, duration: 600.ms).slideY(
                        begin: 0.06,
                        end: 0,
                        curve: Curves.easeOutCubic,
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _thinRule(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ShaderMask(
            shaderCallback: (bounds) => AuryelColors.goldGradient.createShader(bounds),
            child: Text(
              'AURYEL',
              style: AuryelText.display(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 6,
              ),
            ),
          ),
        ),
        _thinRule(),
      ],
    );
  }

  Widget _thinRule() {
    return Container(
      width: 34,
      height: 1,
      color: AuryelColors.gold.withValues(alpha: 0.55),
    );
  }
}

class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 22, height: 1, color: AuryelColors.gold.withValues(alpha: 0.4)),
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
        Container(width: 22, height: 1, color: AuryelColors.gold.withValues(alpha: 0.4)),
      ],
    );
  }
}

class _TapToRead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'TOUCHER POUR LIRE',
          style: AuryelText.body(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AuryelColors.textMuted,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        PhosphorIcon(
          PhosphorIconsThin.caretDown,
          size: 16,
          color: AuryelColors.textMuted,
        ),
      ],
    );
  }
}

class _AdvisorPanel extends StatelessWidget {
  const _AdvisorPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuryelColors.goldGradient,
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AuryelColors.surfaceLight,
              ),
              child: Center(
                child: PhosphorIcon(
                  PhosphorIconsFill.moonStars,
                  color: AuryelColors.goldLight,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Séléna',
                  style: AuryelText.display(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  't’accompagne aujourd’hui',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          PhosphorIcon(
            PhosphorIconsRegular.caretRight,
            size: 18,
            color: AuryelColors.gold.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }
}

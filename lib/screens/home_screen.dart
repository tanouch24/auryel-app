import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/auryel_theme.dart';
import 'placeholder_screen.dart';

// La phrase du jour, en dur pour l'instant — factorisée pour que l'affichage
// (RichText) et le partage restent synchronisés sans dupliquer le texte.
const _dailyPhraseLead = 'Ce que tu n’oses pas regarder ';
const _dailyPhraseAccent = 'te dirige.';
const _dailyPhrase = '$_dailyPhraseLead$_dailyPhraseAccent';

/// Écran d'accueil "Accueil". Contenu en dur pour l'instant — structuré
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
            top: 150,
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
                children: [
                  const SizedBox(height: 56),
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
                        const TextSpan(text: _dailyPhraseLead),
                        TextSpan(
                          text: _dailyPhraseAccent,
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
                  const SizedBox(height: 20),
                  const _ShareButton().animate().fadeIn(delay: 600.ms, duration: 600.ms),
                ],
              ),
            ),
          ),
          // Icône profil ancrée en haut de l'écran, indépendante du bloc de
          // contenu centré — mène à l'écran "Espace" (placeholder).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlaceholderScreen(
                          title: 'Mon espace',
                          icon: PhosphorIconsRegular.userCircle,
                          subtitle: 'Bientôt, ton espace personnel.',
                        ),
                      ),
                    ),
                    icon: PhosphorIcon(
                      PhosphorIconsThin.userCircle,
                      size: 22,
                      color: AuryelColors.textMuted,
                    ),
                    splashRadius: 20,
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
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
          'Découvrir le message du jour',
          style: AuryelText.body(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AuryelColors.textMuted,
            letterSpacing: 0.3,
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

class _ShareButton extends StatelessWidget {
  const _ShareButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => SharePlus.instance.share(
          ShareParams(text: '$_dailyPhrase\n\n— Auryel'),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.shareNetwork,
                size: 15,
                color: AuryelColors.goldLight,
              ),
              const SizedBox(width: 8),
              Text(
                'Partager',
                style: AuryelText.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AuryelColors.goldLight,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

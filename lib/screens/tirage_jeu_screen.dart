import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';
import 'jeu_auryel_screen.dart';
import 'tirage_screen.dart';

/// Hub du 2ᵉ onglet « Tirage & Jeu » — CONSACRÉ au tirage / aux expériences de
/// jeu. Le parcours bien-être n'est PLUS présenté ici : il a son CTA dédié sur
/// l'Accueil (« Suivre mon parcours bien-être »).
/// Ne duplique AUCUNE logique de tirage : l'entrée Tirage ouvre le vrai
/// [TirageScreen].
class TirageJeuScreen extends StatelessWidget {
  const TirageJeuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuryelWordmarkTitle(),
              const SizedBox(height: 4),
              Text(
                'Tirage & Jeu',
                textAlign: TextAlign.center,
                style: AuryelText.display(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Écoute ton intuition, tire les cartes ou relève un défi.',
                textAlign: TextAlign.center,
                style: AuryelText.body(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AuryelColors.textMuted,
                ),
              ),
              const SizedBox(height: 22),
              _HubCard(
                overline: 'TIRAGE',
                icon: PhosphorIconsRegular.cardsThree,
                title: 'Tire tes trois cartes',
                body:
                    'Choisis toi-même tes cartes et reçois une lecture claire '
                    'de ta situation.',
                ctaLabel: 'Faire mon tirage',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const TirageScreen())),
              ),
              const SizedBox(height: 14),
              _HubCard(
                overline: 'JEU AURYEL',
                icon: PhosphorIconsRegular.puzzlePiece,
                title: 'Le Jeu Auryel',
                body:
                    'Un jeu de mémoire pour ralentir et revenir à toi. Trois '
                    'niveaux, parties illimitées.',
                ctaLabel: 'Jouer',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const JeuAuryelScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit mot-symbole discret en tête de hub (réutilise le lettrage Auryel).
class AuryelWordmarkTitle extends StatelessWidget {
  const AuryelWordmarkTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'AURYEL',
      textAlign: TextAlign.center,
      style: AuryelText.body(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AuryelColors.gold,
        letterSpacing: 4,
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.overline,
    required this.icon,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onTap,
  });

  final String overline;
  final IconData icon;
  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $ctaLabel',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AuryelColors.surface.withValues(alpha: 0.55),
              border: Border.all(color: AuryelColors.warmBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AuryelColors.gold.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AuryelColors.goldLight.withValues(alpha: 0.55),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: PhosphorIcon(
                        icon,
                        size: 20,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      overline,
                      style: AuryelText.body(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.gold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: AuryelText.display(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: AuryelText.body(
                    fontSize: 12,
                    height: 1.4,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      ctaLabel,
                      style: AuryelText.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const PhosphorIcon(
                      PhosphorIconsRegular.arrowRight,
                      size: 13,
                      color: AuryelColors.goldLight,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

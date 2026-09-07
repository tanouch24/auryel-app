import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/experience_intro_store.dart';
import '../theme/auryel_theme.dart';
import '../widgets/auryel_wordmark.dart';
import '../widgets/gold_button.dart';
import '../widgets/main_nav_shell.dart';

/// « Bienvenue dans Auryel » — écran premium de TRANSITION, affiché UNE FOIS
/// automatiquement juste après la création du compte + la synchro du profil.
/// C'est LE DERNIER écran du parcours initial : au tap sur « Découvrir Auryel »,
/// l'utilisateur entre dans l'app (MainNavShell). Aucun autre écran entre.
///
/// Rejouable depuis le Dashboard via [fromDashboard] = true (le flag n'est
/// alors pas touché, le CTA devient « Retour à Auryel »).
///
/// Ce n'est PAS une étape d'onboarding : pas de puces de progression, pas de
/// « Continuer » de formulaire, un seul écran scrollable. L'expérience se
/// RÉVÈLE progressivement (fade + slide décalés, court glow doré sur les
/// icônes, shimmer limité du CTA). Toutes les animations sont FINIES et
/// respectent « réduire les animations » (MediaQuery.disableAnimations).
class AuryelExperienceScreen extends StatelessWidget {
  const AuryelExperienceScreen({
    super.key,
    this.fromDashboard = false,
    this.store,
  });

  /// `true` quand ouvert manuellement depuis le Dashboard (replay).
  final bool fromDashboard;

  /// Injectable pour les tests.
  final ExperienceIntroStore? store;

  static const _slogan =
      'Auryel réinvente la voyance et la méditation pour en faire une '
      'véritable expérience quotidienne, personnelle et immersive.';

  static const _blocks = <_ExperienceBlock>[
    _ExperienceBlock(
      icon: PhosphorIconsRegular.sparkle,
      title: 'Ton conseiller',
      text:
          'Choisis le conseiller qui te correspond et retrouve-le dans '
          'ton expérience Auryel.',
    ),
    _ExperienceBlock(
      icon: PhosphorIconsRegular.sun,
      title: 'Ta pensée du jour',
      text:
          'Une nouvelle pensée t’accompagne chaque jour, avec son '
          'interprétation.',
    ),
    _ExperienceBlock(
      icon: PhosphorIconsRegular.cardsThree,
      title: 'Tes tirages',
      text:
          'Tire les cartes et découvre une interprétation adaptée à ton '
          'tirage.',
    ),
    _ExperienceBlock(
      icon: PhosphorIconsRegular.flowerLotus,
      title: 'Ton moment',
      text: 'Retrouve chaque jour un moment de méditation et de recentrage.',
    ),
    _ExperienceBlock(
      icon: PhosphorIconsRegular.shareNetwork,
      title: 'Partage & récompenses',
      text:
          'Partage les contenus Auryel et suis ta progression vers les '
          'récompenses proposées dans l’application.',
    ),
    _ExperienceBlock(
      icon: PhosphorIconsRegular.gameController,
      title: 'Le Jeu Auryel',
      text: 'Joue, progresse et débloque de nouvelles expériences Auryel.',
    ),
    _ExperienceBlock(
      icon: PhosphorIconsRegular.storefront,
      title: 'Boutique Auryel',
      text: 'Une sélection Auryel arrivera dans une prochaine mise à jour.',
      badge: 'À venir',
    ),
  ];

  Future<void> _discover(BuildContext context) async {
    // Ne touche le flag QUE dans le parcours automatique.
    await (store ?? ExperienceIntroStore()).markSeen();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anim = !MediaQuery.disableAnimationsOf(context);
    final haloSize = math.min(420.0, MediaQuery.sizeOf(context).width * 1.15);

    // Cadence de révélation.
    const wordmarkMs = 0;
    const titleMs = 260;
    const sloganMs = 460;
    const overlineMs = 660;
    const firstCardMs = 780;
    const cardStepMs = 85;
    final ctaMs = firstCardMs + _blocks.length * cardStepMs + 120;

    Widget reveal(
      Widget child, {
      required int delayMs,
      double slide = 0.14,
      int durationMs = 460,
    }) {
      if (!anim) return child;
      return child
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: delayMs),
            duration: Duration(milliseconds: durationMs),
            curve: Curves.easeOut,
          )
          .slideY(
            begin: slide,
            end: 0,
            delay: Duration(milliseconds: delayMs),
            duration: Duration(milliseconds: durationMs),
            curve: Curves.easeOutCubic,
          );
    }

    Widget cta = AuryelGoldButton(
      label: fromDashboard ? 'Retour à Auryel' : 'Découvrir Auryel',
      onTap: fromDashboard
          ? () => Navigator.of(context).maybePop()
          : () => _discover(context),
    );
    if (anim) {
      cta = cta
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: ctaMs),
            duration: 420.ms,
          )
          .slideY(
            begin: 0.2,
            end: 0,
            delay: Duration(milliseconds: ctaMs),
            duration: 420.ms,
            curve: Curves.easeOutCubic,
          )
          .then(delay: 220.ms)
          .shimmer(
            duration: 1200.ms,
            color: AuryelColors.goldLight.withValues(alpha: 0.45),
          )
          .then(delay: 1600.ms)
          .shimmer(
            duration: 1200.ms,
            color: AuryelColors.goldLight.withValues(alpha: 0.4),
          );
    }

    return Scaffold(
      backgroundColor: AuryelColors.backgroundDeep,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: Stack(
          children: [
            // Profondeur : halo doré radial haut + voile sombre en bas.
            Positioned(
              top: -haloSize * 0.32,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: haloSize,
                    height: haloSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AuryelColors.gold.withValues(alpha: 0.15),
                          AuryelColors.gold.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00120E17), Color(0x66120E17)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (fromDashboard)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                tooltip: 'Retour',
                                visualDensity: VisualDensity.compact,
                                icon: const PhosphorIcon(
                                  PhosphorIconsRegular.arrowLeft,
                                  size: 20,
                                  color: AuryelColors.textMuted,
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          reveal(
                            const Center(
                              child: AuryelWordmark(
                                fontSize: 26,
                                letterSpacing: 6,
                              ),
                            ),
                            delayMs: wordmarkMs,
                            slide: -0.2,
                            durationMs: 520,
                          ),
                          const SizedBox(height: 14),
                          reveal(
                            const Center(child: _Ornament()),
                            delayMs: titleMs - 80,
                            slide: 0,
                          ),
                          const SizedBox(height: 20),
                          reveal(
                            Text(
                              'Bienvenue dans Auryel',
                              textAlign: TextAlign.center,
                              style: AuryelText.display(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            delayMs: titleMs,
                          ),
                          const SizedBox(height: 14),
                          reveal(
                            Text(
                              _slogan,
                              textAlign: TextAlign.center,
                              style: AuryelText.body(
                                fontSize: 13.5,
                                height: 1.62,
                                color: AuryelColors.textSecondary,
                              ),
                            ),
                            delayMs: sloganMs,
                          ),
                          const SizedBox(height: 30),
                          reveal(
                            Text(
                              'TON EXPÉRIENCE AURYEL',
                              textAlign: TextAlign.center,
                              style: AuryelText.body(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AuryelColors.gold,
                                letterSpacing: 2.6,
                              ),
                            ),
                            delayMs: overlineMs,
                          ),
                          const SizedBox(height: 16),
                          for (var i = 0; i < _blocks.length; i++) ...[
                            reveal(
                              _ExperienceCard(
                                block: _blocks[i],
                                animate: anim,
                                glowDelayMs: firstCardMs + i * cardStepMs + 120,
                              ),
                              delayMs: firstCardMs + i * cardStepMs,
                              durationMs: 420,
                            ),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: cta,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filet or + losange, réutilisé de l'accueil pour l'impact haut.
class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    Widget rule() => Container(
      width: 26,
      height: 1,
      color: AuryelColors.gold.withValues(alpha: 0.45),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        rule(),
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
        rule(),
      ],
    );
  }
}

class _ExperienceBlock {
  const _ExperienceBlock({
    required this.icon,
    required this.title,
    required this.text,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? badge;
}

class _ExperienceCard extends StatelessWidget {
  const _ExperienceCard({
    required this.block,
    this.animate = false,
    this.glowDelayMs = 0,
  });

  final _ExperienceBlock block;
  final bool animate;
  final int glowDelayMs;

  @override
  Widget build(BuildContext context) {
    Widget iconBadge = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [AuryelColors.surfaceLight, AuryelColors.surface],
        ),
        border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.4)),
      ),
      child: PhosphorIcon(block.icon, size: 18, color: AuryelColors.goldLight),
    );
    if (animate) {
      // Court glow doré à l'apparition (fini) : le cercle « respire » une fois.
      iconBadge = iconBadge
          .animate()
          .scaleXY(
            begin: 0.82,
            end: 1,
            delay: Duration(milliseconds: glowDelayMs),
            duration: 380.ms,
            curve: Curves.easeOutBack,
          )
          .boxShadow(
            delay: Duration(milliseconds: glowDelayMs),
            duration: 900.ms,
            curve: Curves.easeOut,
            begin: const BoxShadow(color: Color(0x00000000)),
            end: BoxShadow(
              color: AuryelColors.gold.withValues(alpha: 0.28),
              blurRadius: 16,
              spreadRadius: -2,
            ),
          )
          .then()
          .boxShadow(
            duration: 900.ms,
            begin: BoxShadow(
              color: AuryelColors.gold.withValues(alpha: 0.28),
              blurRadius: 16,
              spreadRadius: -2,
            ),
            end: const BoxShadow(color: Color(0x00000000)),
          );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuryelColors.surfaceLight, AuryelColors.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconBadge,
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        block.title,
                        style: AuryelText.display(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (block.badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AuryelColors.gold.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          block.badge!,
                          style: AuryelText.body(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AuryelColors.goldLight,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  block.text,
                  style: AuryelText.body(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

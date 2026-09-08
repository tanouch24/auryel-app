import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/auryel_state.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';

/// Une carte du jeu — texte SIMULÉ pour l'instant (même logique que le
/// portrait d'onboarding : contenu statique côté client, structuré pour
/// qu'une vraie interprétation serveur remplace `interpretation` au Temps 2).
/// Noms et interprétations repris du système `CARTES` déjà en place côté
/// bot (`auryel-1/auryel_bot.py`), pour rester cohérent avec le futur tirage réel.
class TarotCard {
  const TarotCard({
    required this.name,
    required this.suitIcon,
    required this.interpretation,
  });

  final String name;
  final PhosphorIconData suitIcon;
  final String interpretation;
}

const List<TarotCard> kMockTarotCards = [
  TarotCard(
    name: 'L’As de Cœur',
    suitIcon: PhosphorIconsFill.heart,
    interpretation: 'Un nouveau commencement dans l’amour. Une émotion pure qui cherche à s’exprimer.',
  ),
  TarotCard(
    name: 'Le Neuf de Cœur',
    suitIcon: PhosphorIconsFill.heart,
    interpretation: 'La carte des vœux exaucés. Ce que le cœur désire profondément se manifeste.',
  ),
  TarotCard(
    name: 'La Dame de Cœur',
    suitIcon: PhosphorIconsFill.heart,
    interpretation:
        'La voix du cœur et de l’intuition. Une présence aimante, tout près.',
  ),
  TarotCard(
    name: 'L’As de Carreau',
    suitIcon: PhosphorIconsFill.diamond,
    interpretation:
        'Un nouveau départ concret. Une opportunité se présente, tangible.',
  ),
  TarotCard(
    name: 'Le Six de Carreau',
    suitIcon: PhosphorIconsFill.diamond,
    interpretation: 'La générosité. Ce que tu donnes te revient, multiplié.',
  ),
  TarotCard(
    name: 'L’As de Trèfle',
    suitIcon: PhosphorIconsFill.club,
    interpretation: 'Une idée qui germe, et qui pourrait tout changer.',
  ),
  TarotCard(
    name: 'Le Neuf de Trèfle',
    suitIcon: PhosphorIconsFill.club,
    interpretation: 'Tu as traversé beaucoup. Tu peux faire face à ceci aussi.',
  ),
  TarotCard(
    name: 'L’As de Pique',
    suitIcon: PhosphorIconsFill.spade,
    interpretation:
        'Une transformation profonde s’annonce. Une vérité cherche à se dire.',
  ),
  TarotCard(
    name: 'Le Cinq de Pique',
    suitIcon: PhosphorIconsFill.spade,
    interpretation:
        'Une épreuve, mais temporaire. Ce qui suit se construit plus solide.',
  ),
  TarotCard(
    name: 'Le Roi de Cœur',
    suitIcon: PhosphorIconsFill.heart,
    interpretation: 'La sagesse du cœur. Une présence protectrice, discrète.',
  ),
];

/// Onglet "Mes cartes" — éventail de cartes face cachée, tirage tactile
/// (jamais servi d'office), révélation animée, interprétation simulée,
/// puis renvoi vers le conseiller choisi.
class MyCardsScreen extends StatefulWidget {
  const MyCardsScreen({super.key});

  @override
  State<MyCardsScreen> createState() => _MyCardsScreenState();
}

class _MyCardsScreenState extends State<MyCardsScreen> {
  TarotCard? _drawn;

  void _draw() {
    final card = kMockTarotCards[Random().nextInt(kMockTarotCards.length)];
    setState(() => _drawn = card);
  }

  void _reset() {
    setState(() => _drawn = null);
  }

  @override
  Widget build(BuildContext context) {
    final selectedAdvisor = AuryelStateScope.of(context).selectedAdvisor;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              Text(
                'Mes cartes du jour',
                style: AuryelText.display(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ).animate().fadeIn(duration: 500.ms),
              const SizedBox(height: 8),
              Text(
                _drawn == null
                    ? 'Touche une carte pour la tirer.'
                    : 'Ta carte du moment.',
                style: AuryelText.body(
                  fontSize: 13,
                  color: AuryelColors.textMuted,
                ),
              ).animate().fadeIn(delay: 150.ms, duration: 500.ms),
              Expanded(
                child: _drawn == null
                    ? _CardFan(onDraw: _draw)
                    : _RevealedCard(
                        card: _drawn!,
                        advisorFirstName: selectedAdvisor,
                        onDrawAgain: _reset,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Éventail de cartes face cachée, légèrement inclinées, tapables.
class _CardFan extends StatelessWidget {
  const _CardFan({required this.onDraw});

  final VoidCallback onDraw;

  static const _count = 8;
  static const _cardWidth = 76.0;
  static const _cardHeight = 112.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 340,
        height: 220,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: List.generate(_count, (i) {
            final mid = (_count - 1) / 2;
            final offset = i - mid;
            final angle = offset * 0.16; // radians — éventail serré et élégant
            final dx = offset * 30.0;
            final dy = -offset.abs() * 6.0; // léger arc : les bords remontent
            return Positioned(
              bottom: 20 + dy,
              left: 340 / 2 - _cardWidth / 2 + dx,
              child: Transform.rotate(
                angle: angle,
                alignment: Alignment.bottomCenter,
                child:
                    _CardBack(
                          width: _cardWidth,
                          height: _cardHeight,
                          onTap: onDraw,
                        )
                        .animate()
                        .fadeIn(delay: (60 * i).ms, duration: 400.ms)
                        .slideY(
                          begin: 0.15,
                          end: 0,
                          delay: (60 * i).ms,
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AuryelColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AuryelColors.gold.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: AuryelColors.backgroundDeep.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: AuryelColors.gold.withValues(alpha: 0.3),
                width: 0.6,
              ),
            ),
            child: Center(
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: AuryelColors.goldGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte révélée : face + nom + interprétation simulée + CTA conseiller.
class _RevealedCard extends StatelessWidget {
  const _RevealedCard({
    required this.card,
    required this.advisorFirstName,
    required this.onDrawAgain,
  });

  final TarotCard card;
  final String? advisorFirstName;
  final VoidCallback onDrawAgain;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        children: [
          Container(
                width: 190,
                height: 280,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AuryelColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AuryelColors.gold.withValues(alpha: 0.6),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AuryelColors.gold.withValues(alpha: 0.12),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AuryelColors.goldGradient.createShader(bounds),
                      child: PhosphorIcon(
                        card.suitIcon,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      card.name,
                      textAlign: TextAlign.center,
                      style: AuryelText.display(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 350.ms)
              .flip(
                direction: Axis.horizontal,
                begin: -0.5,
                end: 0,
                duration: 600.ms,
                curve: Curves.easeOut,
              )
              .scaleXY(
                begin: 0.85,
                end: 1,
                duration: 500.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 28),
          Text(
            card.interpretation,
            textAlign: TextAlign.center,
            style: AuryelText.display(
              fontSize: 17,
              fontStyle: FontStyle.italic,
              height: 1.5,
              color: AuryelColors.textCream,
            ),
          ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
          const SizedBox(height: 28),
          if (advisorFirstName != null)
            AuryelGoldButton(
                  label: 'En parler avec $advisorFirstName',
                  onTap: () {},
                )
                .animate()
                .fadeIn(delay: 700.ms, duration: 500.ms)
                .slideY(
                  begin: 0.08,
                  end: 0,
                  delay: 700.ms,
                  duration: 500.ms,
                  curve: Curves.easeOutCubic,
                ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: onDrawAgain,
            child: Text(
              'Tirer une autre carte',
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.textMuted,
              ),
            ),
          ).animate().fadeIn(delay: 850.ms, duration: 500.ms),
        ],
      ),
    );
  }
}

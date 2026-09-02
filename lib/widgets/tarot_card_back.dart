import 'package:flutter/material.dart';

import '../theme/auryel_theme.dart';

/// B8.4 — dos de carte : l'ASSET RÉEL fourni par l'utilisateur, utilisé tel
/// quel (`assets/images/tarot_card_back.png`, carte détourée sur fond
/// transparent). Aucun dessin programmatique, aucun `CustomPainter`.
///
/// Toutes les cartes de dos de l'app passent par ce widget : éventail + les 3
/// emplacements du tapis.
class TarotCardBack extends StatelessWidget {
  const TarotCardBack({super.key, this.selected = false});

  /// Carte choisie : léger halo doré (indication discrète). Le visuel de la
  /// carte lui-même n'est jamais modifié.
  final bool selected;

  /// Chemin de l'asset — exposé pour les tests.
  static const String asset = 'assets/images/tarot_card_back.png';

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(asset, fit: BoxFit.contain);
    if (!selected) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AuryelColors.gold.withValues(alpha: 0.45),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: image,
    );
  }
}

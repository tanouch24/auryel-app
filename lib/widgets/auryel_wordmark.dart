import 'package:flutter/material.dart';

import '../theme/auryel_theme.dart';

/// Wordmark « AURYEL » — dégradé or, Inter display, très espacé.
///
/// Composant partagé (accueil + Dashboard) pour garder une identité unique.
/// [rules] ajoute les deux filets fins de part et d'autre (accueil, centré) ;
/// à `false` pour un en-tête aligné à gauche (Dashboard).
class AuryelWordmark extends StatelessWidget {
  const AuryelWordmark({
    super.key,
    this.fontSize = 26,
    this.letterSpacing = 6,
    this.rules = true,
    this.alignment = MainAxisAlignment.center,
  });

  final double fontSize;
  final double letterSpacing;
  final bool rules;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final text = ShaderMask(
      shaderCallback: (bounds) =>
          AuryelColors.goldGradient.createShader(bounds),
      child: Text(
        'AURYEL',
        style: AuryelText.display(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: letterSpacing,
        ),
      ),
    );

    if (!rules) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignment,
      children: [
        _rule(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: text,
        ),
        _rule(),
      ],
    );
  }

  Widget _rule() => Container(
    width: 34,
    height: 1,
    color: AuryelColors.gold.withValues(alpha: 0.55),
  );
}

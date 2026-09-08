import 'package:flutter/material.dart';

import '../theme/auryel_theme.dart';

/// Wording de transparence IA — CANONIQUE, validé (30/07). Ne pas paraphraser
/// sans validation juridique. Affiché aux points de contact où l'utilisateur
/// échange avec un « conseiller » (chat), choisit un conseiller (onboarding) et
/// dans « Mon compte » (Informations & confidentialité).
const String kAiTransparencyText =
    'Une partie de nos échanges est gérée par une intelligence artificielle.';

/// Ligne de transparence IA, discrète mais toujours visible (jamais masquée,
/// jamais derrière un tap). Pensée pour ne pas casser l'immersion : petit,
/// atténué, une seule phrase.
class AiTransparencyNote extends StatelessWidget {
  const AiTransparencyNote({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    this.textAlign = TextAlign.center,
    this.fontSize = 10.5,
  });

  final EdgeInsetsGeometry padding;
  final TextAlign textAlign;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        // Lu par les lecteurs d'écran : la transparence reste accessible.
        label: kAiTransparencyText,
        child: Text(
          kAiTransparencyText,
          textAlign: textAlign,
          style: AuryelText.body(
            fontSize: fontSize,
            height: 1.35,
            color: AuryelColors.textMuted,
          ),
        ),
      ),
    );
  }
}

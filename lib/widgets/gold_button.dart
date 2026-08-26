import 'package:flutter/material.dart';

import '../theme/auryel_theme.dart';

/// Bouton or plein partagé par les écrans d'onboarding — action premium,
/// bien visible. (Widget nouveau, indépendant des boutons déjà en place
/// dans `consultation_block.dart` / `advisor_detail_screen.dart` pour ne
/// rien risquer sur l'existant.)
class AuryelGoldButton extends StatelessWidget {
  const AuryelGoldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled ? AuryelColors.goldGradient : null,
            color: enabled ? null : AuryelColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: enabled ? null : Border.all(color: AuryelColors.warmBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? AuryelColors.backgroundDeep
                        : AuryelColors.textMuted,
                    letterSpacing: 0.4,
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

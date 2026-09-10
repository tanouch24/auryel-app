import 'package:flutter/material.dart';

import '../state/meta_consent_controller.dart';
import '../theme/auryel_theme.dart';

/// Consentement EXPLICITE, non pré-coché et RÉVOCABLE à la mesure publicitaire
/// Meta. Rendu uniquement si un [MetaConsentController] est présent dans
/// l'arbre (config Meta fournie au build) — sinon `SizedBox.shrink()`.
///
/// Tant que l'interrupteur est sur OFF : aucune mesure, aucune collecte de
/// l'identifiant publicitaire, aucun événement transmis à Meta.
class MetaConsentTile extends StatelessWidget {
  const MetaConsentTile({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AnalyticsScope.consentOf(context);
    if (controller == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: AuryelColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AuryelColors.warmBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mesure publicitaire',
                      style: AuryelText.body(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Autoriser Auryel à mesurer l’efficacité de ses campagnes '
                      'avec Meta (installation, abonnement). Aucun message ni '
                      'donnée personnelle n’est transmis. Désactivable à tout '
                      'moment.',
                      style: AuryelText.body(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: controller.granted,
                onChanged: (v) => controller.setGranted(v),
                activeThumbColor: AuryelColors.gold,
              ),
            ],
          ),
        );
      },
    );
  }
}

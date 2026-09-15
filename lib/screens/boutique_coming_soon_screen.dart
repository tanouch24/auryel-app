import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';
import '../widgets/auryel_wordmark.dart';

/// Onglet « Boutique » (bottom nav, index 3) — **V1**.
///
/// La Boutique reste dans la navigation mais la vente n'est PAS lancée : cet
/// écran « À venir » est le seul contenu exposé à l'utilisateur. Le catalogue,
/// le panier, la fiche produit et le seam de paiement (`BoutiqueScreen`,
/// `CartScreen`, `ProductDetailScreen`, `ShopCartStore`, `ShopCheckoutService`)
/// restent dans le code, compilables, pour une future mise à jour — ils ne
/// sont simplement plus reliés à la navigation. Aucun prix, aucun produit,
/// aucun panier, aucun bouton « Commander », aucune date promise.
class BoutiqueComingSoonScreen extends StatelessWidget {
  const BoutiqueComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AuryelWordmark(fontSize: 22, letterSpacing: 5),
                  const SizedBox(height: 40),
                  // Halo doré discret derrière l'icône boutique.
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AuryelColors.gold.withValues(alpha: 0.18),
                                AuryelColors.gold.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                        const PhosphorIcon(
                          PhosphorIconsRegular.storefront,
                          size: 40,
                          color: AuryelColors.goldLight,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'BOUTIQUE AURYEL',
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.gold,
                      letterSpacing: 2.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bientôt disponible',
                    textAlign: TextAlign.center,
                    style: AuryelText.display(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nous préparons une sélection choisie avec soin — objets, '
                    'rituels et accessoires pensés pour tes moments Auryel. '
                    'La Boutique fera partie d’une prochaine mise à jour.',
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 13.5,
                      height: 1.6,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

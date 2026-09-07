import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/shop_product.dart';
import '../theme/auryel_theme.dart';

/// Visuel produit.
///
/// V1 : aucun asset réel -> **placeholder DA Auryel** (fond sombre, halo doré
/// léger, icône de catégorie ; le nom du produit s'ajoute en grand format
/// uniquement, la carte/fiche l'affichant déjà par ailleurs). Aucune image
/// externe, aucune photo photoréaliste. Si [ShopProduct.imageAsset] est
/// renseigné plus tard, il est affiché tel quel.
class ShopProductImage extends StatelessWidget {
  const ShopProductImage({
    super.key,
    required this.product,
    this.compact = false,
  });

  final ShopProduct product;

  /// `true` sur la grille / les vignettes ; `false` en fiche produit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final asset = product.imageAsset;
    if (asset != null) {
      return Image.asset(asset, fit: BoxFit.cover);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuryelColors.surfaceLight, AuryelColors.backgroundLow],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // halo doré discret
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.7,
              heightFactor: 0.7,
              child: DecoratedBox(
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
          Padding(
            padding: EdgeInsets.all(compact ? 10 : 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    child: PhosphorIcon(
                      product.category.icon,
                      size: compact ? 26 : 44,
                      color: AuryelColors.goldLight,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 14),
                  Flexible(
                    child: Text(
                      product.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.display(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

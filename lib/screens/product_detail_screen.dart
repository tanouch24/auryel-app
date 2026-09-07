import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/shop_cart_store.dart';
import '../data/shop_product.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';
import '../widgets/shop_product_image.dart';
import 'cart_screen.dart';

/// Fiche produit (Boutique V1.1).
///
/// Le CTA principal est « Ajouter au panier » : il alimente le panier LOCAL
/// ([ShopCartStore]). Aucun paiement ici — le tunnel d'achat réel (Stripe)
/// n'existe pas encore et partira du panier, jamais d'un « Acheter maintenant ».
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  final ShopProduct product;

  void _addToCart(BuildContext context) {
    final cart = ShopCartScope.of(context);
    cart.addProduct(product);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Ajouté au panier'),
          action: SnackBarAction(
            label: 'Voir',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Retour',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: const PhosphorIcon(
                      PhosphorIconsRegular.arrowLeft,
                      size: 20,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1.15,
                    child: ShopProductImage(product: product),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  product.category.label.toUpperCase(),
                  style: AuryelText.body(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.gold,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  product.name,
                  style: AuryelText.display(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.priceLabel,
                  style: AuryelText.display(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.goldLight,
                  ),
                ),
                if (product.badge != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const PhosphorIcon(
                        PhosphorIconsRegular.sealCheck,
                        size: 15,
                        color: AuryelColors.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          product.badge!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AuryelText.body(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AuryelColors.goldLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  product.shortDescription,
                  style: AuryelText.body(
                    fontSize: 13.5,
                    height: 1.55,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                // CTA = ajout au panier LOCAL. Pas de « Acheter maintenant » :
                // le paiement réel n'existe pas encore et partira du panier.
                AuryelGoldButton(
                  label: 'Ajouter au panier',
                  onTap: () => _addToCart(context),
                ),
                const SizedBox(height: 10),
                Text(
                  'Le paiement en ligne arrive bientôt. Tu peux déjà préparer '
                  'ton panier : les articles présentés sont une sélection en '
                  'préparation.',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 11,
                    height: 1.4,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

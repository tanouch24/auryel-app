import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/shop_cart_store.dart';
import '../data/shop_product.dart';
import '../theme/auryel_theme.dart';
import '../widgets/shop_product_image.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

/// Onglet « Boutique » (bottom nav, index 3).
///
/// V1 : catalogue **local** de produits physiques (démo UI), aucun checkout
/// réel. DA Auryel — fond sombre, or discret, cartes fines. Le Dashboard reste
/// hors bottom nav ; « Bibliothèque » n'est plus un onglet mais reste
/// accessible depuis « Mon parcours ».
class BoutiqueScreen extends StatefulWidget {
  const BoutiqueScreen({super.key});

  @override
  State<BoutiqueScreen> createState() => _BoutiqueScreenState();
}

class _BoutiqueScreenState extends State<BoutiqueScreen> {
  /// `null` = « Tout ».
  ShopCategory? _category;

  List<ShopProduct> get _visible => _category == null
      ? kShopProducts
      : kShopProducts.where((p) => p.category == _category).toList();

  void _open(ShopProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  void _openCart() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final featured = kShopProducts.where((p) => p.featured).toList();
    final products = _visible;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Boutique',
                        style: AuryelText.display(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _CartButton(onTap: _openCart),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Des objets choisis pour accompagner tes moments Auryel.',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AuryelColors.textMuted,
                  ),
                ),
                if (featured.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'À DÉCOUVRIR',
                    style: AuryelText.body(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.gold,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: featured.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _FeaturedCard(
                        product: featured[i],
                        onTap: () => _open(featured[i]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _CategoryBar(
                  selected: _category,
                  onSelect: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.54,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, i) => _ProductCard(
                    product: products[i],
                    onTap: () => _open(products[i]),
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

// ---------------------------------------------------------------------------
// Icône panier + badge (nombre TOTAL d'unités)
// ---------------------------------------------------------------------------

class _CartButton extends StatelessWidget {
  const _CartButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cart = ShopCartScope.of(context);
    return AnimatedBuilder(
      animation: cart,
      builder: (context, _) {
        final count = cart.totalItems;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onTap,
              tooltip: 'Mon panier',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const PhosphorIcon(
                PhosphorIconsRegular.shoppingBag,
                size: 22,
                color: AuryelColors.goldLight,
              ),
            ),
            if (count > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  constraints: const BoxConstraints(
                    minWidth: 17,
                    minHeight: 17,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AuryelColors.goldGradient,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AuryelColors.backgroundDeep),
                  ),
                  child: Text(
                    '$count',
                    style: AuryelText.body(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AuryelColors.backgroundDeep,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Barre de catégories
// ---------------------------------------------------------------------------

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.selected, required this.onSelect});

  final ShopCategory? selected;
  final ValueChanged<ShopCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _Chip(
            label: 'Tout',
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final c in ShopCategory.values)
            _Chip(
              label: c.label,
              active: selected == c,
              onTap: () => onSelect(c),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AuryelColors.gold : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active ? AuryelColors.gold : AuryelColors.warmBorder,
              ),
            ),
            child: Text(
              label,
              style: AuryelText.body(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active
                    ? AuryelColors.backgroundDeep
                    : AuryelColors.textMuted,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte « À découvrir »
// ---------------------------------------------------------------------------

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.product, required this.onTap});

  final ShopProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AuryelColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 234,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AuryelColors.warmBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: ShopProductImage(product: product, compact: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.badge ?? product.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.body(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.gold,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.display(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.priceLabel,
                      style: AuryelText.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carte produit (grille)
// ---------------------------------------------------------------------------

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final ShopProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AuryelColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AuryelColors.warmBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ShopProductImage(product: product, compact: true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.badge ?? product.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.body(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.gold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.display(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.priceLabel,
                      style: AuryelText.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Voir le produit  ›',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.body(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

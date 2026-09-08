import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/shop_cart_store.dart';
import '../data/shop_checkout_service.dart';
import '../data/shop_product.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';
import '../widgets/shop_product_image.dart';

/// « Mon panier » (Boutique V1.1).
///
/// Panier LOCAL : quantités, suppression, sous-total. Le CTA « Commander »
/// passe par le **seam** [ShopCheckoutService.startCartCheckout] qui, tant
/// que le paiement n'est pas branché, répond proprement « indisponible ».
/// Aucun Stripe, aucun appel réseau.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _checkout(BuildContext context, ShopCartStore cart) async {
    try {
      await const ShopCheckoutService().startCartCheckout(cart.items);
    } on ShopCheckoutUnavailable {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le paiement sera disponible prochainement. '
            'Aucun achat n’a été effectué.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ShopCartScope.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: cart,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(),
                  Expanded(
                    child: cart.isEmpty
                        ? _EmptyCart(
                            onDiscover: () => Navigator.of(context).maybePop(),
                          )
                        : _CartList(cart: cart),
                  ),
                  if (!cart.isEmpty)
                    _Footer(
                      cart: cart,
                      onCheckout: () => _checkout(context, cart),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Retour',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              size: 20,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Mon panier',
            style: AuryelText.display(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(
              PhosphorIconsRegular.shoppingBag,
              size: 40,
              color: AuryelColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Ton panier est vide',
              textAlign: TextAlign.center,
              style: AuryelText.display(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Découvre la boutique Auryel et ajoute les objets qui te plaisent.',
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 13,
                height: 1.5,
                color: AuryelColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            AuryelGoldButton(label: 'Découvrir la boutique', onTap: onDiscover),
          ],
        ),
      ),
    );
  }
}

class _CartList extends StatelessWidget {
  const _CartList({required this.cart});

  final ShopCartStore cart;

  @override
  Widget build(BuildContext context) {
    final lines = cart.items;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final line = lines[i];
        final product = shopProductByIdOrNull(line.productId);
        if (product == null) return const SizedBox.shrink();
        return _CartRow(product: product, quantity: line.quantity, cart: cart);
      },
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.product,
    required this.quantity,
    required this.cart,
  });

  final ShopProduct product;
  final int quantity;
  final ShopCartStore cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: ShopProductImage(product: product, compact: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.display(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${product.priceLabel} l’unité',
                  style: AuryelText.body(
                    fontSize: 11.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _QuantityStepper(
                  product: product,
                  quantity: quantity,
                  cart: cart,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => cart.removeLine(product.id),
            tooltip: 'Retirer',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const PhosphorIcon(
              PhosphorIconsRegular.trash,
              size: 17,
              color: AuryelColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.product,
    required this.quantity,
    required this.cart,
  });

  final ShopProduct product;
  final int quantity;
  final ShopCartStore cart;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: PhosphorIconsRegular.minus,
          tooltip: 'Moins',
          onTap: () => cart.decrement(product.id),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 34),
          alignment: Alignment.center,
          child: Text(
            '$quantity',
            style: AuryelText.body(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AuryelColors.textCream,
            ),
          ),
        ),
        _StepButton(
          icon: PhosphorIconsRegular.plus,
          tooltip: 'Plus',
          onTap: () => cart.increment(product.id),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AuryelColors.surfaceLight,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AuryelColors.warmBorder),
            ),
            child: PhosphorIcon(icon, size: 14, color: AuryelColors.goldLight),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.cart, required this.onCheckout});

  final ShopCartStore cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        border: Border(top: BorderSide(color: AuryelColors.warmBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sous-total',
                style: AuryelText.body(
                  fontSize: 13,
                  color: AuryelColors.textMuted,
                ),
              ),
              Text(
                formatEuroCents(cart.subtotalCents),
                style: AuryelText.display(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.goldLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AuryelGoldButton(label: 'Commander', onTap: onCheckout),
          const SizedBox(height: 6),
          Text(
            'Le paiement en ligne arrive bientôt.',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 10.5,
              color: AuryelColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

import 'shop_cart_store.dart';
import 'shop_product.dart';

/// Boutique V1.1 — **seam** de paiement.
///
/// Aucune intégration (Stripe / Shopify / backend) dans ce lot :
/// [checkoutAvailable] est `false` et les deux `startCheckout*` lèvent
/// [ShopCheckoutUnavailable] sans rien déclencher. Quand un vrai checkout sera
/// branché, il suffira de l'implémenter ici — les écrans Boutique / Panier ne
/// bougent pas.
///
/// Contrat du prochain lot : Flutter envoie les `productId` + quantités ;
/// le backend crée la Stripe Checkout Session et **recalcule le vrai prix**.
/// Le montant affiché ici n'est jamais source de vérité paiement.
class ShopCheckoutService {
  const ShopCheckoutService();

  /// `true` uniquement quand un tunnel d'achat réel est câblé.
  static const bool checkoutAvailable = false;

  /// Démarre l'achat d'un [product] seul. Tant que [checkoutAvailable] est
  /// `false`, lève [ShopCheckoutUnavailable] : aucun paiement, aucune commande.
  Future<void> startCheckout(ShopProduct product) async {
    throw const ShopCheckoutUnavailable();
  }

  /// Démarre l'achat du panier ([items] = `productId` + quantités). Même
  /// contrat : tant que [checkoutAvailable] est `false`, lève
  /// [ShopCheckoutUnavailable]. Aucun appel réseau, aucun Stripe.
  Future<void> startCartCheckout(List<CartItem> items) async {
    throw const ShopCheckoutUnavailable();
  }
}

/// La boutique n'accepte pas encore les commandes. Aucun achat n'a été effectué.
class ShopCheckoutUnavailable implements Exception {
  const ShopCheckoutUnavailable();

  @override
  String toString() => 'ShopCheckoutUnavailable';
}

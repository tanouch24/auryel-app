import 'package:in_app_purchase/in_app_purchase.dart';

/// Abstraction TESTABLE du plugin `in_app_purchase`. Le [PurchaseController]
/// dépend UNIQUEMENT de cette interface — jamais de `InAppPurchase.instance`
/// directement — pour permettre un faux en mémoire dans les tests (aucun
/// canal de plateforme, aucun store réel).
///
/// Les types exposés (`ProductDetails`, `PurchaseDetails`,
/// `ProductDetailsResponse`, `PurchaseStatus`, `PurchaseVerificationData`)
/// sont ceux du plugin officiel — l'abstraction ne les remplace pas, elle ne
/// masque que le singleton.
abstract class IapGateway {
  /// `true` si la plateforme de paiement est prête (Play Services présents /
  /// StoreKit disponible). `false` sur un émulateur sans store, en CI, etc.
  Future<bool> isAvailable();

  /// Détails produits pour un ensemble d'identifiants. Les IDs introuvables
  /// (produit non encore activé dans la console, etc.) reviennent dans
  /// `notFoundIDs` — ce n'est PAS une erreur.
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);

  /// Flux temps réel des mises à jour d'achat. Ne se ferme jamais tant que
  /// l'app est active. À écouter avec UNE seule souscription.
  Stream<List<PurchaseDetails>> get purchaseStream;

  /// Lance l'achat d'un produit NON CONSOMMABLE (abonnement Premium inclus —
  /// un abonnement auto-renouvelable est un non-consommable côté plugin).
  /// Le résultat arrive via [purchaseStream], pas via le retour (qui indique
  /// seulement si la demande a bien été envoyée).
  Future<bool> buyNonConsumable(ProductDetails product);

  /// Finalise un achat livré (`purchased` / `restored`). À appeler UNIQUEMENT
  /// après livraison effective du contenu (ici : après un verify backend 200).
  Future<void> completePurchase(PurchaseDetails purchase);

  /// Redemande la livraison de tous les achats non consommables. Les
  /// événements reviennent via [purchaseStream] avec le statut `restored`.
  Future<void> restorePurchases();
}

/// Implémentation réelle : fine enveloppe autour de `InAppPurchase.instance`.
class InAppPurchaseGateway implements IapGateway {
  InAppPurchaseGateway({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> buyNonConsumable(ProductDetails product) => _iap
      .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();
}

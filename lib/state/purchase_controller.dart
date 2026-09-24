// Champs privés injectés par des paramètres nommés publics -> pas d'initializing
// formal possible sans exposer `_billing` / `_gateway` / … comme noms publics.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../api/api_client.dart';
import '../api/billing_api.dart';
import '../analytics/meta_events.dart';
import '../data/iap_gateway.dart';
import '../data/purchase.dart';
import 'auth_controller.dart';
import 'consultation_controller.dart';

/// États du parcours d'achat Premium. AUCUNE UI dans ce lot — F5-C s'appuiera
/// dessus.
enum PurchaseState {
  /// Repos : rien en cours (produit peut être chargé ou non).
  idle,

  /// `queryProductDetails` en cours.
  loadingProducts,

  /// Le produit `auryel_premium_monthly` est revenu dans `notFoundIDs`
  /// (pas encore activé dans la console store, etc.). Pas une erreur fatale.
  productsUnavailable,

  /// `isAvailable()` a répondu `false` (plateforme de paiement indisponible).
  storeUnavailable,

  /// Achat lancé, en attente du 1er événement du store.
  purchasing,

  /// Le store a renvoyé `pending` (paiement différé, validation parentale…).
  pendingStore,

  /// `POST /api/billing/verify` en cours.
  verifying,

  /// Verify a échoué de façon RÉCUPÉRABLE (503, 5xx, réseau). L'achat est
  /// conservé pour [PurchaseController.retryVerification].
  verifyRetryable,

  /// Verify a échoué de façon DÉFINITIVE (409 account_mismatch, 422
  /// invalid_store_receipt / product_mismatch, preuve store absente…).
  /// Aucun entitlement, aucun `completePurchase`.
  verifyFatal,

  /// Pas de session Bearer au moment du verify. L'achat est conservé ;
  /// [PurchaseController.retryVerification] réessaiera une fois reconnecté.
  requiresAuthentication,

  /// Verify 200 + `ConsultationController.refresh()` OK. Le droit Premium réel
  /// est porté par `ConsultationController.quota.isPremium`, PAS par cet état.
  active,

  /// L'utilisateur a annulé l'achat.
  canceled,

  /// Le store a renvoyé `error`.
  storeError,
}

/// États du parcours d'achat CONSOMMABLE « 1 heure supplémentaire »
/// (`auryel_extra_hour`). Distinct de [PurchaseState] : achat répétable, pas
/// de restauration, pas d'entitlement — juste un crédit de temps confirmé par
/// le serveur.
enum ExtraHourPurchaseState {
  /// Repos.
  idle,

  /// Produit `auryel_extra_hour` absent (`notFoundIDs`) ou store indisponible.
  unavailable,

  /// Achat lancé, en attente du 1er événement du store.
  purchasing,

  /// Le store a renvoyé `pending` (paiement différé).
  pendingStore,

  /// `POST /api/billing/purchase` en cours.
  verifying,

  /// Vérification échouée de façon RÉCUPÉRABLE (503, 5xx, réseau). L'achat est
  /// conservé pour [PurchaseController.retryExtraHourVerification].
  verifyRetryable,

  /// Vérification échouée de façon DÉFINITIVE (409, 422, 4xx). Aucun crédit,
  /// aucun `completePurchase`.
  verifyFatal,

  /// Pas de session Bearer au moment du verify. L'achat est conservé.
  requiresAuthentication,

  /// Serveur 200 : CET achat vient de créditer +1 h. Wallet rafraîchi.
  credited,

  /// Serveur 200 : achat DÉJÀ crédité auparavant (rejeu / restauration
  /// implicite). Aucun double crédit.
  alreadyCredited,

  /// L'utilisateur a annulé l'achat.
  canceled,

  /// Le store a renvoyé `error`.
  storeError,
}

/// Orchestration des achats Premium (F5-B — infrastructure seulement).
///
/// INVARIANT : ce contrôleur n'est JAMAIS la source de vérité du Premium.
/// Le droit Premium vient uniquement du backend, relu via
/// `ConsultationController` (`quota.isPremium`) après un verify 200. Aucun
/// booléen `isPremium` local persistant n'est stocké ici.
///
/// Pipeline unique (identique pour `purchased` ET `restored`) :
///   preuve store -> POST /api/billing/verify -> (200) refresh consultation
///   -> completePurchase si `pendingCompletePurchase`.
class PurchaseController extends ChangeNotifier {
  PurchaseController({
    required BillingApi billing,
    required IapGateway gateway,
    required AuthController auth,
    required ConsultationController consultation,
    TargetPlatform? platformOverride,
    MetaEvents metaEvents = const NoopMetaEvents(),
  }) : _billing = billing,
       _gateway = gateway,
       _auth = auth,
       _consultation = consultation,
       _platformOverride = platformOverride,
       _meta = metaEvents;

  final BillingApi _billing;
  final IapGateway _gateway;
  final AuthController _auth;
  final ConsultationController _consultation;
  final TargetPlatform? _platformOverride;
  final MetaEvents _meta;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;
  bool _disposed = false;

  PurchaseState _state = PurchaseState.idle;
  ProductDetails? _premiumProduct;
  String? _errorCode;

  ExtraHourPurchaseState _extraHourState = ExtraHourPurchaseState.idle;
  ProductDetails? _extraHourProduct;
  String? _extraHourError;
  PurchaseDetails? _extraHourPendingRetry;

  /// Dédoublonnage des vérifications EN COURS (jamais permanent : la clé est
  /// retirée en fin de verify, succès inclus, pour qu'un restore / relancement
  /// futur puisse re-vérifier — le backend est idempotent).
  final Set<String> _inFlight = <String>{};

  /// Dernier achat à re-vérifier ([retryVerification]). Effacé sur succès et
  /// sur échec définitif.
  PurchaseDetails? _pendingRetry;

  // --- lecture publique (données minimales pour F5-C) -----------------------

  PurchaseState get state => _state;
  ProductDetails? get premiumProduct => _premiumProduct;
  String? get errorCode => _errorCode;

  // --- « 1 heure supplémentaire » (consommable, répétable) ------------------

  ExtraHourPurchaseState get extraHourState => _extraHourState;
  ProductDetails? get extraHourProduct => _extraHourProduct;
  String? get extraHourError => _extraHourError;

  /// `true` si un achat « +1 h » peut être lancé maintenant.
  bool get canBuyExtraHour =>
      _extraHourProduct != null &&
      _extraHourState != ExtraHourPurchaseState.purchasing &&
      _extraHourState != ExtraHourPurchaseState.pendingStore &&
      _extraHourState != ExtraHourPurchaseState.verifying;

  /// `true` s'il reste un achat « +1 h » en attente de nouvelle vérification.
  bool get hasExtraHourPendingRetry => _extraHourPendingRetry != null;

  /// `true` si un achat peut être lancé maintenant (produit chargé, aucun
  /// achat/vérif en cours).
  bool get canBuy =>
      _premiumProduct != null &&
      _state != PurchaseState.loadingProducts &&
      _state != PurchaseState.purchasing &&
      _state != PurchaseState.pendingStore &&
      _state != PurchaseState.verifying;

  /// `true` si une restauration peut être lancée maintenant.
  bool get canRestore =>
      _state != PurchaseState.loadingProducts &&
      _state != PurchaseState.purchasing &&
      _state != PurchaseState.pendingStore &&
      _state != PurchaseState.verifying;

  /// `true` s'il reste un achat en attente de nouvelle vérification.
  bool get hasPendingRetry => _pendingRetry != null;

  TargetPlatform get _platform => _platformOverride ?? defaultTargetPlatform;

  // --- lifecycle ----------------------------------------------------------

  /// Idempotent : souscrit UNE seule fois à `purchaseStream`, puis lance un
  /// premier `loadProducts()` (sans bloquer). Réappelée -> no-op.
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _subscription = _gateway.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: _onStreamError,
    );
    await loadProducts();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  // --- produits ---------------------------------------------------------

  /// 1) `isAvailable()` -> `storeUnavailable` si `false`.
  /// 2) `queryProductDetails({auryel_premium_monthly, auryel_extra_hour})`.
  /// 3) produit trouvé -> `premiumProduct` / `extraHourProduct` + état `idle`.
  /// 4) dans `notFoundIDs` (ou liste vide) -> `productsUnavailable` /
  ///    `ExtraHourPurchaseState.unavailable` (NORMAL tant que le produit n'est
  ///    pas activé côté store). L'absence de `auryel_extra_hour` NE change PAS
  ///    l'état Premium, et inversement.
  /// Aucune exception non gérée ne remonte à l'UI.
  Future<void> loadProducts() async {
    if (_disposed) return;
    _set(PurchaseState.loadingProducts);
    _setExtra(ExtraHourPurchaseState.idle);
    try {
      final available = await _gateway.isAvailable();
      if (_disposed) return;
      if (!available) {
        _set(PurchaseState.storeUnavailable, errorCode: 'store_unavailable');
        _extraHourProduct = null;
        _setExtra(
          ExtraHourPurchaseState.unavailable,
          errorCode: 'store_unavailable',
        );
        return;
      }
      final resp = await _gateway.queryProductDetails({
        kPremiumMonthlyProductId,
        kExtraHourProductId,
      });
      if (_disposed) return;

      ProductDetails? premium;
      ProductDetails? extraHour;
      for (final p in resp.productDetails) {
        if (p.id == kPremiumMonthlyProductId) {
          premium = p;
        } else if (p.id == kExtraHourProductId) {
          extraHour = p;
        }
      }

      // --- « 1 heure supplémentaire » (indépendant de Premium) ---
      if (extraHour == null || resp.notFoundIDs.contains(kExtraHourProductId)) {
        _extraHourProduct = null;
        _setExtra(
          ExtraHourPurchaseState.unavailable,
          errorCode: 'product_not_found',
        );
      } else {
        _extraHourProduct = extraHour;
        _setExtra(ExtraHourPurchaseState.idle);
      }

      // --- Premium ---
      if (premium == null ||
          resp.notFoundIDs.contains(kPremiumMonthlyProductId)) {
        _premiumProduct = null;
        _set(PurchaseState.productsUnavailable, errorCode: 'product_not_found');
        return;
      }
      _premiumProduct = premium;
      _set(PurchaseState.idle);
    } on Object catch (e) {
      // Toute panne de query (plateforme, plugin) -> indisponible, pas de crash.
      _premiumProduct = null;
      _extraHourProduct = null;
      _set(PurchaseState.productsUnavailable, errorCode: 'query_failed:$e');
      _setExtra(
        ExtraHourPurchaseState.unavailable,
        errorCode: 'query_failed:$e',
      );
    }
  }

  // --- achat / restore ------------------------------------------------

  /// Lance l'achat de l'abonnement Premium. Le résultat arrive via
  /// `purchaseStream` (pas via le retour). No-op si le produit n'est pas
  /// chargé ou si un achat/vérif est déjà en cours.
  Future<void> buyPremium() async {
    if (_disposed) return;
    final product = _premiumProduct;
    if (product == null || !canBuy) return;
    _set(PurchaseState.purchasing);
    try {
      await _gateway.buyNonConsumable(product);
    } on Object catch (e) {
      _set(PurchaseState.storeError, errorCode: 'buy_failed:$e');
    }
  }

  /// Redemande la livraison des achats non consommables. Les événements
  /// `restored` passent par EXACTEMENT le même pipeline que `purchased`.
  Future<void> restorePurchases() async {
    if (_disposed || !canRestore) return;
    try {
      await _gateway.restorePurchases();
    } on Object catch (e) {
      _set(PurchaseState.storeError, errorCode: 'restore_failed:$e');
    }
  }

  /// Reprend EXACTEMENT le dernier achat en attente de vérification, avec un
  /// Bearer frais. `completePurchase` seulement après succès serveur. No-op
  /// s'il n'y a rien en attente.
  Future<void> retryVerification() async {
    final pending = _pendingRetry;
    if (_disposed || pending == null) return;
    // Reprise : on ne re-déclenche PAS l'événement Meta (déjà émis, ou reprise
    // d'une restauration) — priorité au non-doublon de conversion.
    await _verifyAndComplete(pending, isNewPurchase: false);
  }

  /// Lance l'achat CONSOMMABLE « 1 heure supplémentaire » (répétable). Le
  /// résultat arrive via `purchaseStream`. Ne touche JAMAIS l'état Premium.
  /// Aucun ajout local de 3600 s : le crédit est décidé par le backend.
  Future<void> buyExtraHour() async {
    if (_disposed) return;
    final product = _extraHourProduct;
    if (product == null || !canBuyExtraHour) return;
    _setExtra(ExtraHourPurchaseState.purchasing);
    try {
      await _gateway.buyConsumable(product);
    } on Object catch (e) {
      _setExtra(ExtraHourPurchaseState.storeError, errorCode: 'buy_failed:$e');
    }
  }

  /// Reprend le dernier achat « +1 h » en attente de vérification, avec un
  /// Bearer frais. No-op s'il n'y a rien en attente.
  Future<void> retryExtraHourVerification() async {
    final pending = _extraHourPendingRetry;
    if (_disposed || pending == null) return;
    await _verifyAndCompleteExtraHour(pending);
  }

  // --- flux d'achat --------------------------------------------------

  void _onStreamError(Object error, StackTrace stack) {
    if (_disposed) return;
    _set(PurchaseState.storeError, errorCode: 'stream_error');
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final pd in purchases) {
      if (_disposed) return;
      try {
        await _handleOne(pd);
      } on Object {
        // Un événement fautif ne doit jamais tuer la souscription.
        if (!_disposed) {
          _set(PurchaseState.verifyRetryable, errorCode: 'unexpected');
        }
      }
    }
  }

  Future<void> _handleOne(PurchaseDetails pd) async {
    // Le produit consommable « +1 h » a son propre pipeline / son propre état.
    if (pd.productID == kExtraHourProductId) {
      await _handleExtraHourOne(pd);
      return;
    }
    switch (pd.status) {
      case PurchaseStatus.pending:
        // Aucune vérif backend, aucun completePurchase.
        _set(PurchaseState.pendingStore);
        return;
      case PurchaseStatus.canceled:
        _set(PurchaseState.canceled);
        return;
      case PurchaseStatus.error:
        // Aucun entitlement inventé. On NE complète pas non plus : F5-B ne
        // finalise un achat qu'après un verify backend 200.
        _set(
          PurchaseState.storeError,
          errorCode: pd.error?.code ?? 'store_error',
        );
        return;
      case PurchaseStatus.purchased:
        await _verifyAndComplete(pd, isNewPurchase: true);
        return;
      case PurchaseStatus.restored:
        await _verifyAndComplete(pd, isNewPurchase: false);
        return;
    }
  }

  // --- verify backend + complete (ordre STRICT) ---------------------

  Future<void> _verifyAndComplete(
    PurchaseDetails pd, {
    required bool isNewPurchase,
  }) async {
    if (_disposed) return;

    final platform = _platform;
    final isAndroid = platform == TargetPlatform.android;
    final isIOS = platform == TargetPlatform.iOS;
    if (!isAndroid && !isIOS) {
      _set(PurchaseState.verifyFatal, errorCode: 'unsupported_platform');
      _pendingRetry = null;
      return;
    }

    // Preuve store selon la plateforme (POINT CRITIQUE).
    final String proof;
    if (isAndroid) {
      // Google : purchase token = serverVerificationData (JAMAIS purchaseID).
      proof = pd.verificationData.serverVerificationData;
      if (proof.isEmpty) {
        _set(PurchaseState.verifyFatal, errorCode: 'missing_store_proof');
        _pendingRetry = null;
        return;
      }
    } else {
      // Apple : transaction_id = purchaseID (JAMAIS serverVerificationData).
      final txId = pd.purchaseID;
      if (txId == null || txId.isEmpty) {
        _set(PurchaseState.verifyFatal, errorCode: 'missing_transaction_id');
        _pendingRetry = null;
        return;
      }
      proof = txId;
    }

    // Dédoublonnage des vérifs EN COURS (non permanent).
    final key = '${platform.name}|${pd.productID}|$proof';
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);

    try {
      final token = await _auth.currentToken();
      if (_disposed) return;
      if (token == null || token.isEmpty) {
        _pendingRetry = pd;
        _set(
          PurchaseState.requiresAuthentication,
          errorCode: 'requires_authentication',
        );
        return;
      }

      _set(PurchaseState.verifying);

      await (isAndroid
          ? _billing.verifyGooglePlay(
              bearer: token,
              productId: pd.productID,
              purchaseToken: proof,
            )
          : _billing.verifyAppStore(
              bearer: token,
              productId: pd.productID,
              transactionId: proof,
            ));
      if (_disposed) return;

      // ORDRE STRICT : verify 200 -> refresh -> completePurchase.
      await _consultation.refresh();
      if (_disposed) return;

      if (pd.pendingCompletePurchase) {
        await _gateway.completePurchase(pd);
      }
      _pendingRetry = null;
      _set(PurchaseState.active);

      // Meta : conversion « abonnement démarré » — UNIQUEMENT après un verify
      // serveur 200 et pour un ACHAT NEUF (jamais une restauration / reprise).
      // No-op sans consentement. Aucune donnée : ni prix, ni user_id, ni reçu.
      if (isNewPurchase) {
        unawaited(_meta.logSubscriptionStarted());
      }
    } on ApiUnauthorizedException {
      // Mécanisme auth existant : purge + sessionExpired.
      await _auth.invalidateSession();
      _pendingRetry = pd;
      _set(
        PurchaseState.requiresAuthentication,
        errorCode: 'requires_authentication',
      );
    } on ApiNetworkException {
      _pendingRetry = pd;
      _set(PurchaseState.verifyRetryable, errorCode: 'network');
    } on ApiException catch (e) {
      switch (e.statusCode) {
        case 409:
          // account_mismatch — fatal, aucun complete.
          _pendingRetry = null;
          _set(
            PurchaseState.verifyFatal,
            errorCode: e.code ?? 'account_mismatch',
          );
        case 422:
          // invalid_store_receipt / product_mismatch — fatal, aucun complete.
          _pendingRetry = null;
          _set(
            PurchaseState.verifyFatal,
            errorCode: e.code ?? 'invalid_store_receipt',
          );
        case 503:
          // verification_not_configured / store_verification_unavailable —
          // récupérable (ex. Apple pas encore configuré côté backend).
          _pendingRetry = pd;
          _set(
            PurchaseState.verifyRetryable,
            errorCode: e.code ?? 'verification_not_configured',
          );
        default:
          if (e.statusCode >= 500) {
            _pendingRetry = pd;
            _set(
              PurchaseState.verifyRetryable,
              errorCode: e.code ?? 'server_error',
            );
          } else {
            // 4xx inattendu (400 invalid_store/invalid_product…) : on n'envoie
            // que des valeurs valides, donc traité comme fatal.
            _pendingRetry = null;
            _set(PurchaseState.verifyFatal, errorCode: e.code ?? 'bad_request');
          }
      }
    } on FormatException {
      // 200 au corps illisible : ne se corrige pas en rejouant.
      _pendingRetry = null;
      _set(PurchaseState.verifyFatal, errorCode: 'bad_response');
    } finally {
      _inFlight.remove(key);
    }
  }

  // --- « 1 heure supplémentaire » : flux + verify (ordre STRICT) ----------

  Future<void> _handleExtraHourOne(PurchaseDetails pd) async {
    switch (pd.status) {
      case PurchaseStatus.pending:
        _setExtra(ExtraHourPurchaseState.pendingStore);
        return;
      case PurchaseStatus.canceled:
        _setExtra(ExtraHourPurchaseState.canceled);
        return;
      case PurchaseStatus.error:
        _setExtra(
          ExtraHourPurchaseState.storeError,
          errorCode: pd.error?.code ?? 'store_error',
        );
        return;
      case PurchaseStatus.purchased:
        await _verifyAndCompleteExtraHour(pd);
        return;
      case PurchaseStatus.restored:
        // Apple ne restaure pas les consommables. Même si un plugin ou un
        // StoreKit local émet un événement inattendu, il ne doit jamais
        // recréditer une ancienne transaction.
        _extraHourPendingRetry = null;
        _setExtra(
          ExtraHourPurchaseState.verifyFatal,
          errorCode: 'consumable_not_restorable',
        );
        return;
    }
  }

  Future<void> _verifyAndCompleteExtraHour(PurchaseDetails pd) async {
    if (_disposed) return;

    final isAndroid = _platform == TargetPlatform.android;
    final isIOS = _platform == TargetPlatform.iOS;
    if (!isAndroid && !isIOS) {
      _extraHourPendingRetry = null;
      _setExtra(
        ExtraHourPurchaseState.verifyFatal,
        errorCode: 'unsupported_platform',
      );
      return;
    }

    // Google : purchase token = serverVerificationData. Apple : transaction
    // ID = purchaseID. Ne jamais substituer la preuve d'une plateforme à
    // l'autre.
    final String proof;
    if (isAndroid) {
      proof = pd.verificationData.serverVerificationData;
    } else {
      proof = pd.purchaseID ?? '';
    }
    if (proof.isEmpty) {
      _extraHourPendingRetry = null;
      _setExtra(
        ExtraHourPurchaseState.verifyFatal,
        errorCode: isAndroid ? 'missing_store_proof' : 'missing_transaction_id',
      );
      return;
    }

    final key = 'extra_hour|${pd.productID}|$proof';
    if (_inFlight.contains(key)) return;
    _inFlight.add(key);

    try {
      final token = await _auth.currentToken();
      if (_disposed) return;
      if (token == null || token.isEmpty) {
        _extraHourPendingRetry = pd;
        _setExtra(
          ExtraHourPurchaseState.requiresAuthentication,
          errorCode: 'requires_authentication',
        );
        return;
      }

      _setExtra(ExtraHourPurchaseState.verifying);

      final resp = isAndroid
          ? await _billing.verifyGooglePlayPurchase(
              bearer: token,
              productId: pd.productID,
              purchaseToken: proof,
            )
          : await _billing.verifyAppStorePurchase(
              bearer: token,
              productId: pd.productID,
              transactionId: proof,
            );
      if (_disposed) return;

      // ORDRE STRICT : verify 200 -> refresh wallet -> completePurchase.
      // Jamais d'ajout local de 3600 s : le serveur a déjà crédité le bucket
      // `purchased`, `refresh()` relit le portefeuille (bloc `time`).
      await _consultation.refresh();
      if (_disposed) return;

      if (pd.pendingCompletePurchase) {
        // autoConsume:true -> le plugin consomme ici -> l'heure redevient
        // ré-achetable côté Play Billing.
        await _gateway.completePurchase(pd);
      }
      _extraHourPendingRetry = null;
      _setExtra(
        resp.purchase.alreadyCredited
            ? ExtraHourPurchaseState.alreadyCredited
            : ExtraHourPurchaseState.credited,
      );
    } on ApiUnauthorizedException {
      await _auth.invalidateSession();
      _extraHourPendingRetry = pd;
      _setExtra(
        ExtraHourPurchaseState.requiresAuthentication,
        errorCode: 'requires_authentication',
      );
    } on ApiNetworkException {
      _extraHourPendingRetry = pd;
      _setExtra(ExtraHourPurchaseState.verifyRetryable, errorCode: 'network');
    } on ApiException catch (e) {
      if (e.statusCode == 503 || e.statusCode >= 500) {
        _extraHourPendingRetry = pd;
        _setExtra(
          ExtraHourPurchaseState.verifyRetryable,
          errorCode: e.code ?? 'server_error',
        );
      } else {
        // 409 account_mismatch / 422 invalid_store_receipt / 400 -> fatal,
        // aucun completePurchase.
        _extraHourPendingRetry = null;
        _setExtra(
          ExtraHourPurchaseState.verifyFatal,
          errorCode: e.code ?? 'bad_request',
        );
      }
    } on FormatException {
      _extraHourPendingRetry = null;
      _setExtra(ExtraHourPurchaseState.verifyFatal, errorCode: 'bad_response');
    } finally {
      _inFlight.remove(key);
    }
  }

  // --- helpers ---------------------------------------------------------

  void _set(PurchaseState state, {String? errorCode}) {
    if (_disposed) return;
    _state = state;
    _errorCode = errorCode;
    notifyListeners();
  }

  void _setExtra(ExtraHourPurchaseState state, {String? errorCode}) {
    if (_disposed) return;
    _extraHourState = state;
    _extraHourError = errorCode;
    notifyListeners();
  }
}

/// Fournit [PurchaseController] à l'arbre de widgets (rebuild sur
/// `notifyListeners`). Même style que [AuthScope] / [ConsultationScope].
class PurchaseScope extends InheritedNotifier<PurchaseController> {
  const PurchaseScope({
    super.key,
    required PurchaseController controller,
    required super.child,
  }) : super(notifier: controller);

  static PurchaseController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PurchaseScope>();
    assert(scope != null, 'PurchaseScope introuvable dans l’arbre.');
    return scope!.notifier!;
  }

  static PurchaseController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PurchaseScope>()?.notifier;
}

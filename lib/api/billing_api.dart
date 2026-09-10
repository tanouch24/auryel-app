import 'api_client.dart';
import '../data/purchase.dart';

/// Endpoint de vérification d'achat mobile (F5-B). Réutilise l'[ApiClient] F1 —
/// aucun second client HTTP.
///
///   POST /api/billing/verify   (Bearer)
///     Android : { "store": "google_play", "product_id": "…", "purchase_token": "…" }
///     iOS     : { "store": "app_store",   "product_id": "…", "transaction_id": "…" }
///
/// RÈGLES :
///  - Le Bearer vient de `AuthController.currentToken()` — jamais d'identité
///    dans le corps.
///  - On n'envoie JAMAIS : user_id, entitled, status, dates, quota,
///    subscription_key. Seuls store / product_id / preuve store partent.
///  - `entitled` / `quota` sont des DÉCISIONS SERVEUR renvoyées dans la réponse,
///    jamais fournies par le client.
///
/// Erreurs propagées telles quelles par [ApiClient] :
///  - 401 -> [ApiUnauthorizedException]   (session invalide)
///  - 409 / 422 / 5xx / autre -> [ApiException] (`statusCode`, `code`)
///  - réseau / timeout / TLS -> [ApiNetworkException]
///  - 200 au corps illisible -> [FormatException] (parsing DTO)
class BillingApi {
  BillingApi(this._client);

  final ApiClient _client;

  static const String _path = '/api/billing/verify';
  static const String _purchasePath = '/api/billing/purchase';

  /// Vérifie un achat Google Play. `purchaseToken` =
  /// `PurchaseDetails.verificationData.serverVerificationData` (le purchase
  /// token Google), JAMAIS le `purchaseID`.
  Future<BillingVerifyResponse> verifyGooglePlay({
    required String bearer,
    required String productId,
    required String purchaseToken,
  }) async {
    final json = await _client.postJson(_path, {
      'store': kStoreGooglePlay,
      'product_id': productId,
      'purchase_token': purchaseToken,
    }, bearer: bearer);
    return BillingVerifyResponse.fromJson(json);
  }

  /// Vérifie un achat App Store. `transactionId` = `PurchaseDetails.purchaseID`
  /// (l'identifiant de transaction Apple), JAMAIS le
  /// `verificationData.serverVerificationData` (receipt/JWS générique).
  Future<BillingVerifyResponse> verifyAppStore({
    required String bearer,
    required String productId,
    required String transactionId,
  }) async {
    final json = await _client.postJson(_path, {
      'store': kStoreAppStore,
      'product_id': productId,
      'transaction_id': transactionId,
    }, bearer: bearer);
    return BillingVerifyResponse.fromJson(json);
  }

  /// Vérifie + crédite un achat CONSOMMABLE Google Play (« 1 heure
  /// supplémentaire »). `purchaseToken` =
  /// `PurchaseDetails.verificationData.serverVerificationData`.
  ///
  ///   POST /api/billing/purchase
  ///     { "store": "google_play", "product_id": "…", "purchase_token": "…" }
  ///
  /// Le serveur crédite EXACTLY-ONCE : rejouer un token déjà crédité renvoie
  /// 200 avec `already_credited: true` (aucun double crédit). Erreurs
  /// propagées telles quelles par [ApiClient] (401 -> [ApiUnauthorizedException],
  /// 409 / 422 / 5xx -> [ApiException], réseau -> [ApiNetworkException]).
  Future<BillingPurchaseResponse> verifyGooglePlayPurchase({
    required String bearer,
    required String productId,
    required String purchaseToken,
  }) async {
    final json = await _client.postJson(_purchasePath, {
      'store': kStoreGooglePlay,
      'product_id': productId,
      'purchase_token': purchaseToken,
    }, bearer: bearer);
    return BillingPurchaseResponse.fromJson(json);
  }
}

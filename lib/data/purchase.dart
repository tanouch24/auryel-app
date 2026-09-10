import 'consultation.dart' show QuotaDto;

/// Identifiant du produit d'abonnement Premium — tel qu'il est enregistré côté
/// stores (Google Play Console / App Store Connect) ET tel que l'attend le
/// backend (`_MOBILE_SUB_PRODUCT_IDS`).
///
/// AUCUN prix ici : le prix affiché vient toujours de `ProductDetails.price`
/// (résolu par le store selon la région de l'utilisateur).
///
/// L'achat consommable « 1 heure supplémentaire » a son propre identifiant
/// [kExtraHourProductId] et son propre endpoint (`POST /api/billing/purchase`).
const String kPremiumMonthlyProductId = 'auryel_premium_monthly';

/// Identifiant du produit CONSOMMABLE « 1 heure supplémentaire » — tel qu'il
/// est enregistré dans Google Play Console ET tel que l'attend le backend
/// (`_MOBILE_CONSUMABLE_PRODUCT_IDS`).
///
/// Achat unique RÉPÉTABLE : chaque achat validé par le serveur crédite
/// exactement 3600 s dans le bucket `purchased` (temps acheté, débité en
/// dernier, jamais remis à zéro). Le prix affiché vient toujours de
/// `ProductDetails.price` (résolu par le store selon la région) ; « 1,99 € »
/// n'est qu'un repli. AUCUN lien avec l'abonnement Premium.
const String kExtraHourProductId = 'auryel_extra_hour';

/// Secondes créditées par un achat `auryel_extra_hour` validé (écho du
/// mapping SERVEUR figé — jamais utilisé pour créditer localement).
const int kExtraHourSeconds = 3600;

/// Stores acceptés par `POST /api/billing/verify` et `POST /api/billing/purchase`.
const String kStoreGooglePlay = 'google_play';
const String kStoreAppStore = 'app_store';

/// Bloc `subscription` renvoyé par `POST /api/billing/verify` (HTTP 200).
///
/// C'est un écho NON sensible de la décision serveur — il ne sert qu'à
/// l'observabilité / au debug. La source de vérité du droit Premium reste
/// `quota` (relu ensuite via `GET /api/consultation/state`), jamais ce bloc.
class BillingSubscriptionDto {
  const BillingSubscriptionDto({
    required this.store,
    required this.productId,
    required this.status,
    required this.entitled,
    required this.expiresAt,
  });

  final String store;
  final String productId;
  final String status;
  final bool entitled;

  /// Fin effective du droit (peut être nulle si le backend l'omet).
  final DateTime? expiresAt;

  factory BillingSubscriptionDto.fromJson(Map<String, dynamic> json) {
    final store = (json['store'] ?? '').toString();
    final productId = (json['product_id'] ?? '').toString();
    final status = (json['status'] ?? '').toString();
    if (store.isEmpty || productId.isEmpty || status.isEmpty) {
      throw const FormatException(
        'billing/verify: `subscription` incomplet (store/product_id/status)',
      );
    }
    return BillingSubscriptionDto(
      store: store,
      productId: productId,
      status: status,
      entitled: json['entitled'] == true,
      expiresAt: _date(json['expires_at']),
    );
  }
}

/// Réponse 200 de `POST /api/billing/verify`.
///
///   { "subscription": { store, product_id, status, entitled, expires_at },
///     "quota": { ... } }
///
/// `quota` réutilise [QuotaDto] (même forme que `/api/consultation/state`).
class BillingVerifyResponse {
  const BillingVerifyResponse({
    required this.subscription,
    required this.quota,
  });

  final BillingSubscriptionDto subscription;
  final QuotaDto quota;

  factory BillingVerifyResponse.fromJson(Map<String, dynamic> json) {
    final s = json['subscription'];
    final q = json['quota'];
    if (s is! Map<String, dynamic>) {
      throw const FormatException('billing/verify: bloc `subscription` absent');
    }
    if (q is! Map<String, dynamic>) {
      throw const FormatException('billing/verify: bloc `quota` absent');
    }
    return BillingVerifyResponse(
      subscription: BillingSubscriptionDto.fromJson(s),
      quota: QuotaDto.fromJson(q),
    );
  }
}

DateTime? _date(Object? v) =>
    (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

/// Bloc `purchase` renvoyé par `POST /api/billing/purchase` (HTTP 200).
///
/// `creditedSeconds` = décision SERVEUR : 3600 si CET appel vient de créditer
/// l'heure, 0 si l'achat avait déjà été crédité (`alreadyCredited == true`).
/// La SOURCE DE VÉRITÉ du portefeuille reste le bloc `time` de
/// `GET /api/consultation/state`, relu juste après par le client.
class BillingPurchaseDto {
  const BillingPurchaseDto({
    required this.store,
    required this.productId,
    required this.creditedSeconds,
    required this.alreadyCredited,
  });

  final String store;
  final String productId;
  final int creditedSeconds;
  final bool alreadyCredited;

  factory BillingPurchaseDto.fromJson(Map<String, dynamic> json) {
    final store = (json['store'] ?? '').toString();
    final productId = (json['product_id'] ?? '').toString();
    if (store.isEmpty || productId.isEmpty) {
      throw const FormatException(
        'billing/purchase: `purchase` incomplet (store/product_id)',
      );
    }
    final credited = json['credited_seconds'];
    return BillingPurchaseDto(
      store: store,
      productId: productId,
      creditedSeconds: credited is int
          ? credited
          : int.tryParse('${credited ?? 0}') ?? 0,
      alreadyCredited: json['already_credited'] == true,
    );
  }
}

/// Réponse 200 de `POST /api/billing/purchase`.
///
///   { "purchase": { store, product_id, credited_seconds, already_credited },
///     "quota": { ... } }
class BillingPurchaseResponse {
  const BillingPurchaseResponse({
    required this.purchase,
    required this.quota,
  });

  final BillingPurchaseDto purchase;
  final QuotaDto quota;

  factory BillingPurchaseResponse.fromJson(Map<String, dynamic> json) {
    final p = json['purchase'];
    final q = json['quota'];
    if (p is! Map<String, dynamic>) {
      throw const FormatException('billing/purchase: bloc `purchase` absent');
    }
    if (q is! Map<String, dynamic>) {
      throw const FormatException('billing/purchase: bloc `quota` absent');
    }
    return BillingPurchaseResponse(
      purchase: BillingPurchaseDto.fromJson(p),
      quota: QuotaDto.fromJson(q),
    );
  }
}

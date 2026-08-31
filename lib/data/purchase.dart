import 'consultation.dart' show QuotaDto;

/// Identifiant du produit d'abonnement Premium — tel qu'il est enregistré côté
/// stores (Google Play Console / App Store Connect) ET tel que l'attend le
/// backend (`_MOBILE_SUB_PRODUCT_IDS`).
///
/// AUCUN prix ici : le prix affiché vient toujours de `ProductDetails.price`
/// (résolu par le store selon la région de l'utilisateur).
///
/// Le consommable « consultation supplémentaire » (`auryel_consultation_extra`,
/// 2,90 €) N'EST PAS géré dans ce lot (F5-B).
const String kPremiumMonthlyProductId = 'auryel_premium_monthly';

/// Stores acceptés par `POST /api/billing/verify`.
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

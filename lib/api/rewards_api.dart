import 'api_client.dart';

/// Progression de la récompense « 30 jours de partage = 1 h de consultation ».
/// C'est la RÉPONSE SERVEUR — la source de vérité. Le tracker local
/// (`DailyShareTracker`) n'est plus qu'un cache d'affichage non autoritaire.
class ShareProgress {
  const ShareProgress({
    required this.count,
    required this.target,
    required this.credited,
    required this.creditedSeconds,
  });

  /// Jours DISTINCTS de partage comptabilisés par le serveur.
  final int count;

  /// Palier (30 en V1).
  final int target;

  /// `true` uniquement quand le serveur a réellement crédité l'heure.
  final bool credited;

  /// Secondes créditées lors de CET appel (3600 au palier, 0 sinon). Jamais
  /// utilisé pour modifier un solde côté client : on rafraîchit le portefeuille
  /// depuis le serveur.
  final int creditedSeconds;

  factory ShareProgress.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final rawTarget = asInt(json['target']);
    return ShareProgress(
      count: asInt(json['count']),
      target: rawTarget > 0 ? rawTarget : 30,
      credited: json['credited'] == true,
      creditedSeconds: asInt(json['credited_seconds']),
    );
  }

  @override
  String toString() =>
      'ShareProgress($count/$target, credited: $credited, +${creditedSeconds}s)';
}

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 2/5) — ÉTOILES AURYEL. Le SERVEUR reste
// l'unique source de vérité : [RewardWallet] est la réponse BRUTE de
// `GET /api/app/rewards/wallet`, jamais recalculée côté client. Les montants
// ([RewardRule.starsAmount]) viennent TOUJOURS du serveur — jamais codés en
// dur dans Flutter.
// ===========================================================================

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Une règle de récompense ACTIVE (le serveur n'expose jamais une règle
/// `enabled=false` : une action future désactivée n'apparaît jamais).
class RewardRule {
  const RewardRule({
    required this.ruleKey,
    required this.starsAmount,
    this.dailyLimit,
  });

  final String ruleKey;
  final int starsAmount;

  /// `null` = pas de plafond quotidien (ex. jalon de streak) ; sinon le
  /// nombre maximum de crédits par jour pour cette règle. TOUJOURS la valeur
  /// serveur réelle (`reward_rules.daily_limit`) — jamais devinée côté
  /// Flutter.
  final int? dailyLimit;

  factory RewardRule.fromJson(Map<String, dynamic> json) => RewardRule(
    ruleKey: (json['rule_key'] ?? '').toString(),
    starsAmount: _asInt(json['stars_amount']),
    dailyLimit: _asIntOrNull(json['daily_limit']),
  );
}

/// Série de jours actifs consécutifs (jour Europe/Paris, décidé serveur).
class RewardStreak {
  const RewardStreak({
    required this.currentStreak,
    required this.bestStreak,
    required this.nextRewardInDays,
  });

  final int currentStreak;
  final int bestStreak;

  /// Jours restants avant le prochain jalon de 7 jours (+50 ⭐).
  final int nextRewardInDays;

  factory RewardStreak.fromJson(Map<String, dynamic> json) => RewardStreak(
    currentStreak: _asInt(json['current_streak']),
    bestStreak: _asInt(json['best_streak']),
    nextRewardInDays: _asInt(json['next_reward_in_days']),
  );

  static const RewardStreak zero = RewardStreak(
    currentStreak: 0,
    bestStreak: 0,
    nextRewardInDays: 7,
  );
}

/// Une ligne d'historique — LECTURE SEULE, jamais rejouée côté client.
class RewardTransaction {
  const RewardTransaction({
    required this.deltaStars,
    required this.balanceAfter,
    required this.reason,
    required this.createdAt,
  });

  final int deltaStars;
  final int balanceAfter;

  /// `rule_key` à l'origine du mouvement (ex. `meditation_completed`).
  final String reason;
  final DateTime? createdAt;

  factory RewardTransaction.fromJson(Map<String, dynamic> json) {
    final raw = json['created_at']?.toString();
    return RewardTransaction(
      deltaStars: _asInt(json['delta_stars']),
      balanceAfter: _asInt(json['balance_after']),
      reason: (json['reason'] ?? '').toString(),
      createdAt: raw == null ? null : DateTime.tryParse(raw),
    );
  }
}

/// GROS CHANTIER AURYEL (Prompt 3/5) — un produit du catalogue « temps
/// contre Étoiles » (ex. Consultation Express). Coût/durée TOUJOURS résolus
/// serveur (`express_products`) — jamais codés en dur côté Flutter.
class ExpressProduct {
  const ExpressProduct({
    required this.productKey,
    required this.starsCost,
    required this.secondsGranted,
  });

  final String productKey;
  final int starsCost;
  final int secondsGranted;

  factory ExpressProduct.fromJson(Map<String, dynamic> json) => ExpressProduct(
    productKey: (json['product_key'] ?? '').toString(),
    starsCost: _asInt(json['stars_cost']),
    secondsGranted: _asInt(json['seconds_granted']),
  );
}

/// Wallet Étoiles complet — RÉPONSE SERVEUR de `GET /api/app/rewards/wallet`,
/// source de vérité UNIQUE partagée par le header Accueil et l'écran Wallet.
class RewardWallet {
  const RewardWallet({
    required this.starsBalance,
    required this.rules,
    required this.streak,
    required this.recentTransactions,
    this.expressProducts = const [],
    this.minutesConvertedThisMonth = 0,
    this.monthlyMinutesLimit = 30,
    this.monthlyMinutesRemaining = 30,
  });

  final int starsBalance;

  /// UNIQUEMENT les règles actives — une action future désactivée
  /// (`rewarded_ad_completed`) n'apparaît jamais ici.
  final List<RewardRule> rules;
  final RewardStreak streak;
  final List<RewardTransaction> recentTransactions;

  /// UNIQUEMENT les produits express ACTIFS.
  final List<ExpressProduct> expressProducts;
  final int minutesConvertedThisMonth;
  final int monthlyMinutesLimit;
  final int monthlyMinutesRemaining;

  factory RewardWallet.fromJson(Map<String, dynamic> json) {
    final rawRules = json['rules'];
    final rules = rawRules is List
        ? rawRules
              .whereType<Map<String, dynamic>>()
              .map(RewardRule.fromJson)
              .toList(growable: false)
        : const <RewardRule>[];
    final rawStreak = json['streak'];
    final streak = rawStreak is Map<String, dynamic>
        ? RewardStreak.fromJson(rawStreak)
        : RewardStreak.zero;
    final rawTx = json['recent_transactions'];
    final tx = rawTx is List
        ? rawTx
              .whereType<Map<String, dynamic>>()
              .map(RewardTransaction.fromJson)
              .toList(growable: false)
        : const <RewardTransaction>[];
    final rawExpress = json['express_products'];
    final express = rawExpress is List
        ? rawExpress
              .whereType<Map<String, dynamic>>()
              .map(ExpressProduct.fromJson)
              .toList(growable: false)
        : const <ExpressProduct>[];
    return RewardWallet(
      starsBalance: _asInt(json['stars_balance']),
      rules: rules,
      streak: streak,
      recentTransactions: tx,
      expressProducts: express,
      minutesConvertedThisMonth: _asInt(json['minutes_converted_this_month']),
      monthlyMinutesLimit: _asInt(json['monthly_minutes_limit']) == 0
          ? 30
          : _asInt(json['monthly_minutes_limit']),
      monthlyMinutesRemaining: json.containsKey('monthly_minutes_remaining')
          ? _asInt(json['monthly_minutes_remaining'])
          : 30,
    );
  }

  static const RewardWallet empty = RewardWallet(
    starsBalance: 0,
    rules: [],
    streak: RewardStreak.zero,
    recentTransactions: [],
    expressProducts: [],
  );
}

/// Résultat d'un `POST /api/app/rewards/claim`. `awarded=false` n'est PAS une
/// erreur (ex. déjà réclamé aujourd'hui) : le solde n'a simplement pas bougé.
class RewardClaimResult {
  const RewardClaimResult({
    required this.awarded,
    required this.reason,
    required this.starsAwarded,
    required this.newBalance,
  });

  final bool awarded;
  final String? reason;
  final int starsAwarded;
  final int newBalance;

  factory RewardClaimResult.fromJson(Map<String, dynamic> json) =>
      RewardClaimResult(
        awarded: json['awarded'] == true,
        reason: json['reason']?.toString(),
        starsAwarded: _asInt(json['stars_awarded']),
        newBalance: _asInt(json['new_balance']),
      );
}

// ===========================================================================
// GROS CHANTIER AURYEL (Prompt 3/5) — CONSULTATION EXPRESS : dépenser des
// Étoiles contre du temps de consultation. Coût/durée TOUJOURS résolus par
// le serveur — [ExpressConsultationResult] est la réponse BRUTE, jamais
// recalculée côté client.
// ===========================================================================

/// Résultat d'un `POST /api/app/rewards/express-consultation`.
/// `success=false` n'est PAS une erreur réseau (ex. solde insuffisant) : le
/// serveur répond 200 avec une raison métier.
class ExpressConsultationResult {
  const ExpressConsultationResult({
    required this.success,
    required this.reason,
    required this.starsSpent,
    required this.starsBalance,
    required this.secondsGranted,
  });

  final bool success;
  final String? reason;
  final int starsSpent;
  final int starsBalance;
  final int secondsGranted;

  bool get isInsufficientBalance => reason == 'insufficient_balance';
  bool get isMonthlyLimitReached =>
      reason == 'monthly_conversion_limit_reached';

  factory ExpressConsultationResult.fromJson(Map<String, dynamic> json) =>
      ExpressConsultationResult(
        success: json['success'] == true,
        reason: json['reason']?.toString(),
        starsSpent: _asInt(json['stars_spent']),
        starsBalance: _asInt(json['stars_balance']),
        secondsGranted: _asInt(json['seconds_granted']),
      );
}

/// Récompenses côté app. Réutilise l'[ApiClient] commun — aucun second client.
///
///   POST /api/app/rewards/daily-share    (Bearer) -> ShareProgress
///     Déclaré APRÈS un partage réellement lancé depuis Auryel. Le serveur
///     décide s'il compte le jour (max 1/jour) et s'il crédite au palier.
///   GET  /api/app/rewards/share-progress (Bearer) -> ShareProgress
///     Lecture seule, pour afficher « X / 30 ».
///   GET  /api/app/rewards/wallet         (Bearer) -> RewardWallet
///     Solde Étoiles + règles actives + streak + historique récent.
///   POST /api/app/rewards/claim          (Bearer) { action_key } -> RewardClaimResult
///     Réclame UNE action SANS preuve serveur indépendante (whitelist stricte
///     côté serveur — aujourd'hui `wake_completed` uniquement). AUCUN montant
///     n'est jamais envoyé : le serveur résout tout depuis `reward_rules`.
///   POST /api/app/rewards/express-consultation (Bearer) { product_key,
///        idempotency_key } -> ExpressConsultationResult
///     Débloque du temps de consultation contre des Étoiles (GROS CHANTIER
///     AURYEL Prompt 3/5). Coût/durée résolus par `express_products` côté
///     serveur — jamais fournis par Flutter.
class RewardsApi {
  RewardsApi(this._client);

  final ApiClient _client;

  Future<ShareProgress> recordDailyShare(String bearer) async {
    final json = await _client.postJson(
      '/api/app/rewards/daily-share',
      const {},
      bearer: bearer,
    );
    return ShareProgress.fromJson(json);
  }

  Future<ShareProgress> getShareProgress(String bearer) async {
    final json = await _client.getJson(
      '/api/app/rewards/share-progress',
      bearer: bearer,
    );
    return ShareProgress.fromJson(json);
  }

  Future<RewardWallet> getWallet(String bearer) async {
    final json = await _client.getJson(
      '/api/app/rewards/wallet',
      bearer: bearer,
    );
    return RewardWallet.fromJson(json);
  }

  Future<RewardClaimResult> claimAction({
    required String bearer,
    required String actionKey,
    String? eventId,
  }) async {
    final body = <String, dynamic>{'action_key': actionKey};
    if (eventId != null) body['event_id'] = eventId;
    final json = await _client.postJson(
      '/api/app/rewards/claim',
      body,
      bearer: bearer,
    );
    return RewardClaimResult.fromJson(json);
  }

  /// `POST /api/app/rewards/express-consultation { product_key,
  /// idempotency_key }`. `idempotencyKey` DOIT être stable pour UNE même
  /// tentative d'achat (générée une fois côté appelant, réutilisée telle
  /// quelle sur un retry) — jamais un montant/coût/durée envoyé ici.
  Future<ExpressConsultationResult> purchaseExpressConsultation({
    required String bearer,
    required String productKey,
    required String idempotencyKey,
  }) async {
    final json = await _client.postJson(
      '/api/app/rewards/express-consultation',
      {'product_key': productKey, 'idempotency_key': idempotencyKey},
      bearer: bearer,
    );
    return ExpressConsultationResult.fromJson(json);
  }
}

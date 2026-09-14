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

/// Une règle de récompense ACTIVE (le serveur n'expose jamais une règle
/// `enabled=false` : une action future désactivée n'apparaît jamais).
class RewardRule {
  const RewardRule({required this.ruleKey, required this.starsAmount});

  final String ruleKey;
  final int starsAmount;

  factory RewardRule.fromJson(Map<String, dynamic> json) => RewardRule(
    ruleKey: (json['rule_key'] ?? '').toString(),
    starsAmount: _asInt(json['stars_amount']),
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

/// Wallet Étoiles complet — RÉPONSE SERVEUR de `GET /api/app/rewards/wallet`,
/// source de vérité UNIQUE partagée par le header Accueil et l'écran Wallet.
class RewardWallet {
  const RewardWallet({
    required this.starsBalance,
    required this.rules,
    required this.streak,
    required this.recentTransactions,
  });

  final int starsBalance;

  /// UNIQUEMENT les règles actives — une action future désactivée
  /// (`mini_game_completed`, `rewarded_ad_completed`) n'apparaît jamais ici.
  final List<RewardRule> rules;
  final RewardStreak streak;
  final List<RewardTransaction> recentTransactions;

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
    return RewardWallet(
      starsBalance: _asInt(json['stars_balance']),
      rules: rules,
      streak: streak,
      recentTransactions: tx,
    );
  }

  static const RewardWallet empty = RewardWallet(
    starsBalance: 0,
    rules: [],
    streak: RewardStreak.zero,
    recentTransactions: [],
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
  }) async {
    final json = await _client.postJson('/api/app/rewards/claim', {
      'action_key': actionKey,
    }, bearer: bearer);
    return RewardClaimResult.fromJson(json);
  }
}

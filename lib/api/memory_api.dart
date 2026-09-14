import 'api_client.dart';

/// Difficultés du Jeu Auryel côté API (chaînes serveur). L'app mappe son enum
/// `GameDifficulty` (facile/moyen/intense) sur ces valeurs.
const List<String> kMemoryApiDifficulties = ['easy', 'medium', 'hard'];

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _asStrOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

/// Partie ouverte côté serveur. `gameId` est l'unique référence à passer à
/// [MemoryApi.complete] — le client ne transmet JAMAIS de chrono.
class MemoryGameSession {
  const MemoryGameSession({
    required this.gameId,
    required this.difficulty,
    required this.thresholdSeconds,
    required this.starsReward,
    required this.pairCount,
    required this.startedAt,
    required this.expiresAt,
  });

  final String gameId;
  final String difficulty;

  /// Réussir en STRICTEMENT moins de [thresholdSeconds] pour la récompense.
  final int thresholdSeconds;

  /// GROS CHANTIER AURYEL (Prompt 3/5) — Étoiles créditées si la partie est
  /// gagnée sous le seuil ET la catégorie mini-jeux encore éligible
  /// aujourd'hui (RÉSOLU côté serveur — `reward_rules.mini_game_completed`,
  /// jamais codé en dur, jamais figé par difficulté).
  final int starsReward;
  final int pairCount;
  final String? startedAt;
  final String? expiresAt;

  factory MemoryGameSession.fromJson(Map<String, dynamic> json) =>
      MemoryGameSession(
        gameId: (json['game_id'] ?? '').toString(),
        difficulty: (json['difficulty'] ?? '').toString(),
        thresholdSeconds: _asInt(json['threshold_seconds']),
        starsReward: _asInt(json['stars_reward']),
        pairCount: _asInt(json['pair_count']),
        startedAt: _asStrOrNull(json['started_at']),
        expiresAt: _asStrOrNull(json['expires_at']),
      );
}

/// Résultat serveur d'une partie terminée. `outcome` porte la raison :
///   'rewarded'             -> [rewardCredited] true, [starsAwarded] > 0
///   'time_limit_exceeded'  -> gagné mais trop lent, aucun crédit
///   'daily_limit_reached'  -> catégorie mini-jeux déjà récompensée AUJOURD'HUI
///                             (plafond PARTAGÉ avec Suite intuitive / Carte
///                             cachée — plus une fenêtre 7 j par difficulté)
///   'implausible_time'     -> partie physiquement impossible, ignorée
///   'expired'              -> game_id expiré
class MemoryCompleteResult {
  const MemoryCompleteResult({
    required this.status,
    required this.difficulty,
    required this.elapsedSeconds,
    required this.rewardCredited,
    required this.starsAwarded,
    required this.starsReward,
    required this.outcome,
    required this.alreadyFinalized,
  });

  final String status; // completed | expired
  final String difficulty;

  /// Chrono calculé PAR LE SERVEUR (now - started_at). Affichage seulement.
  final int elapsedSeconds;

  /// `true` UNIQUEMENT si CET appel vient d'accorder le crédit.
  final bool rewardCredited;
  final int starsAwarded;
  final int starsReward;
  final String outcome;
  final bool alreadyFinalized;

  bool get isTimeExceeded => outcome == 'time_limit_exceeded';
  bool get isDailyLimitReached => outcome == 'daily_limit_reached';
  bool get isExpired => outcome == 'expired' || status == 'expired';

  factory MemoryCompleteResult.fromJson(Map<String, dynamic> json) =>
      MemoryCompleteResult(
        status: (json['status'] ?? '').toString(),
        difficulty: (json['difficulty'] ?? '').toString(),
        elapsedSeconds: _asInt(json['elapsed_seconds']),
        rewardCredited: json['reward_credited'] == true,
        starsAwarded: _asInt(json['stars_awarded']),
        starsReward: _asInt(json['stars_reward']),
        outcome: (json['outcome'] ?? '').toString(),
        alreadyFinalized: json['already_finalized'] == true,
      );
}

/// Un niveau de jeu (paramètres de JEU — inchangés par le Prompt 3/5, la
/// récompense étant désormais commune aux 3 difficultés).
class MemoryDifficultyInfo {
  const MemoryDifficultyInfo({
    required this.difficulty,
    required this.thresholdSeconds,
    required this.pairCount,
  });

  final String difficulty;
  final int thresholdSeconds;
  final int pairCount;

  factory MemoryDifficultyInfo.fromJson(Map<String, dynamic> json) =>
      MemoryDifficultyInfo(
        difficulty: (json['difficulty'] ?? '').toString(),
        thresholdSeconds: _asInt(json['threshold_seconds']),
        pairCount: _asInt(json['pair_count']),
      );
}

/// Progression Memory — RÉPONSE SERVEUR, source de vérité. GROS CHANTIER
/// AURYEL (Prompt 3/5) : l'éligibilité est désormais PARTAGÉE par toute la
/// catégorie mini-jeux (Memory / Suite intuitive / Carte cachée), plus de
/// fenêtre 7 j indépendante par difficulté.
class MemoryProgress {
  const MemoryProgress({
    required this.eligibleToday,
    required this.starsReward,
    required this.nextResetAt,
    required this.difficulties,
  });

  /// `true` si AUCUN mini-jeu de la catégorie n'a encore été récompensé
  /// aujourd'hui (jour Europe/Paris, décidé serveur).
  final bool eligibleToday;
  final int starsReward;

  /// ISO-8601 : minuit Europe/Paris du lendemain, UNIQUEMENT si
  /// [eligibleToday] est faux.
  final String? nextResetAt;
  final List<MemoryDifficultyInfo> difficulties;

  factory MemoryProgress.fromJson(Map<String, dynamic> json) {
    final raw = json['difficulties'];
    final list = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(MemoryDifficultyInfo.fromJson)
              .toList(growable: false)
        : const <MemoryDifficultyInfo>[];
    return MemoryProgress(
      eligibleToday: json['eligible_today'] == true,
      starsReward: _asInt(json['stars_reward']),
      nextResetAt: _asStrOrNull(json['next_reset_at']),
      difficulties: list,
    );
  }
}

/// Jeu Memory + récompenses Étoiles côté app. Réutilise l'[ApiClient] commun —
/// aucun second client HTTP.
///
///   POST /api/app/memory/start    (Bearer) { difficulty } -> MemoryGameSession
///     À appeler AVANT de lancer réellement la partie.
///   POST /api/app/memory/complete (Bearer) { game_id }     -> MemoryCompleteResult
///     À appeler à la fin RÉELLE du jeu. Le body ne contient QUE `game_id` :
///     la décision de récompense (chrono, seuil, éligibilité du jour) est
///     prise UNIQUEMENT par le serveur.
///   GET  /api/app/memory/progress (Bearer)                 -> MemoryProgress
///     Lecture seule. Ne récompense jamais.
///
/// DÉPENDANCE BACKEND : tant que les endpoints ne répondent pas 2xx, l'appelant
/// laisse le jeu jouable sans récompense (aucun faux crédit côté client).
class MemoryApi {
  MemoryApi(this._client);

  final ApiClient _client;

  Future<MemoryGameSession> start({
    required String bearer,
    required String difficulty,
  }) async {
    final json = await _client.postJson('/api/app/memory/start', {
      'difficulty': difficulty,
    }, bearer: bearer);
    return MemoryGameSession.fromJson(json);
  }

  Future<MemoryCompleteResult> complete({
    required String bearer,
    required String gameId,
  }) async {
    final json = await _client.postJson('/api/app/memory/complete', {
      'game_id': gameId,
    }, bearer: bearer);
    return MemoryCompleteResult.fromJson(json);
  }

  Future<MemoryProgress> getProgress(String bearer) async {
    final json = await _client.getJson(
      '/api/app/memory/progress',
      bearer: bearer,
    );
    return MemoryProgress.fromJson(json);
  }
}

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
    required this.rewardSeconds,
    required this.pairCount,
    required this.startedAt,
    required this.expiresAt,
  });

  final String gameId;
  final String difficulty;

  /// Réussir en STRICTEMENT moins de [thresholdSeconds] pour la récompense.
  final int thresholdSeconds;

  /// Secondes de consultation créditées si la partie est gagnée sous le seuil
  /// ET la difficulté éligible (300 / 600 / 900).
  final int rewardSeconds;
  final int pairCount;
  final String? startedAt;
  final String? expiresAt;

  factory MemoryGameSession.fromJson(Map<String, dynamic> json) =>
      MemoryGameSession(
        gameId: (json['game_id'] ?? '').toString(),
        difficulty: (json['difficulty'] ?? '').toString(),
        thresholdSeconds: _asInt(json['threshold_seconds']),
        rewardSeconds: _asInt(json['reward_seconds']),
        pairCount: _asInt(json['pair_count']),
        startedAt: _asStrOrNull(json['started_at']),
        expiresAt: _asStrOrNull(json['expires_at']),
      );
}

/// Résultat serveur d'une partie terminée. `outcome` porte la raison :
///   'rewarded'             -> [rewardCredited] true, [creditedSeconds] > 0
///   'time_limit_exceeded'  -> gagné mais trop lent, aucun crédit
///   'cooldown_active'      -> difficulté déjà récompensée sur la fenêtre 7 j
///   'implausible_time'     -> partie physiquement impossible, ignorée
///   'expired'              -> game_id expiré
class MemoryCompleteResult {
  const MemoryCompleteResult({
    required this.status,
    required this.difficulty,
    required this.elapsedSeconds,
    required this.rewardCredited,
    required this.creditedSeconds,
    required this.rewardSeconds,
    required this.outcome,
    required this.nextEligibleAt,
    required this.alreadyFinalized,
  });

  final String status; // completed | expired
  final String difficulty;

  /// Chrono calculé PAR LE SERVEUR (now - started_at). Affichage seulement.
  final int elapsedSeconds;

  /// `true` UNIQUEMENT si CET appel vient d'accorder le crédit.
  final bool rewardCredited;
  final int creditedSeconds;
  final int rewardSeconds;
  final String outcome;

  /// ISO-8601 : quand cette difficulté redeviendra éligible (cooldown / crédit).
  final String? nextEligibleAt;
  final bool alreadyFinalized;

  bool get isTimeExceeded => outcome == 'time_limit_exceeded';
  bool get isCooldown => outcome == 'cooldown_active';
  bool get isExpired => outcome == 'expired' || status == 'expired';

  factory MemoryCompleteResult.fromJson(Map<String, dynamic> json) =>
      MemoryCompleteResult(
        status: (json['status'] ?? '').toString(),
        difficulty: (json['difficulty'] ?? '').toString(),
        elapsedSeconds: _asInt(json['elapsed_seconds']),
        rewardCredited: json['reward_credited'] == true,
        creditedSeconds: _asInt(json['credited_seconds']),
        rewardSeconds: _asInt(json['reward_seconds']),
        outcome: (json['outcome'] ?? '').toString(),
        nextEligibleAt: _asStrOrNull(json['next_eligible_at']),
        alreadyFinalized: json['already_finalized'] == true,
      );
}

/// Éligibilité d'une difficulté sur la fenêtre glissante de 7 jours.
class MemoryDifficultyProgress {
  const MemoryDifficultyProgress({
    required this.difficulty,
    required this.thresholdSeconds,
    required this.rewardSeconds,
    required this.eligibleNow,
    required this.lastRewardAt,
    required this.nextEligibleAt,
    required this.remainingSeconds,
  });

  final String difficulty;
  final int thresholdSeconds;
  final int rewardSeconds;
  final bool eligibleNow;
  final String? lastRewardAt;
  final String? nextEligibleAt;

  /// Secondes restantes avant nouvelle éligibilité (0 si éligible).
  final int remainingSeconds;

  factory MemoryDifficultyProgress.fromJson(Map<String, dynamic> json) =>
      MemoryDifficultyProgress(
        difficulty: (json['difficulty'] ?? '').toString(),
        thresholdSeconds: _asInt(json['threshold_seconds']),
        rewardSeconds: _asInt(json['reward_seconds']),
        eligibleNow: json['eligible_now'] == true,
        lastRewardAt: _asStrOrNull(json['last_reward_at']),
        nextEligibleAt: _asStrOrNull(json['next_eligible_at']),
        remainingSeconds: _asInt(json['remaining_seconds']),
      );
}

/// Progression Memory — RÉPONSE SERVEUR, source de vérité. Aucun compteur local
/// ne fait autorité : l'état survit à la fermeture de l'app, à la déconnexion
/// et au changement d'appareil.
class MemoryProgress {
  const MemoryProgress({
    required this.windowDays,
    required this.maxWindowSeconds,
    required this.difficulties,
  });

  final int windowDays;

  /// Total maximal crédité sur la fenêtre (1800 s = 30 min).
  final int maxWindowSeconds;
  final List<MemoryDifficultyProgress> difficulties;

  MemoryDifficultyProgress? forDifficulty(String apiDifficulty) {
    for (final d in difficulties) {
      if (d.difficulty == apiDifficulty) return d;
    }
    return null;
  }

  factory MemoryProgress.fromJson(Map<String, dynamic> json) {
    final raw = json['difficulties'];
    final list = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(MemoryDifficultyProgress.fromJson)
              .toList(growable: false)
        : const <MemoryDifficultyProgress>[];
    return MemoryProgress(
      windowDays: () {
        final n = _asInt(json['window_days']);
        return n > 0 ? n : 7;
      }(),
      maxWindowSeconds: () {
        final n = _asInt(json['max_window_seconds']);
        return n > 0 ? n : 1800;
      }(),
      difficulties: list,
    );
  }
}

/// Jeu Memory + récompenses de temps côté app. Réutilise l'[ApiClient] commun —
/// aucun second client HTTP.
///
///   POST /api/app/memory/start    (Bearer) { difficulty } -> MemoryGameSession
///     À appeler AVANT de lancer réellement la partie.
///   POST /api/app/memory/complete (Bearer) { game_id }     -> MemoryCompleteResult
///     À appeler à la fin RÉELLE du jeu. Le body ne contient QUE `game_id` :
///     la décision de récompense (chrono, seuil, éligibilité 7 j) est prise
///     UNIQUEMENT par le serveur.
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

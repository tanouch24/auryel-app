import 'api_client.dart';

/// GROS CHANTIER AURYEL (Prompt 3/5) — session serveur GÉNÉRIQUE de mini-jeu,
/// partagée par « Suite intuitive » (sequence_recall) et « Carte cachée »
/// (hidden_card). Le SERVEUR calcule le chrono et décide seul de la
/// récompense (règle PARTAGÉE `mini_game_completed`, même plafond quotidien
/// que le Jeu Memory) : le client ne transmet JAMAIS de chrono ni de
/// résultat de performance.
const List<String> kMiniGameKeys = ['sequence_recall', 'hidden_card'];

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

/// Session ouverte côté serveur. `sessionId` est l'unique référence à passer
/// à [MiniGameApi.finish].
class MiniGameSession {
  const MiniGameSession({
    required this.sessionId,
    required this.gameKey,
    required this.startedAt,
    required this.expiresAt,
  });

  final String sessionId;
  final String gameKey;
  final String? startedAt;
  final String? expiresAt;

  factory MiniGameSession.fromJson(Map<String, dynamic> json) => MiniGameSession(
    sessionId: (json['session_id'] ?? '').toString(),
    gameKey: (json['game_key'] ?? '').toString(),
    startedAt: _asStrOrNull(json['started_at']),
    expiresAt: _asStrOrNull(json['expires_at']),
  );
}

/// Résultat serveur d'une session terminée.
///   'rewarded'            -> [awarded] true, [starsAwarded] > 0
///   'daily_limit_reached' -> catégorie mini-jeux déjà récompensée aujourd'hui
///   'implausible_time'    -> manche physiquement impossible, ignorée
///   'already_finalized'   -> rejeu d'une session déjà close
///   'expired'             -> session expirée
class MiniGameResult {
  const MiniGameResult({
    required this.status,
    required this.outcome,
    required this.awarded,
    required this.starsAwarded,
    required this.newBalance,
  });

  final String status;
  final String? outcome;
  final bool awarded;
  final int starsAwarded;
  final int? newBalance;

  bool get isDailyLimitReached => outcome == 'daily_limit_reached';
  bool get isExpired => outcome == 'expired' || status == 'expired';

  factory MiniGameResult.fromJson(Map<String, dynamic> json) => MiniGameResult(
    status: (json['status'] ?? '').toString(),
    outcome: _asStrOrNull(json['outcome']),
    awarded: json['awarded'] == true,
    starsAwarded: _asInt(json['stars_awarded']),
    newBalance: json['new_balance'] == null ? null : _asInt(json['new_balance']),
  );
}

/// Mini-jeux (Suite intuitive / Carte cachée) côté app. Réutilise l'[ApiClient]
/// commun — aucun second client HTTP.
///
///   POST /api/app/minigame/start  (Bearer) { game_key } -> MiniGameSession
///   POST /api/app/minigame/finish (Bearer) { session_id } -> MiniGameResult
///
/// DÉPENDANCE BACKEND : tant que les endpoints ne répondent pas 2xx,
/// l'appelant laisse le jeu jouable sans récompense (aucun faux crédit).
class MiniGameApi {
  MiniGameApi(this._client);

  final ApiClient _client;

  Future<MiniGameSession> start({
    required String bearer,
    required String gameKey,
  }) async {
    final json = await _client.postJson('/api/app/minigame/start', {
      'game_key': gameKey,
    }, bearer: bearer);
    return MiniGameSession.fromJson(json);
  }

  Future<MiniGameResult> finish({
    required String bearer,
    required String sessionId,
  }) async {
    final json = await _client.postJson('/api/app/minigame/finish', {
      'session_id': sessionId,
    }, bearer: bearer);
    return MiniGameResult.fromJson(json);
  }
}

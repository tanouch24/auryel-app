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

/// Récompenses côté app. Réutilise l'[ApiClient] commun — aucun second client.
///
///   POST /api/app/rewards/daily-share    (Bearer) -> ShareProgress
///     Déclaré APRÈS un partage réellement lancé depuis Auryel. Le serveur
///     décide s'il compte le jour (max 1/jour) et s'il crédite au palier.
///   GET  /api/app/rewards/share-progress (Bearer) -> ShareProgress
///     Lecture seule, pour afficher « X / 30 ».
///
/// DÉPENDANCE BACKEND : endpoints construits dans la session parallèle. Tant
/// qu'ils ne répondent pas 2xx, [RewardsApi] propage l'erreur et l'appelant
/// retombe sur le cache local NON autoritaire.
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
}

import '../api/rewards_api.dart';

/// Accès à la récompense « 30 jours de partage = 1 h ».
///
/// LE BACKEND EST LA SOURCE DE VÉRITÉ. Cette classe ne calcule rien, ne
/// crédite rien : elle relaie [RewardsApi] et, en cas d'indisponibilité,
/// renvoie `null` pour que l'appelant retombe sur le cache local NON
/// autoritaire (`DailyShareTracker`).
///
/// AUCUNE ligne ne fait `+= 3600` ni ne modifie un solde de temps : après un
/// `credited == true`, l'appelant rafraîchit le portefeuille depuis le serveur.
class ShareRewardRepository {
  // Champs privés -> pas d'« initializing formal » possible (noms différents).
  // ignore_for_file: prefer_initializing_formals
  ShareRewardRepository({
    RewardsApi? api,
    required Future<String?> Function() tokenProvider,
  }) : _api = api,
       _token = tokenProvider;

  final RewardsApi? _api;

  /// Fournit le Bearer courant (`AuthController.currentToken` en production).
  final Future<String?> Function() _token;

  /// `true` si un endpoint récompense est réellement câblé.
  bool get available => _api != null;

  /// Déclare un jour de partage au serveur (après un partage réellement lancé
  /// depuis Auryel). Renvoie la progression serveur, ou `null` si l'appel n'a
  /// pas abouti (endpoint absent, réseau, 5xx, 401) — jamais d'exception
  /// remontée : le partage natif ne doit pas être perturbé.
  Future<ShareProgress?> recordShare() =>
      _guard((t) => _api!.recordDailyShare(t));

  /// Lecture seule de la progression « X / 30 ».
  Future<ShareProgress?> loadProgress() =>
      _guard((t) => _api!.getShareProgress(t));

  Future<ShareProgress?> _guard(
    Future<ShareProgress> Function(String token) call,
  ) async {
    final api = _api;
    if (api == null) return null;
    final token = await _token();
    if (token == null || token.isEmpty) return null;
    try {
      return await call(token);
    } catch (_) {
      return null; // mode dégradé : cache local non autoritaire
    }
  }
}

import 'api_client.dart';

/// Suppression définitive du compte + des données serveur associées (RGPD /
/// exigence Stores). Réutilise l'[ApiClient] commun — aucun second client HTTP.
///
///   DELETE /api/app/account   (Bearer)  -> 200/204 en cas de succès
///
/// DÉPENDANCE BACKEND : cet endpoint est construit dans la session backend
/// parallèle. Tant qu'il répond autre chose que 2xx, [AccountApi.deleteAccount]
/// lève ([ApiException] / [ApiUnauthorizedException] / [ApiNetworkException]) et
/// AUCUNE donnée locale n'est touchée (cf. [AccountDeletionService]).
///
/// Note : l'ancien audit (`account_service.dart`) évoquait `DELETE /api/account`.
/// La convention des endpoints app récents est `/api/app/*` (profil, rewards,
/// ai/report) — on s'aligne dessus. Si le contrat final diffère, seule cette
/// constante de chemin est à ajuster.
class AccountApi {
  AccountApi(this._client);

  final ApiClient _client;

  static const String path = '/api/app/account';

  Future<void> deleteAccount(String bearer) async {
    await _client.deleteJson(path, bearer: bearer);
  }
}

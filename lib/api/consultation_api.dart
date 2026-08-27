import 'api_client.dart';
import '../data/consultation.dart';

/// Endpoint de consultation (F3/F4). Réutilise l'[ApiClient] F1 — aucun second
/// client HTTP.
///
///   POST /api/consultation/message   (Bearer) { "message": "..." }
///   GET  /api/consultation/state     (Bearer)  — lecture seule, F4
///
/// Erreurs propagées telles quelles par [ApiClient] :
///  - 401 -> [ApiUnauthorizedException]  (purge session + retour login)
///  - 402 -> [ApiNoCreditException]       (mur Premium, `body['quota']`)
///  - réseau / timeout / TLS -> [ApiNetworkException]
///  - 5xx / autre -> [ApiException]
class ConsultationApi {
  ConsultationApi(this._client);

  final ApiClient _client;

  Future<ConsultationMessageResponse> sendMessage({
    required String bearer,
    required String message,
  }) async {
    final json = await _client.postJson(
      '/api/consultation/message',
      {'message': message},
      bearer: bearer,
    );
    return ConsultationMessageResponse.fromJson(json);
  }

  /// État courant de la consultation active + quota. Aucun crédit consommé,
  /// aucun appel LLM côté serveur.
  Future<ConsultationStateResponse> getState({required String bearer}) async {
    final json = await _client.getJson(
      '/api/consultation/state',
      bearer: bearer,
    );
    return ConsultationStateResponse.fromJson(json);
  }
}

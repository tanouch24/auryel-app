import 'api_client.dart';
import '../data/consultation.dart';

/// Endpoint de consultation (F3/F4). Réutilise l'[ApiClient] F1 — aucun second
/// client HTTP.
///
///   POST /api/consultation/message    (Bearer) { "message": "...", "tirage_id"? }
///   GET  /api/consultation/state      (Bearer)  — lecture seule, F4
///   GET  /api/consultation/messages   (Bearer)  — lecture seule, historique
///
/// T3 : `tirageId` optionnel. Fourni, il ajoute `tirage_id` au body (contexte
/// tirage injecté serveur AVANT toute consommation de crédit). Absent, le body
/// est EXACTEMENT `{ "message": ... }` — comportement historique inchangé.
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
    String? tirageId,
  }) async {
    final json = await _client.postJson(
      '/api/consultation/message',
      {
        'message': message,
        if (tirageId != null && tirageId.isNotEmpty) 'tirage_id': tirageId,
      },
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

  /// Historique des messages de la consultation active. Lecture seule : aucun
  /// crédit consommé, aucun appel LLM côté serveur, aucun POST.
  Future<ConsultationMessagesResponse> getMessages({
    required String bearer,
  }) async {
    final json = await _client.getJson(
      '/api/consultation/messages',
      bearer: bearer,
    );
    return ConsultationMessagesResponse.fromJson(json);
  }
}

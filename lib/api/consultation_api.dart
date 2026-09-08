import 'api_client.dart';
import '../data/consultation.dart';

/// Endpoint de consultation (F3/F4). Réutilise l'[ApiClient] F1 — aucun second
/// client HTTP.
///
///   POST /api/consultation/message    (Bearer) { "message", "consultation_id"?, "tirage_id"? }
///   POST /api/consultation/open       (Bearer) { "advisor_id" }              — J6
///   GET  /api/consultation/state      (Bearer)  — lecture seule, F4
///   GET  /api/consultation/messages   (Bearer)  — lecture seule, historique
///   GET  /api/consultation/list       (Bearer)  — lecture seule, tous les fils — J6
///
/// T3 : `tirageId` optionnel. Fourni, il ajoute `tirage_id` au body (contexte
/// tirage injecté serveur AVANT toute consommation de crédit). Absent, le body
/// est EXACTEMENT `{ "message": ... }` — comportement historique inchangé.
///
/// J6 : `consultationId` optionnel sur [sendMessage] / [getMessages] — cible un
/// fil précis (une discussion par conseiller). Absent -> comportement legacy
/// (fil le plus récent, choisi par le backend). Les écrans existants
/// (ChatScreen) restent compatibles tant que J6-F2 n'a pas migré leurs appels.
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
    String? consultationId,
    String? tirageId,
  }) async {
    final json = await _client.postJson('/api/consultation/message', {
      'message': message,
      if (consultationId != null && consultationId.isNotEmpty)
        'consultation_id': consultationId,
      if (tirageId != null && tirageId.isNotEmpty) 'tirage_id': tirageId,
    }, bearer: bearer);
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

  /// Historique des messages. J6 : `consultationId` fourni -> messages de CE fil
  /// (`?consultation_id=<uuid>`). Absent -> fil le plus récent (legacy). Lecture
  /// seule : aucun crédit, aucun appel LLM, aucun POST.
  Future<ConsultationMessagesResponse> getMessages({
    required String bearer,
    String? consultationId,
  }) async {
    final path = (consultationId != null && consultationId.isNotEmpty)
        ? '/api/consultation/messages?consultation_id='
              '${Uri.encodeQueryComponent(consultationId)}'
        : '/api/consultation/messages';
    final json = await _client.getJson(path, bearer: bearer);
    return ConsultationMessagesResponse.fromJson(json);
  }

  /// J6 — TOUS les fils de discussion de l'utilisateur (un par conseiller),
  /// triés « le plus récemment actif d'abord » côté backend. Lecture seule :
  /// aucun crédit, aucun débit, aucun POST, aucun cutoff `expires_at`.
  Future<List<ConsultationSummaryDto>> listConsultations({
    required String bearer,
  }) async {
    final json = await _client.getJson(
      '/api/consultation/list',
      bearer: bearer,
    );
    return ConsultationSummaryDto.listFromJson(json);
  }

  /// J6 — ouvre (ou REPREND) la discussion avec `advisorId`. Le backend renvoie
  /// le fil EXISTANT s'il y en a un pour ce conseiller, sinon en crée un NEUF
  /// (`consultation.opened_now`). Ne consomme aucun temps, n'ouvre aucune
  /// fenêtre facturable, ne modifie PAS le conseiller préféré du profil.
  Future<ConsultationDto> openConsultation({
    required String bearer,
    required String advisorId,
  }) async {
    final json = await _client.postJson('/api/consultation/open', {
      'advisor_id': advisorId,
    }, bearer: bearer);
    final c = json['consultation'];
    if (c is! Map<String, dynamic>) {
      throw ApiException(200, message: 'open: réponse sans objet consultation');
    }
    return ConsultationDto.fromJson(c);
  }
}

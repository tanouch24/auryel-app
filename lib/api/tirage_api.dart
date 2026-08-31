import 'api_client.dart';
import '../data/tirage.dart';

/// Endpoints du Tirage (T3). Réutilise l'[ApiClient] partagé — aucun second
/// client HTTP. Identité = jeton Bearer uniquement, jamais de `user_id` envoyé.
///
///   `POST /api/tirages`            (Bearer) `{ "card_keys": [k1, k2, k3] }`
///   `GET  /api/tirages`            (Bearer) `?limit=&before=`
///   `GET  /api/tirages/<id>`       (Bearer)
///
/// `POST /api/tirages` ne consomme AUCUN crédit et n'ouvre AUCUNE consultation :
/// c'est un simple SAVE. Erreurs propagées telles quelles par [ApiClient]
/// (401 -> [ApiUnauthorizedException], 404 -> [ApiException] `tirage_not_found`,
/// réseau -> [ApiNetworkException], 5xx/autre -> [ApiException]).
class TirageApi {
  TirageApi(this._client);

  final ApiClient _client;

  /// Sauvegarde d'un tirage. Le body ne contient QUE `card_keys` — jamais
  /// `user_id` / `advisor_id` / `interpretation` / `consultation_id`.
  Future<TirageResult> create({
    required String bearer,
    required List<String> cardKeys,
  }) async {
    final json = await _client.postJson('/api/tirages', {
      'card_keys': cardKeys,
    }, bearer: bearer);
    return TirageResult.fromJson(json);
  }

  /// Historique « Mon parcours », newest-first. `before` est un curseur ISO 8601
  /// renvoyé par le serveur (`next_cursor`) ; il est encodé proprement via [Uri].
  Future<TirageListResponse> list({
    required String bearer,
    int limit = 20,
    String? before,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null && before.isNotEmpty) query['before'] = before;
    final path = Uri(path: '/api/tirages', queryParameters: query).toString();
    final json = await _client.getJson(path, bearer: bearer);
    return TirageListResponse.fromJson(json);
  }

  /// Un tirage précis de l'utilisateur authentifié. 404 `tirage_not_found` si
  /// l'id est inconnu / appartient à un autre compte / est malformé.
  Future<TirageResult> get({
    required String bearer,
    required String tirageId,
  }) async {
    final json = await _client.getJson(
      '/api/tirages/${Uri.encodeComponent(tirageId)}',
      bearer: bearer,
    );
    return TirageResult.fromJson(json);
  }
}

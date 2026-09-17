import 'api_client.dart';

class UnreadApi {
  const UnreadApi(this._client);

  final ApiClient _client;

  Future<Map<String, int>> counts({String? bearer}) async {
    final body = await _client.getJson('/api/app/unread', bearer: bearer);
    final raw = body['counts'];
    if (raw is! Map) return const {};
    return raw.map<String, int>(
      (key, value) =>
          MapEntry(key.toString(), value is num ? value.toInt() : 0),
    );
  }

  Future<void> markRead(
    String category, {
    String? referenceKey,
    String? bearer,
  }) async {
    await _client.postJson('/api/app/unread/read', {
      'category': category,
      ...?referenceKey == null ? null : {'reference_key': referenceKey},
    }, bearer: bearer);
  }
}

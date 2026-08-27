import 'api_client.dart';
import '../data/account.dart';

/// Endpoints d'authentification du backend Auryel (email + code OTP).
///
///   POST /api/auth/request-code   {"email": "..."}
///   POST /api/auth/verify-code    {"email": "...", "code": "123456"} -> { token }
///   POST /api/auth/logout         (Bearer)
///   GET  /api/account             (Bearer) -> { user_id, email, ... }
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  Future<void> requestCode(String email) async {
    await _client.postJson('/api/auth/request-code', {'email': email});
  }

  /// Retourne le jeton de session opaque à conserver en stockage sécurisé.
  Future<String> verifyCode(String email, String code) async {
    final json = await _client.postJson('/api/auth/verify-code', {
      'email': email,
      'code': code,
    });
    final token = (json['token'] ?? json['session_token'] ?? json['access_token'])
        ?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(200, code: 'missing_token', message: 'Réponse sans token');
    }
    return token;
  }

  Future<Account> getAccount(String bearer) async {
    final json = await _client.getJson('/api/account', bearer: bearer);
    return Account.fromJson(json);
  }

  Future<void> logout(String bearer) async {
    await _client.postJson('/api/auth/logout', const {}, bearer: bearer);
  }
}

import 'api_client.dart';
import '../data/account.dart';

/// Endpoints d'authentification du backend Auryel.
///
/// AUTH V2 — voie officielle app (email + mot de passe, AUCUN code OTP) :
///   POST /api/app/auth/register   {"email": "...", "password": "..."} -> { token }
///   POST /api/app/auth/login      {"email": "...", "password": "..."} -> { token }
///
/// LEGACY — code OTP par email. Conservé UNIQUEMENT pour un futur parcours
/// « définir un mot de passe » sur un ancien compte (login 409 password_not_set).
/// Plus AUCUN nouvel utilisateur ne passe par là.
///   POST /api/auth/request-code   {"email": "..."}
///   POST /api/auth/verify-code    {"email": "...", "code": "123456"} -> { token }
///
///   POST /api/auth/logout         (Bearer)
///   GET  /api/account             (Bearer) -> { user_id, email, ... }
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  String _extractToken(Map<String, dynamic> json) {
    final token =
        (json['token'] ?? json['session_token'] ?? json['access_token'])
            ?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(
        200,
        code: 'missing_token',
        message: 'Réponse sans token',
      );
    }
    return token;
  }

  /// AUTH V2 — crée un compte (email + mot de passe) et renvoie le jeton de
  /// session. Le mot de passe n'est ni loggé ni conservé après l'appel.
  /// Erreurs relayées telles quelles : 400 `invalid_email` / `weak_password`,
  /// 409 `email_taken`, 503 `temporarily_unavailable`.
  Future<String> registerWithPassword(String email, String password) async {
    final json = await _client.postJson('/api/app/auth/register', {
      'email': email,
      'password': password,
    });
    return _extractToken(json);
  }

  /// AUTH V2 — connexion (email + mot de passe) -> jeton de session.
  /// Erreurs : 401 `invalid_credentials` (générique), 409 `password_not_set`
  /// (ancien compte OTP sans mot de passe), 503 `temporarily_unavailable`.
  Future<String> loginWithPassword(String email, String password) async {
    final json = await _client.postJson('/api/app/auth/login', {
      'email': email,
      'password': password,
    });
    return _extractToken(json);
  }

  Future<void> requestCode(String email) async {
    await _client.postJson('/api/auth/request-code', {'email': email});
  }

  /// Retourne le jeton de session opaque à conserver en stockage sécurisé.
  Future<String> verifyCode(String email, String code) async {
    final json = await _client.postJson('/api/auth/verify-code', {
      'email': email,
      'code': code,
    });
    return _extractToken(json);
  }

  Future<Account> getAccount(String bearer) async {
    final json = await _client.getJson('/api/account', bearer: bearer);
    return Account.fromJson(json);
  }

  Future<void> logout(String bearer) async {
    await _client.postJson('/api/auth/logout', const {}, bearer: bearer);
  }
}

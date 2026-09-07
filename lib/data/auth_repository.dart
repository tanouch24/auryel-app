import '../api/api_client.dart';
import '../api/auth_api.dart';
import 'account.dart';
import 'token_store.dart';

enum RestoreOutcome {
  /// Aucun jeton stocké — parcours login normal.
  noToken,

  /// Jeton présent, `GET /api/account` a répondu 200.
  valid,

  /// Jeton présent mais rejeté (401) — purgé, retour au login.
  expired,

  /// Jeton présent, serveur injoignable — jeton CONSERVÉ, mode dégradé.
  networkError,
}

class RestoreResult {
  const RestoreResult(this.outcome, [this.account]);
  final RestoreOutcome outcome;
  final Account? account;
}

/// Orchestration de l'auth email/OTP. Le jeton ne transite QUE par [TokenStore]
/// (stockage chiffré OS). Ne connaît rien de l'onboarding métier.
class AuthRepository {
  AuthRepository({required AuthApi api, required TokenStore tokenStore})
    // Champs privés -> impossible d'utiliser un « initializing formal ».
    // ignore: prefer_initializing_formals
    : _api = api,
      _tokens = tokenStore;

  final AuthApi _api;
  final TokenStore _tokens;

  Future<String?> currentToken() => _tokens.read();

  /// Purge locale du jeton, sans appel réseau. Utilisé quand un 401 est
  /// rencontré hors du flux de login (ex. PATCH profil).
  Future<void> clearSession() => _tokens.clear();

  /// AUTH V2 — crée le compte (email + mot de passe), stocke le jeton retourné,
  /// le renvoie. L'email est trimé ; le mot de passe n'est JAMAIS modifié.
  /// Lève [ApiException] (400/409/503…) sans écrire de jeton.
  Future<String> registerWithPasswordAndStore(
    String email,
    String password,
  ) async {
    final token = await _api.registerWithPassword(email.trim(), password);
    await _tokens.write(token);
    return token;
  }

  /// AUTH V2 — connexion (email + mot de passe), stocke le jeton, le renvoie.
  /// Lève [ApiException] (401 `invalid_credentials`, 409 `password_not_set`…)
  /// sans écrire de jeton.
  Future<String> loginWithPasswordAndStore(
    String email,
    String password,
  ) async {
    final token = await _api.loginWithPassword(email.trim(), password);
    await _tokens.write(token);
    return token;
  }

  /// LEGACY (OTP) — demande d'un code à usage unique par email. Conservé pour
  /// un futur parcours « définir un mot de passe » ; hors parcours actif.
  Future<void> requestCode(String email) => _api.requestCode(email.trim());

  /// Étape 2 — vérifie le code, stocke le jeton retourné, le renvoie.
  /// Lève [ApiException] / [ApiUnauthorizedException] si le code est mauvais
  /// ou expiré (AUCUN jeton n'est alors écrit).
  Future<String> verifyCodeAndStore(String email, String code) async {
    final token = await _api.verifyCode(email.trim(), code.trim());
    await _tokens.write(token);
    return token;
  }

  /// Récupère le compte avec le jeton stocké. Sur 401 : purge le jeton et
  /// relaie [ApiUnauthorizedException].
  Future<Account> fetchAccount() async {
    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      throw StateError('Aucun jeton de session');
    }
    try {
      return await _api.getAccount(token);
    } on ApiUnauthorizedException {
      await _tokens.clear();
      rethrow;
    }
  }

  /// Au démarrage : décide de l'état de session à partir du jeton stocké.
  Future<RestoreResult> restoreSession() async {
    final token = await _tokens.read();
    if (token == null || token.isEmpty) {
      return const RestoreResult(RestoreOutcome.noToken);
    }
    try {
      final account = await _api.getAccount(token);
      return RestoreResult(RestoreOutcome.valid, account);
    } on ApiUnauthorizedException {
      await _tokens.clear();
      return const RestoreResult(RestoreOutcome.expired);
    } on ApiNetworkException {
      // Panne réseau temporaire : on NE détruit PAS la session.
      return const RestoreResult(RestoreOutcome.networkError);
    } on ApiException {
      // 5xx / réponse inattendue : session non invalidée non plus.
      return const RestoreResult(RestoreOutcome.networkError);
    }
  }

  /// Déconnexion : appel best-effort à `POST /api/auth/logout`, puis purge
  /// locale du jeton dans tous les cas.
  Future<void> logout() async {
    final token = await _tokens.read();
    if (token != null && token.isNotEmpty) {
      try {
        await _api.logout(token);
      } catch (_) {
        // Le serveur peut être injoignable : la purge locale prime.
      }
    }
    await _tokens.clear();
  }
}

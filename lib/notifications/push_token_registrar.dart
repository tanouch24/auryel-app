// Paramètres nommés publics de nom différent des champs privés.
// ignore_for_file: prefer_initializing_formals
import 'dart:io' show Platform;

import '../api/api_client.dart';
import '../config/app_info.dart';

/// Enregistrement du jeton push auprès du backend Auryel.
///
/// Contrat backend (Migration v40) :
///   POST /api/app/push/register    (Bearer)
///     { "fcm_token": "...", "platform": "android",
///       "app_version"?: "...", "os_version"?: "...", "device_label"?: "..." }
///     -> 200 { "status": "registered" }   (upsert idempotent, réaffectation
///        du jeton au compte courant si le téléphone a changé de compte)
///   POST /api/app/push/unregister  (Bearer)
///     { "fcm_token": "..." }  -> 200 { "status": "unregistered" }  (idempotent)
///
/// Tout est BEST-EFFORT : aucune exception ne remonte (le push ne doit jamais
/// bloquer un login, un logout ou une suppression de compte). Le jeton n'est
/// jamais loggé.
abstract class PushTokenRegistrar {
  /// À faire après `currentToken()` et sur chaque `onTokenRefresh`, UNIQUEMENT
  /// quand une session est valide (Bearer disponible).
  Future<void> register(String token);

  /// À appeler à la déconnexion / suppression de compte, AVANT de perdre le
  /// Bearer. Best effort. `token` : le jeton de CET appareil.
  Future<void> unregister(String token);
}

/// Par défaut : ne fait rien (aucun endpoint câblé / pas de session). Ne lève
/// jamais, ne bloque jamais le démarrage.
class NoopPushTokenRegistrar implements PushTokenRegistrar {
  const NoopPushTokenRegistrar();

  @override
  Future<void> register(String token) async {}

  @override
  Future<void> unregister(String token) async {}
}

/// Implémentation HTTP réelle. [bearerProvider] renvoie le jeton de session
/// courant (ou `null` si déconnecté -> on n'appelle rien).
class HttpPushTokenRegistrar implements PushTokenRegistrar {
  HttpPushTokenRegistrar({
    required ApiClient apiClient,
    required Future<String?> Function() bearerProvider,
    String platform = 'android',
  })  : _api = apiClient,
        _bearer = bearerProvider,
        _platform = platform;

  final ApiClient _api;
  final Future<String?> Function() _bearer;
  final String _platform;

  String get _osVersion {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> register(String token) async {
    if (token.isEmpty) return;
    final bearer = await _safeBearer();
    if (bearer == null || bearer.isEmpty) return; // pas de session -> rien
    final os = _osVersion;
    try {
      await _api.postJson(
        '/api/app/push/register',
        {
          'fcm_token': token,
          'platform': _platform,
          'app_version': kAppVersion,
          if (os.isNotEmpty) 'os_version': os,
        },
        bearer: bearer,
      );
    } catch (_) {
      // best effort : 4xx/5xx/réseau -> on retentera au prochain refresh /
      // passage signedIn.
    }
  }

  @override
  Future<void> unregister(String token) async {
    if (token.isEmpty) return;
    final bearer = await _safeBearer();
    if (bearer == null || bearer.isEmpty) return;
    try {
      await _api.postJson(
        '/api/app/push/unregister',
        {'fcm_token': token},
        bearer: bearer,
      );
    } catch (_) {
      // best effort : le serveur purge de toute façon les devices à la
      // suppression de compte ; un logout ne doit jamais être bloqué.
    }
  }

  Future<String?> _safeBearer() async {
    try {
      return await _bearer();
    } catch (_) {
      return null;
    }
  }
}

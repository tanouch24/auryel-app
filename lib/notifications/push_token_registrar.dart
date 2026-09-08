/// Enregistrement du jeton push auprès du backend.
///
/// DÉPENDANCE BACKEND : **aucun endpoint d'enregistrement de push token n'est
/// défini dans le client aujourd'hui** (audité : rien dans `lib/api/*`). Tant
/// que le backend n'expose pas (par ex.) `POST /api/app/push/token`, on ne câble
/// RIEN et on n'invente aucune URL. L'implémentation par défaut est
/// [NoopPushTokenRegistrar] : elle absorbe les appels sans effet ni erreur.
///
/// Le jour où l'endpoint existe : ajouter `HttpPushTokenRegistrar(ApiClient,
/// tokenProvider)` derrière cette interface — le reste du code (service,
/// coordinateur) ne bouge pas.
abstract class PushTokenRegistrar {
  /// Transmet [token] au backend (à faire après [AuryelNotificationService]
  /// `currentToken()` et sur chaque `onTokenRefresh`).
  Future<void> register(String token);

  /// À appeler à la déconnexion / suppression de compte (best effort).
  Future<void> unregister();
}

/// Par défaut : ne fait rien (aucun endpoint). Ne lève jamais, ne bloque jamais
/// le démarrage.
class NoopPushTokenRegistrar implements PushTokenRegistrar {
  const NoopPushTokenRegistrar();

  @override
  Future<void> register(String token) async {
    /* pas d'endpoint -> no-op volontaire, jamais d'URL inventée */
  }

  @override
  Future<void> unregister() async {}
}

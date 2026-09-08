/// B10 — ANCIEN seam de suppression de compte. **REMPLACÉ** par
/// `AccountApi` (`DELETE /api/app/account`) + `AuthController.deleteAccount()`
/// + `LocalUserData.clearPersonal()`, qui orchestrent l'appel réel, la purge
/// du jeton et le nettoyage local UNIQUEMENT après un succès serveur.
///
/// Conservé sans usage pour compat ; ne rien construire dessus.
class AccountService {
  const AccountService();

  /// `true` uniquement quand un endpoint de suppression réel est câblé.
  static const bool deletionAvailable = false;

  /// Supprime définitivement le compte + les données serveur. Tant que
  /// [deletionAvailable] est `false`, lève [AccountDeletionUnavailable] sans
  /// rien toucher (ni local, ni serveur).
  Future<void> deleteAccount() async {
    throw const AccountDeletionUnavailable();
  }
}

/// La suppression de compte n'est pas encore disponible (endpoint backend
/// manquant). Aucune donnée n'a été touchée.
class AccountDeletionUnavailable implements Exception {
  const AccountDeletionUnavailable();

  @override
  String toString() => 'AccountDeletionUnavailable';
}

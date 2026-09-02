/// B10 — seam pour la suppression de compte (RGPD).
///
/// L'audit backend (auryel-1 @ 37e82b8) confirme : **aucun endpoint app de
/// hard-delete `accounts` n'existe** (`/api/account` = GET only, `deleted_at`
/// jamais posé par une route, la purge RGPD ne touche que le legacy `phone`).
///
/// Ce lot NE FAIT DONC AUCUNE suppression — locale ou distante. La confirmation
/// UI existe, mais [deleteAccount] lève [AccountDeletionUnavailable]. Quand
/// l'endpoint B10 backend (`DELETE /api/account`, cascade multi-tables) sera
/// prêt, il suffira de brancher son appel ici — le reste de l'UI ne bouge pas.
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

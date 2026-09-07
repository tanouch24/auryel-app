/// Décisions PURES pour la restauration de profil multi-appareil — testables
/// sans widget ni réseau. Utilisé par `EmailAuthScreen` (login) et
/// `SplashScreen` (restauration de session).
class SessionProfileGate {
  const SessionProfileGate._();

  /// `true` si l'identité locale persistée appartient à un AUTRE compte réel
  /// (jamais un identifiant temporaire `temp_…`) : elle doit être oubliée
  /// AVANT toute récupération serveur, pour n'afficher aucune donnée de
  /// l'utilisateur précédent.
  static bool mustForgetLocalIdentity({
    required String accountUserId,
    required String? localUserId,
  }) {
    if (accountUserId.isEmpty || localUserId == null || localUserId.isEmpty) {
      return false;
    }
    return localUserId != accountUserId && !localUserId.startsWith('temp_');
  }

  /// `true` si le profil local est COMPLET (prénom + date de naissance +
  /// conseiller) ET rattaché au compte connecté : le démarrage peut se faire
  /// directement, sans appel `GET /api/app/profile` (pas de ralentissement
  /// inutile). Sinon, il faut récupérer le profil serveur réel.
  static bool localProfileUsableAsIs({
    required String accountUserId,
    required String? localUserId,
    required String? firstName,
    required DateTime? birthDate,
    required String? selectedAdvisor,
  }) {
    if (accountUserId.isEmpty) return false;
    final sameAccount = localUserId != null && localUserId == accountUserId;
    final complete =
        (firstName?.isNotEmpty ?? false) &&
        birthDate != null &&
        (selectedAdvisor?.isNotEmpty ?? false);
    return sameAccount && complete;
  }
}

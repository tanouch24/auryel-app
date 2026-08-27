/// Profil app renvoyé par `GET` / `PATCH /api/app/profile`.
/// `cheminDeVie` et `signeZodiaque` sont calculés PAR LE BACKEND à partir de
/// `dateNaissance` — jamais côté Flutter.
class AppProfile {
  const AppProfile({
    required this.userId,
    required this.guide,
    required this.prenom,
    required this.dateNaissance,
    required this.cheminDeVie,
    required this.signeZodiaque,
  });

  final String userId;
  final String guide;
  final String prenom;

  /// ISO `YYYY-MM-DD` ou `null`.
  final String? dateNaissance;
  final String cheminDeVie;
  final String signeZodiaque;

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    final dn = json['date_naissance'];
    return AppProfile(
      userId: (json['user_id'] ?? '').toString(),
      guide: (json['guide'] ?? '').toString(),
      prenom: (json['prenom'] ?? '').toString(),
      dateNaissance: (dn is String && dn.isNotEmpty) ? dn : null,
      cheminDeVie: (json['chemin_de_vie'] ?? '').toString(),
      signeZodiaque: (json['signe_zodiaque'] ?? '').toString(),
    );
  }
}

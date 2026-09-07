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

  /// [dateNaissance] converti en [DateTime] normalisé à minuit (heure locale),
  /// ou `null` si absent / non ISO. Parsing STRICT ISO (`DateTime.tryParse`) :
  /// on ne réutilise pas `parseBirthDate` (saisie libre JJ/MM/AAAA) qui
  /// interpréterait `2000-05-17` à l'envers.
  DateTime? get birthDateOrNull {
    final raw = dateNaissance;
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

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

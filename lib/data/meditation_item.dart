/// Modèle d'une séance de « Ton Moment » (méditation guidée courte).
///
/// Aucune promesse médicale : les descriptions parlent de « ralentir »,
/// « décrocher », « revenir au calme » — jamais de soin, thérapie ou
/// traitement. Le contenu audio réel (fichiers `assets/meditations/*`) est un
/// livrable de contenu distinct ; tant qu'un fichier est absent, l'écran le
/// signale proprement sans planter (cf. [MeditationAudio]).
enum MeditationCategory {
  detente('Détente'),
  respiration('Respiration'),
  sommeil('Sommeil'),
  recentrage('Recentrage'),
  lacherPrise('Lâcher prise');

  const MeditationCategory(this.label);

  /// Libellé affichable (français, sans jargon).
  final String label;
}

class MeditationItem {
  const MeditationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.assetPath,
    required this.duration,
    required this.category,
  });

  /// Slug stable — sert de clé et de nom de fichier attendu
  /// (`assets/meditations/<id>.m4a`).
  final String id;

  /// Titre court de la séance.
  final String title;

  /// Une phrase, sans promesse médicale.
  final String description;

  /// Chemin relatif à `assets/` (convention `AssetSource` d'audioplayers).
  final String assetPath;

  /// Durée annoncée de la séance (indicative tant que l'audio n'est pas monté).
  final Duration duration;

  final MeditationCategory category;

  /// « 6 min » — format compact pour l'entête de l'écran.
  String get durationLabel {
    final m = duration.inMinutes;
    if (m <= 0) return '${duration.inSeconds} s';
    return '$m min';
  }
}

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
    this.audioUrl,
  });

  /// Slug stable — sert de clé et de nom de fichier attendu
  /// (`assets/meditations/<id>.m4a`).
  final String id;

  /// Titre court de la séance.
  final String title;

  /// Une phrase, sans promesse médicale.
  final String description;

  /// Chemin relatif à `assets/` (convention `AssetSource` d'audioplayers).
  /// Peut être vide pour une séance servie par le backend (voir [audioUrl]).
  final String assetPath;

  /// URL audio DISTANTE (catalogue backend). `null` pour le catalogue
  /// embarqué. Ignorée si elle n'est pas une URL `http(s)` exploitable.
  final String? audioUrl;

  /// Durée annoncée de la séance (indicative tant que l'audio n'est pas monté).
  final Duration duration;

  final MeditationCategory category;

  /// Source réellement passée au lecteur : l'URL distante si elle est
  /// exploitable, sinon le chemin d'asset local.
  String get playbackSource {
    final u = audioUrl;
    if (u != null && (u.startsWith('http://') || u.startsWith('https://'))) {
      return u;
    }
    return assetPath;
  }

  /// `true` si une source lisible existe (URL distante OU chemin d'asset non
  /// vide). Une entrée sans aucune des deux n'est pas jouable — l'écran affiche
  /// alors son état « bientôt disponible » sans tenter de lecture.
  bool get hasPlayableSource => playbackSource.isNotEmpty;

  /// « 6 min » — format compact pour l'entête de l'écran.
  String get durationLabel {
    final m = duration.inMinutes;
    if (m <= 0) return '${duration.inSeconds} s';
    return '$m min';
  }

  /// Parsing TOLÉRANT d'une entrée du catalogue
  /// `GET /api/app/content/meditations`. Renvoie `null` si `id` ou `title`
  /// manque : l'entrée est alors ignorée (jamais de crash).
  static MeditationItem? tryFromJson(Map<String, dynamic> j) {
    final id = (j['id'] is String) ? (j['id'] as String).trim() : '';
    final title = (j['title'] is String) ? (j['title'] as String).trim() : '';
    if (id.isEmpty || title.isEmpty) return null;

    final url = j['audio_url'];
    final asset = j['asset_path'];
    Duration duration = Duration.zero;
    final ds = j['duration_seconds'];
    if (ds is num) {
      duration = Duration(seconds: ds.toInt());
    } else {
      final dm = j['duration_minutes'];
      if (dm is num) duration = Duration(minutes: dm.toInt());
    }

    return MeditationItem(
      id: id,
      title: title,
      description: (j['description'] is String)
          ? (j['description'] as String).trim()
          : '',
      assetPath: (asset is String && asset.isNotEmpty) ? asset : '',
      audioUrl: (url is String && url.isNotEmpty) ? url : null,
      duration: duration,
      category: _categoryFrom(j['category']),
    );
  }

  static MeditationCategory _categoryFrom(Object? raw) {
    final s = raw is String ? raw.trim().toLowerCase() : '';
    for (final c in MeditationCategory.values) {
      if (c.name.toLowerCase() == s || c.label.toLowerCase() == s) return c;
    }
    return MeditationCategory.detente;
  }
}

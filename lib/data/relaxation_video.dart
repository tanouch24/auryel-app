/// Vidéo d'ambiance apaisante — habillage VISUEL (toujours MUET) joué en fond
/// d'une séance « Ton Moment ». Le son de la méditation vient exclusivement de
/// l'audio MP3 ([MeditationItem.playbackSource]).
///
/// Catalogue 100 % distant (`GET /api/app/content/relaxation-videos`), sans
/// liste figée ni plafond côté app. `category` est un TEXTE LIBRE (ocean, rain,
/// forest, night, calm, …) — surtout pas un enum fermé : une valeur inconnue
/// est simplement conservée telle quelle.
class RelaxationVideo {
  const RelaxationVideo({
    required this.id,
    required this.slug,
    required this.title,
    required this.videoUrl,
    this.thumbnailUrl,
    this.category = 'calm',
    this.tags = const <String>[],
    this.compatibleMeditationCategories = const <String>[],
    this.isGeneric = true,
  });

  /// Identifiant stable (UUID côté backend).
  final String id;

  /// Slug stable — clé d'anti-répétition (historique local).
  final String slug;

  final String title;

  /// URL HTTPS streamée. Jamais téléchargée en entier.
  final String videoUrl;

  final String? thumbnailUrl;

  /// Ambiance libre. Défaut `calm` (générique).
  final String category;

  /// Mots-clés d'ambiance (peut être vide).
  final List<String> tags;

  /// Catégories de méditation jugées compatibles par le backend.
  final List<String> compatibleMeditationCategories;

  /// `true` -> utilisable pour TOUTES les méditations (repli générique).
  final bool isGeneric;

  /// `true` si la vidéo peut accompagner une méditation de catégorie [medCat].
  /// Une vidéo générique passe toujours. Comparaison insensible à la casse.
  bool isCompatibleWith(String medCat) {
    if (isGeneric) return true;
    final needle = medCat.trim().toLowerCase();
    if (needle.isEmpty) return false;
    for (final c in compatibleMeditationCategories) {
      if (c.trim().toLowerCase() == needle) return true;
    }
    return false;
  }

  /// Parsing TOLÉRANT d'une entrée du catalogue. Renvoie `null` si `id` ou
  /// `video_url` exploitable manque : l'entrée est alors ignorée (jamais de
  /// crash), les autres passent. Toute clé inconnue est ignorée.
  static RelaxationVideo? tryFromJson(Map<String, dynamic> j) {
    final id = (j['id'] is String) ? (j['id'] as String).trim() : '';
    final url = (j['video_url'] is String)
        ? (j['video_url'] as String).trim()
        : '';
    if (id.isEmpty) return null;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return null;

    final rawTitle = (j['title'] is String) ? (j['title'] as String).trim() : '';
    final rawCat = (j['category'] is String)
        ? (j['category'] as String).trim()
        : '';

    return RelaxationVideo(
      id: id,
      slug: (j['slug'] is String && (j['slug'] as String).trim().isNotEmpty)
          ? (j['slug'] as String).trim()
          : id,
      title: rawTitle.isNotEmpty ? rawTitle : 'Ambiance apaisante',
      videoUrl: url,
      thumbnailUrl:
          (j['thumbnail_url'] is String &&
              (j['thumbnail_url'] as String).isNotEmpty)
          ? (j['thumbnail_url'] as String)
          : null,
      category: rawCat.isNotEmpty ? rawCat : 'calm',
      tags: _stringList(j['tags']),
      compatibleMeditationCategories: _stringList(
        j['compatible_meditation_categories'],
      ),
      isGeneric: j['is_generic'] is bool
          ? j['is_generic'] as bool
          // Repli : sans info explicite, une vidéo sans compatibilité listée
          // est traitée comme générique (utilisable partout) ; une vidéo qui a
          // des compatibilités listées n'est PAS générique.
          : _stringList(j['compatible_meditation_categories']).isEmpty,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'slug': slug,
    'title': title,
    'video_url': videoUrl,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    'category': category,
    'tags': tags,
    'compatible_meditation_categories': compatibleMeditationCategories,
    'is_generic': isGeneric,
  };

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }
}

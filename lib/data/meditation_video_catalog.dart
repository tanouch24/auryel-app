import 'relaxation_video.dart';

/// Catalogue éditorial des vidéos réellement publiées dans le bucket Auryel.
///
/// Le bucket n'est volontairement pas listé par le client. Une vidéo devient
/// visible après déclaration ici, avec son objet de stockage réel et ses
/// métadonnées éditoriales.
class MeditationVideoEntry {
  const MeditationVideoEntry({
    required this.id,
    required this.title,
    required this.objectKey,
    required this.url,
    this.thumbnailUrl,
    this.duration,
    this.category,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String title;
  final String objectKey;
  final String url;
  final String? thumbnailUrl;
  final Duration? duration;
  final String? category;
  final int sortOrder;
  final bool isActive;

  bool get hasMeditationObjectKey => objectKey.startsWith('meditation-videos/');

  RelaxationVideo toRelaxationVideo() => RelaxationVideo(
    id: id,
    slug: id,
    title: title,
    videoUrl: url,
    category: category ?? '',
    thumbnailUrl: thumbnailUrl,
  );
}

class MeditationVideoCatalog {
  const MeditationVideoCatalog._();

  /// Catalogue éditorial indépendant du catalogue Réveil.
  /// Il reste vide tant qu'une vraie vidéo n'a pas été uploadée sous
  /// `meditation-videos/` puis déclarée ici.
  static const List<MeditationVideoEntry> entries = [];

  static List<RelaxationVideo> activeVideos() {
    final active =
        entries
            .where((entry) => entry.isActive && entry.hasMeditationObjectKey)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return active.map((entry) => entry.toRelaxationVideo()).toList();
  }
}

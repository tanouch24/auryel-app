import 'relaxation_video.dart';
import 'wake_video.dart';

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

  /// Seul contenu vidéo actuellement publié et vérifié dans le bucket.
  static const pilot = MeditationVideoEntry(
    id: 'wake-test-01',
    title: 'Réveil Auryel',
    objectKey: 'wake-videos/auryel-reveil-video-test-01.mp4',
    url: WakeVideoCatalog.pilotRemoteUrl,
    thumbnailUrl: null,
    duration: null,
    category: 'Ambiance du matin',
    sortOrder: 0,
    isActive: true,
  );

  static const List<MeditationVideoEntry> entries = [pilot];

  static List<RelaxationVideo> activeVideos() {
    final active = entries.where((entry) => entry.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return active.map((entry) => entry.toRelaxationVideo()).toList();
  }
}

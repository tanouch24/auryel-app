import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/meditation_video_catalog.dart';

void main() {
  test('le catalogue actif ne déclare que le fichier R2 réellement publié', () {
    expect(MeditationVideoCatalog.entries, hasLength(1));
    final pilot = MeditationVideoCatalog.entries.single;
    expect(pilot.objectKey, 'wake-videos/auryel-reveil-video-test-01.mp4');
    expect(pilot.url, WakeVideoUrlExpectation.pilot);
    expect(pilot.isActive, isTrue);
    expect(MeditationVideoCatalog.activeVideos(), hasLength(1));
    expect(
      MeditationVideoCatalog.activeVideos().single.videoUrl,
      WakeVideoUrlExpectation.pilot,
    );
  });
}

/// La constante est répétée dans le test pour rendre le contrat de l'objet
/// vérifiable sans dépendre de l'implémentation du catalogue Réveil.
class WakeVideoUrlExpectation {
  static const pilot =
      'https://pub-19c78d4dc57a41849a27c0e73ed231ce.r2.dev/'
      'wake-videos/auryel-reveil-video-test-01.mp4';
}

import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/meditation_video_catalog.dart';

void main() {
  test('le pilote Wake n’apparait plus dans Méditations', () {
    expect(MeditationVideoCatalog.entries, isEmpty);
    expect(MeditationVideoCatalog.activeVideos(), isEmpty);
  });

  test('une entrée Méditation doit appartenir à meditation-videos', () {
    const wakeEntry = MeditationVideoEntry(
      id: 'wake',
      title: 'Ne pas découvrir',
      objectKey: 'wake-videos/auryel-reveil-video-test-01.mp4',
      url: 'https://example.test/wake.mp4',
      sortOrder: 0,
      isActive: true,
    );
    expect(wakeEntry.hasMeditationObjectKey, isFalse);

    const meditationEntry = MeditationVideoEntry(
      id: 'meditation',
      title: 'Future méditation',
      objectKey: 'meditation-videos/future.mp4',
      url: 'https://example.test/future.mp4',
      sortOrder: 0,
      isActive: true,
    );
    expect(meditationEntry.hasMeditationObjectKey, isTrue);
  });
}

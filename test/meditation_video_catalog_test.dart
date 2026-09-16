import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/meditation_video_catalog.dart';

void main() {
  test('le pilote Wake n’apparait plus dans Méditations', () {
    expect(MeditationVideoCatalog.entries, isEmpty);
    expect(MeditationVideoCatalog.activeVideos(), isEmpty);
  });

  test('une entrée Méditation doit appartenir à meditations', () {
    const wakeEntry = MeditationVideoEntry(
      id: 'wake',
      title: 'Ne pas découvrir',
      objectKey: 'wake-videos/auryel-reveil-video-test-01.mp4',
      url: 'https://example.test/wake.mp4',
      sortOrder: 0,
      isActive: true,
    );
    expect(wakeEntry.hasMeditationObjectKey, isFalse);

    const legacyEntry = MeditationVideoEntry(
      id: 'meditation',
      title: 'Ancien préfixe',
      objectKey: 'meditation-videos/future.mp4',
      url: 'https://example.test/future.mp4',
      sortOrder: 0,
      isActive: true,
    );
    expect(legacyEntry.hasMeditationObjectKey, isFalse);

    const meditationEntry = MeditationVideoEntry(
      id: 'meditation',
      title: 'Future méditation',
      objectKey: 'meditations/future.mp4',
      url: 'https://example.test/future.mp4',
      sortOrder: 0,
      isActive: true,
    );
    expect(meditationEntry.hasMeditationObjectKey, isTrue);
  });

  test('le catalogue refuse les objets qui ne sont pas des MP4 méditation', () {
    const invalid = [
      'wake-videos/other.mp4',
      'meditations/cover.jpg',
      'meditations/',
      'meditations',
    ];
    for (final key in invalid) {
      final entry = MeditationVideoEntry(
        id: key,
        title: 'Entrée',
        objectKey: key,
        url: 'https://example.test/file.mp4',
        sortOrder: 0,
        isActive: true,
      );
      expect(entry.hasMeditationObjectKey, isFalse, reason: key);
    }
  });
}

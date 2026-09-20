import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_video.dart';

void main() {
  test('catalogue pilote contient une vidéo R2 stable', () {
    expect(WakeVideoCatalog.active, hasLength(1));
    expect(WakeVideoCatalog.pilot.id, 'wake-test-01');
    expect(WakeVideoCatalog.pilot.remoteUrl, startsWith('https://'));
  });

  test('sélection quotidienne stable et sans répétition immédiate', () {
    final catalog = List.generate(
      59,
      (i) => WakeVideo(
        id: 'wake-$i',
        remoteUrl: 'https://cdn.example/wake-$i.mp4',
        sortOrder: i,
      ),
    );
    final first = WakeVideoDailySelection.pick(catalog, DateTime(2026, 9, 20));
    final again = WakeVideoDailySelection.pick(catalog, DateTime(2026, 9, 20));
    final next = WakeVideoDailySelection.pick(catalog, DateTime(2026, 9, 21));
    expect(again.id, first.id);
    expect(next.id, isNot(first.id));
  });

  test('pilote exclu de la rotation quand les vraies vidéos existent', () {
    final catalog = [
      WakeVideoCatalog.pilot,
      ...List.generate(
        59,
        (i) => WakeVideo(
          id: 'wake-$i',
          remoteUrl: 'https://cdn.example/wake-$i.mp4',
          sortOrder: i,
        ),
      ),
    ];
    final ids = List.generate(
      7,
      (i) => WakeVideoDailySelection.pick(
        catalog,
        DateTime(2026, 9, 20 + i),
      ).id,
    );
    expect(ids, everyElement(isNot(WakeVideoCatalog.pilot.id)));
  });

  test('pilote conservé comme fallback si aucune vraie vidéo existe', () {
    expect(
      WakeVideoDailySelection.pick(
        [WakeVideoCatalog.pilot],
        DateTime(2026, 9, 20),
      ).id,
      WakeVideoCatalog.pilot.id,
    );
  });

  test('rotation déterministe sur sept jours avec catalogue suffisant', () {
    final catalog = List.generate(
      59,
      (i) => WakeVideo(
        id: 'wake-$i',
        remoteUrl: 'https://cdn.example/wake-$i.mp4',
        sortOrder: i,
      ),
    );
    final ids = List.generate(
      7,
      (i) =>
          WakeVideoDailySelection.pick(catalog, DateTime(2026, 9, 20 + i)).id,
    );
    expect(ids.toSet(), hasLength(7));
  });

  test('parsing ignore une URL non exploitable', () {
    expect(
      WakeVideo.tryFromJson({'id': 'x', 'video_url': '/local.mp4'}),
      isNull,
    );
    expect(
      WakeVideo.tryFromJson({
        'id': 'x',
        'title': 'Bonjour',
        'video_url': 'https://cdn/x.mp4',
        'duration_seconds': 30,
      })!.title,
      'Bonjour',
    );
  });

  test('cache réutilise un fichier local non vide', () async {
    final directory = await Directory.systemTemp.createTemp('auryel-wake-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/wake-test-01.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    final cache = WakeVideoCache(directory: directory);
    addTearDown(cache.close);

    final prepared = await cache.prepare(WakeVideoCatalog.pilot);
    expect(prepared?.path, file.path);
    expect(await prepared!.length(), 3);
  });

  test('chemin local explicite valide prioritaire', () async {
    final directory = await Directory.systemTemp.createTemp('auryel-wake-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/local.mp4')..writeAsBytesSync([7]);
    final cache = WakeVideoCache(directory: directory);
    addTearDown(cache.close);

    final video = WakeVideo(
      id: 'local',
      remoteUrl: 'https://example.invalid/video.mp4',
      localPath: file.path,
    );
    expect((await cache.prepare(video))?.path, file.path);
  });
}

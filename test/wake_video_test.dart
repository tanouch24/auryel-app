import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_video.dart';

void main() {
  test('catalogue pilote contient une vidéo R2 stable', () {
    expect(WakeVideoCatalog.active, hasLength(1));
    expect(WakeVideoCatalog.pilot.id, 'wake-test-01');
    expect(WakeVideoCatalog.pilot.remoteUrl, startsWith('https://'));
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

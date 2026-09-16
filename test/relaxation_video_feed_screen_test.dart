import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:auryel/data/relaxation_video.dart';
import 'package:auryel/screens/relaxation_video_feed_screen.dart';
import 'package:auryel/widgets/relaxation_video_background.dart';

class _FakeSurface implements RelaxationVideoCompletionSurface {
  bool ready = false;
  int playCount = 0;
  int pauseCount = 0;
  final value = ValueNotifier(
    const VideoPlayerValue(isInitialized: true, duration: Duration(seconds: 1)),
  );

  @override
  Future<bool> load(String url) async {
    ready = true;
    return true;
  }

  @override
  Future<bool> play() async {
    if (!ready) return false;
    playCount++;
    return true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  ValueListenable<VideoPlayerValue> get valueListenable => value;

  void emitCompleted() {
    value.value = const VideoPlayerValue(
      isInitialized: true,
      duration: Duration(seconds: 1),
      position: Duration(seconds: 1),
      isCompleted: true,
    );
  }

  @override
  Widget buildView() => const ColoredBox(color: Colors.black);

  @override
  bool get isReady => ready;

  @override
  void dispose() => value.dispose();
}

RelaxationVideo _video() => const RelaxationVideo(
  id: 'pilot',
  slug: 'pilot',
  title: 'Vidéo pilote',
  videoUrl: 'https://example.com/pilot.mp4',
  category: 'Relaxation',
);

void main() {
  testWidgets(
    'un seul contenu : autoplay, pause/play et limites horizontales',
    (tester) async {
      final surfaces = <_FakeSurface>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RelaxationVideoFeedScreen(
            videos: [_video()],
            surfaceFactory: () {
              final surface = _FakeSurface();
              surfaces.add(surface);
              return surface;
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Vidéo pilote'), findsOneWidget);
      expect(find.text('0 s'), findsNothing);
      expect(surfaces.single.playCount, 1);

      await tester.tap(find.bySemanticsLabel('Mettre en pause'));
      await tester.pump();
      expect(surfaces.single.pauseCount, greaterThanOrEqualTo(1));
      await tester.tap(find.bySemanticsLabel('Lire'));
      await tester.pump();
      expect(surfaces.single.playCount, 2);

      expect(find.text('1 / 1'), findsNothing);
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Vidéo pilote'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(600, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Vidéo pilote'), findsOneWidget);
    },
  );

  testWidgets('la fin réelle passe exactement à la vidéo suivante', (
    tester,
  ) async {
    final surfaces = <_FakeSurface>[];
    final changed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RelaxationVideoFeedScreen(
          videos: const [
            RelaxationVideo(
              id: 'a',
              slug: 'a',
              title: 'A',
              videoUrl: 'https://example.com/a.mp4',
            ),
            RelaxationVideo(
              id: 'b',
              slug: 'b',
              title: 'B',
              videoUrl: 'https://example.com/b.mp4',
            ),
          ],
          surfaceFactory: () {
            final surface = _FakeSurface();
            surfaces.add(surface);
            return surface;
          },
          onItemChanged: (video) => changed.add(video.slug),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(surfaces, isNotEmpty);
    for (final surface in surfaces) {
      surface.emitCompleted();
    }
    await tester.pumpAndSettle();
    expect(changed, hasLength(1));
    expect(changed.single, anyOf('a', 'b'));
  });
}

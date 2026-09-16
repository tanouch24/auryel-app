import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/relaxation_video.dart';
import 'package:auryel/screens/relaxation_video_feed_screen.dart';
import 'package:auryel/widgets/relaxation_video_background.dart';

class _FakeSurface implements RelaxationVideoSurface {
  bool ready = false;
  int playCount = 0;
  int pauseCount = 0;

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
  Widget buildView() => const ColoredBox(color: Colors.black);

  @override
  bool get isReady => ready;

  @override
  void dispose() {}
}

RelaxationVideo _video() => const RelaxationVideo(
  id: 'pilot',
  slug: 'pilot',
  title: 'Vidéo pilote',
  videoUrl: 'https://example.com/pilot.mp4',
  category: 'Relaxation',
);

void main() {
  testWidgets('un seul contenu : autoplay, pause/play et limites verticales', (
    tester,
  ) async {
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

    await tester.fling(find.byType(PageView), const Offset(0, -600), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Vidéo pilote'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(0, 600), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Vidéo pilote'), findsOneWidget);
  });
}

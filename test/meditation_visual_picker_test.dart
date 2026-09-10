import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:auryel/data/relaxation_video.dart';
import 'package:auryel/widgets/relaxation_visual_picker.dart';

// ===========================================================================
// LOT 11 — « Choisir le visuel » : libellés propres, bottom sheet légère
// (aucun VideoPlayerController), option « Aléatoire », choix manuel.
// ===========================================================================

RelaxationVideo _v(
  String slug, {
  String? title,
  String category = 'calm',
  String? thumb,
}) => RelaxationVideo(
  id: 'id-$slug',
  slug: slug,
  title: title ?? 'Ambiance apaisante 01',
  videoUrl: 'https://cdn.auryel.app/$slug.mp4',
  thumbnailUrl: thumb,
  category: category,
);

void main() {
  group('relaxationVisualLabel — jamais de nom de fichier', () {
    test('titre technique "relaxation-11210466" -> "Visuel N"', () {
      expect(
        relaxationVisualLabel(_v('relaxation-11210466', title: 'relaxation-11210466'), 0),
        'Visuel 1',
      );
    });
    test('titre technique "11210466-hd_1080_1920_30fps" -> "Visuel N"', () {
      expect(
        relaxationVisualLabel(
          _v('x', title: '11210466-hd_1080_1920_30fps'),
          4,
        ),
        'Visuel 5',
      );
    });
    test('titre == slug brut -> "Visuel N"', () {
      expect(relaxationVisualLabel(_v('relax-abc', title: 'relax-abc'), 2), 'Visuel 3');
    });
    test('titre vide -> "Visuel N"', () {
      expect(relaxationVisualLabel(_v('s', title: ''), 6), 'Visuel 7');
    });
    test('titre propre conservé', () {
      expect(
        relaxationVisualLabel(_v('s', title: 'Ambiance apaisante 01'), 0),
        'Ambiance apaisante 01',
      );
      expect(
        relaxationVisualLabel(_v('s', title: 'Océan au crépuscule'), 3),
        'Océan au crépuscule',
      );
    });
  });

  Future<RelaxationVisualChoice?> openPicker(
    WidgetTester t, {
    required List<RelaxationVideo> videos,
    String? current,
  }) async {
    RelaxationVisualChoice? result;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showRelaxationVisualPicker(
                    ctx,
                    videos: videos,
                    currentSlug: current,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return result;
  }

  testWidgets('la sheet s\'ouvre, liste « Aléatoire » + N visuels, AUCUN '
      'VideoPlayerController', (t) async {
    final videos = [for (var i = 0; i < 12; i++) _v('relax-$i')];
    await openPicker(t, videos: videos);

    expect(find.text('Choisir le visuel'), findsOneWidget);
    expect(find.text('Aléatoire'), findsOneWidget);
    expect(find.text('Visuel 1'), findsNothing); // titres propres -> pas "Visuel N"
    expect(find.textContaining('Ambiance apaisante'), findsWidgets);
    // PERFORMANCE : la sheet n'initialise aucune vidéo réelle.
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('« Aléatoire » -> RelaxationVisualChoice.random()', (t) async {
    final videos = [_v('relax-0'), _v('relax-1')];
    RelaxationVisualChoice? res;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async => res = await showRelaxationVisualPicker(
                  ctx,
                  videos: videos,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Aléatoire'));
    await t.pumpAndSettle();
    expect(res, isNotNull);
    expect(res!.isRandom, isTrue);
    expect(res!.video, isNull);
  });

  testWidgets('choix manuel -> RelaxationVisualChoice.video(v)', (t) async {
    final videos = [
      _v('relax-0', title: 'Ambiance apaisante 01'),
      _v('relax-1', title: 'Ambiance apaisante 02'),
    ];
    RelaxationVisualChoice? res;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async => res = await showRelaxationVisualPicker(
                  ctx,
                  videos: videos,
                  currentSlug: 'relax-0',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ambiance apaisante 02'));
    await t.pumpAndSettle();
    expect(res, isNotNull);
    expect(res!.isRandom, isFalse);
    expect(res!.video!.slug, 'relax-1');
  });

  testWidgets('vidéo sans thumbnail_url -> placeholder propre (aucune image '
      'inventée, aucune Image.network)', (t) async {
    await openPicker(t, videos: [_v('relax-0')]);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('fermeture sans choix -> null', (t) async {
    final res = await openPicker(t, videos: [_v('relax-0')]);
    // on n'a rien tapé dans la sheet -> elle reste ouverte ; on la ferme
    Navigator.of(t.element(find.text('Aléatoire'))).pop();
    await t.pumpAndSettle();
    expect(res, isNull);
  });
}

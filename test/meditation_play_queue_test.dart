import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/meditation_play_queue.dart';
import 'package:auryel/data/relaxation_video.dart';

RelaxationVideo _video(String slug, String title) => RelaxationVideo(
  id: slug,
  slug: slug,
  title: title,
  videoUrl: 'https://cdn.example/$slug.mp4',
);

void main() {
  test('préserve le titre distinct du média courant', () {
    expect(
      meditationDisplayTitle('Auryel apaisement 009'),
      'Auryel apaisement 009',
    );
    expect(
      meditationDisplayTitle('Respirer doucement 12'),
      'Respirer doucement 12',
    );
    expect(meditationDisplayTitle('Auryel apaisement'), 'Auryel apaisement');
    final source = 'Auryel apaisement 009';
    meditationDisplayTitle(source);
    expect(source, 'Auryel apaisement 009');
  });

  test('deux médias numérotés gardent deux titres affichés distincts', () {
    final first = meditationDisplayTitle('Auryel apaisement 002');
    final second = meditationDisplayTitle('Auryel apaisement 003');
    expect(first, isNot(second));
  });

  test('queue mélange et parcourt chaque élément une fois par cycle', () {
    final queue = MeditationPlayQueue([
      _video('a', 'A'),
      _video('b', 'B'),
      _video('c', 'C'),
    ], random: Random(4));
    final firstCycle = [
      queue.current!.slug,
      queue.next()!.slug,
      queue.next()!.slug,
    ];
    expect(firstCycle.toSet(), hasLength(3));
    final nextCycle = queue.next()!;
    expect(nextCycle.slug, isNot(firstCycle.last));
    expect(queue.items, hasLength(3));
  });

  test('queue gère N=1, N=2 et précédent sans dépendre de 99', () {
    final one = MeditationPlayQueue([_video('one', 'One')], random: Random(1));
    expect(one.next()!.slug, 'one');
    expect(one.previous()!.slug, 'one');
    final two = MeditationPlayQueue([
      _video('a', 'A'),
      _video('b', 'B'),
    ], random: Random(2));
    final first = two.current!.slug;
    expect(two.next()!.slug, isNot(first));
    expect(two.previous()!.slug, first);
  });
}

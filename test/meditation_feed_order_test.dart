import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/meditation_feed_order.dart';

void main() {
  group('MeditationFeedOrder.shuffle', () {
    test('contient exactement les mêmes éléments (aucune perte, aucun ajout)', () {
      final order = MeditationFeedOrder(random: Random(1));
      final items = List.generate(12, (i) => 'm$i');
      final shuffled = order.shuffle(items);
      expect(shuffled.toSet(), items.toSet());
      expect(shuffled.length, items.length);
    });

    test('ne modifie jamais la liste reçue', () {
      final order = MeditationFeedOrder(random: Random(2));
      final items = ['a', 'b', 'c'];
      final original = List.of(items);
      order.shuffle(items);
      expect(items, original);
    });

    test('liste vide ou à 1 élément -> renvoyée telle quelle', () {
      final order = MeditationFeedOrder(random: Random(3));
      expect(order.shuffle(<String>[]), isEmpty);
      expect(order.shuffle(['solo']), ['solo']);
    });

    test(
      'sur beaucoup d\'essais, produit RÉELLEMENT plusieurs ordres différents '
      '(pas un no-op déguisé)',
      () {
        final items = List.generate(10, (i) => 'm$i');
        final seen = <String>{};
        for (var seed = 0; seed < 30; seed++) {
          seen.add(MeditationFeedOrder(random: Random(seed)).shuffle(items).join(','));
        }
        expect(seen.length, greaterThan(1));
      },
    );
  });

  group('MeditationFeedOrder — règle « pas de répétition avant que tout le '
      'monde soit passé »', () {
    test(
      'sur UN tour (shuffle), chaque élément du catalogue apparaît EXACTEMENT '
      'une fois avant qu\'aucun ne revienne',
      () {
        final order = MeditationFeedOrder(random: Random(7));
        final items = List.generate(20, (i) => 'm$i');
        final round = order.shuffle(items);
        // Un "tour" = une bijection du catalogue : aucun doublon, rien
        // manquant -> AUCUNE méditation ne peut revenir avant que toutes les
        // autres n'aient été proposées, par construction.
        expect(round.toSet().length, items.length);
      },
    );
  });

  group('MeditationFeedOrder.reshuffle — jointure entre deux tours', () {
    test('contient toujours exactement les mêmes éléments que le catalogue', () {
      final order = MeditationFeedOrder(random: Random(4));
      final items = List.generate(8, (i) => 'm$i');
      final next = order.reshuffle(items, 'm3');
      expect(next.toSet(), items.toSet());
      expect(next.length, items.length);
    });

    test(
      'le 1er élément du nouveau tour n\'est JAMAIS le dernier élément du '
      'tour précédent (anti-répétition immédiate à la jointure)',
      () {
        for (var seed = 0; seed < 200; seed++) {
          final order = MeditationFeedOrder(random: Random(seed));
          final items = List.generate(6, (i) => 'm$i');
          final next = order.reshuffle(items, 'm2');
          expect(
            next.first,
            isNot('m2'),
            reason: 'seed=$seed a produit une répétition immédiate',
          );
        }
      },
    );

    test('previousLast == null -> comportement d\'un simple shuffle', () {
      final order = MeditationFeedOrder(random: Random(5));
      final items = List.generate(5, (i) => 'm$i');
      final next = order.reshuffle(items, null);
      expect(next.toSet(), items.toSet());
    });

    test('catalogue à 1 seul élément -> reshuffle renvoie cet élément (rien '
        'd\'autre à proposer, jamais de boucle infinie)', () {
      final order = MeditationFeedOrder(random: Random(6));
      final next = order.reshuffle(['solo'], 'solo');
      expect(next, ['solo']);
    });

    test('catalogue vide -> liste vide, jamais de crash', () {
      final order = MeditationFeedOrder(random: Random(8));
      expect(order.reshuffle(<String>[], 'x'), isEmpty);
    });

    test(
      'catalogue à 2 éléments : le dernier recours déterministe (permutation) '
      'garantit malgré tout l\'absence de répétition immédiate',
      () {
        for (var seed = 0; seed < 50; seed++) {
          final order = MeditationFeedOrder(random: Random(seed));
          final next = order.reshuffle(['a', 'b'], 'a');
          expect(next.first, 'b');
        }
      },
    );
  });
}

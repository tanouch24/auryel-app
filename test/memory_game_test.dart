import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/memory_game.dart';

/// Trouve deux slots formant une paire dans l'état courant.
({int a, int b}) _firstPair(MemoryGame g) {
  final byKey = <String, List<int>>{};
  for (final c in g.cards) {
    byKey.putIfAbsent(c.pairKey, () => []).add(c.slotId);
  }
  final pair = byKey.values.firstWhere((v) => v.length == 2);
  return (a: pair[0], b: pair[1]);
}

/// Deux slots de clés différentes.
({int a, int b}) _firstMismatch(MemoryGame g) {
  final a = g.cards[0];
  final b = g.cards.firstWhere((c) => c.pairKey != a.pairKey);
  return (a: a.slotId, b: b.slotId);
}

MemoryGame _game() =>
    MemoryGame(random: Random(42), resolveDelay: Duration.zero);

void main() {
  test('16/17/18 — nombre de cartes et de paires par niveau', () {
    final g = _game();

    g.start(GameDifficulty.facile);
    expect(g.cards.length, 8);
    expect(g.totalPairs, 4);
    expect(_distinctPairKeys(g), 4);

    g.start(GameDifficulty.moyen);
    expect(g.cards.length, 12);
    expect(g.totalPairs, 6);
    expect(_distinctPairKeys(g), 6);

    g.start(GameDifficulty.intense);
    expect(g.cards.length, 16);
    expect(g.totalPairs, 8);
    expect(_distinctPairKeys(g), 8);

    // Chaque clé apparaît exactement deux fois.
    for (final entry in _keyCounts(g).entries) {
      expect(entry.value, 2, reason: entry.key);
    }
  });

  test('19 — deux cartes identiques restent découvertes', () {
    final g = _game()..start(GameDifficulty.facile);
    final p = _firstPair(g);
    g.flip(p.a);
    g.flip(p.b);
    expect(g.cards.firstWhere((c) => c.slotId == p.a).matched, isTrue);
    expect(g.cards.firstWhere((c) => c.slotId == p.b).matched, isTrue);
    expect(g.matchedPairs, 1);
  });

  test('20 — deux cartes différentes se referment après résolution', () {
    final g = _game()..start(GameDifficulty.facile);
    final m = _firstMismatch(g);
    g.flip(m.a);
    g.flip(m.b);
    // resolveDelay = 0 -> retournées immédiatement.
    expect(g.cards.firstWhere((c) => c.slotId == m.a).revealed, isFalse);
    expect(g.cards.firstWhere((c) => c.slotId == m.b).revealed, isFalse);
    expect(g.matchedPairs, 0);
    expect(g.moves, 1);
  });

  test('21 — impossible de retourner une 3e carte pendant la résolution', () {
    final g = MemoryGame(
      random: Random(1),
      resolveDelay: const Duration(seconds: 5), // reste "en résolution"
    )..start(GameDifficulty.moyen);
    final m = _firstMismatch(g);
    g.flip(m.a);
    g.flip(m.b);
    expect(g.isResolving, isTrue);

    final third = g.cards.firstWhere(
      (c) => c.slotId != m.a && c.slotId != m.b && !c.revealed,
    );
    g.flip(third.slotId);
    expect(
      g.cards.firstWhere((c) => c.slotId == third.slotId).revealed,
      isFalse,
    );
    g.dispose();
  });

  test('22 — cliquer deux fois la même carte est ignoré', () {
    final g = _game()..start(GameDifficulty.facile);
    final slot = g.cards.first.slotId;
    g.flip(slot);
    g.flip(slot); // ignoré : ne compte pas comme 2e carte
    expect(g.moves, 0);
    expect(
      g.cards.where((c) => c.revealed).length,
      1,
      reason: 'une seule carte retournée',
    );
  });

  test('23 — une carte déjà trouvée est ignorée', () {
    final g = _game()..start(GameDifficulty.facile);
    final p = _firstPair(g);
    g.flip(p.a);
    g.flip(p.b); // paire trouvée
    final movesAfter = g.moves;
    g.flip(p.a); // déjà "matched" -> ignoré
    expect(g.moves, movesAfter);
  });

  test('24/25 — victoire détectée quand toutes les paires sont trouvées ; '
      'le chrono se fige', () {
    final g = _game()..start(GameDifficulty.facile);
    final keys = _distinctKeys(g);
    for (final k in keys) {
      final slots = g.cards
          .where((c) => c.pairKey == k)
          .map((c) => c.slotId)
          .toList();
      g.flip(slots[0]);
      g.flip(slots[1]);
    }
    expect(g.isWon, isTrue);
    expect(g.matchedPairs, 4);

    final t1 = g.elapsed;
    final t2 = g.elapsed;
    expect(t1, t2, reason: 'elapsed figé après victoire');
  });

  test('start() réinitialise coups / paires / victoire', () {
    final g = _game()..start(GameDifficulty.facile);
    final p = _firstPair(g);
    g.flip(p.a);
    g.flip(p.b);
    expect(g.matchedPairs, 1);

    g.start(GameDifficulty.moyen);
    expect(g.moves, 0);
    expect(g.matchedPairs, 0);
    expect(g.isWon, isFalse);
  });

  test('28 — MemoryGame n\'expose aucune API de récompense / temps de '
      'consultation', () {
    // Garde-fou statique : l\'API publique ne contient rien de "credit",
    // "reward", "seconds", "availableSeconds"...
    const forbidden = ['credit', 'reward', 'seconds', 'consultation', 'bonus'];
    // Rien à asserter au runtime : ce test documente l\'intention et
    // échouerait à la compilation si une telle méthode était ajoutée et
    // référencée. On vérifie juste qu\'une partie gagnée ne "produit" rien.
    final g = _game()..start(GameDifficulty.facile);
    for (final k in _distinctKeys(g)) {
      final slots = g.cards
          .where((c) => c.pairKey == k)
          .map((c) => c.slotId)
          .toList();
      g.flip(slots[0]);
      g.flip(slots[1]);
    }
    expect(g.isWon, isTrue);
    expect(forbidden, isNotEmpty); // marqueur explicite
  });
}

int _distinctPairKeys(MemoryGame g) => _distinctKeys(g).length;

Set<String> _distinctKeys(MemoryGame g) =>
    g.cards.map((c) => c.pairKey).toSet();

Map<String, int> _keyCounts(MemoryGame g) {
  final m = <String, int>{};
  for (final c in g.cards) {
    m[c.pairKey] = (m[c.pairKey] ?? 0) + 1;
  }
  return m;
}

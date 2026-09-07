import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/memory_game.dart';
import 'package:auryel/data/memory_stats.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('état initial : aucune partie, aucun meilleur temps', () async {
    final s = MemoryStats();
    expect(await s.gamesCompleted(), 0);
    expect(await s.bestTime(GameDifficulty.facile), isNull);
    expect(await s.hasPlayed(GameDifficulty.moyen), isFalse);
  });

  test(
    'recordCompletion incrémente le total et garde le meilleur temps',
    () async {
      final s = MemoryStats();

      final first = await s.recordCompletion(
        GameDifficulty.facile,
        const Duration(seconds: 50),
      );
      expect(first, isTrue); // premier temps = record
      expect(await s.gamesCompleted(), 1);
      expect(
        await s.bestTime(GameDifficulty.facile),
        const Duration(seconds: 50),
      );
      expect(await s.hasPlayed(GameDifficulty.facile), isTrue);

      final worse = await s.recordCompletion(
        GameDifficulty.facile,
        const Duration(seconds: 90),
      );
      expect(worse, isFalse);
      expect(
        await s.bestTime(GameDifficulty.facile),
        const Duration(seconds: 50),
      );
      expect(await s.gamesCompleted(), 2);

      final better = await s.recordCompletion(
        GameDifficulty.facile,
        const Duration(seconds: 30),
      );
      expect(better, isTrue);
      expect(
        await s.bestTime(GameDifficulty.facile),
        const Duration(seconds: 30),
      );
    },
  );

  test('meilleur temps distinct par niveau', () async {
    final s = MemoryStats();
    await s.recordCompletion(
      GameDifficulty.facile,
      const Duration(seconds: 20),
    );
    await s.recordCompletion(
      GameDifficulty.intense,
      const Duration(seconds: 80),
    );
    expect(
      await s.bestTime(GameDifficulty.facile),
      const Duration(seconds: 20),
    );
    expect(
      await s.bestTime(GameDifficulty.intense),
      const Duration(seconds: 80),
    );
    expect(await s.bestTime(GameDifficulty.moyen), isNull);
  });

  test(
    'aucune clé de récompense / crédit / secondes de consultation',
    () async {
      final s = MemoryStats();
      await s.markStarted(GameDifficulty.facile);
      await s.recordCompletion(
        GameDifficulty.facile,
        const Duration(seconds: 12),
      );
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect(k.startsWith('auryel.memory.'), isTrue, reason: k);
        expect(
          k.contains('credit') ||
              k.contains('reward') ||
              k.contains('seconds') ||
              k.contains('consultation'),
          isFalse,
          reason: k,
        );
      }
    },
  );
}

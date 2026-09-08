import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/memory_game.dart';
import 'package:auryel/data/memory_stats.dart';
import 'package:auryel/screens/jeu_auryel_screen.dart';

Widget _host({MemoryStats? stats, DateTime Function()? clock, Key? key}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          // Anime = 0 : l\'AnimatedSwitcher des cartes bascule instantanément
          // (hit-test fiable en test).
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: JeuAuryelScreen(
            key: key,
            random: Random(7),
            stats: stats,
            resolveDelay: Duration.zero,
            enableTicker: false,
            clock: clock,
          ),
        ),
      ),
    );

dynamic _state(WidgetTester t) => t.state(find.byType(JeuAuryelScreen));

Future<void> _startLevel(WidgetTester t, String label) async {
  await t.tap(find.widgetWithText(InkWell, label).first);
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(InkWell, 'Commencer').first);
  await t.pumpAndSettle();
}

/// Joue toutes les paires dans l'ordre ; la dernière déclenche la victoire.
Future<void> _winCurrentGame(WidgetTester t, {VoidCallback? beforeLast}) async {
  final MemoryGame game = _state(t).debugGame;
  final keys = game.cards.map((c) => c.pairKey).toSet().toList();
  for (var i = 0; i < keys.length; i++) {
    final slots = game.cards
        .where((c) => c.pairKey == keys[i])
        .map((c) => c.slotId)
        .toList();
    if (i == keys.length - 1) beforeLast?.call();
    await t.tap(
      find.byKey(ValueKey('memory-card-${slots[0]}')),
      warnIfMissed: false,
    );
    await t.pump();
    await t.tap(
      find.byKey(ValueKey('memory-card-${slots[1]}')),
      warnIfMissed: false,
    );
    await t.pump();
  }
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('15 — vrai jeu : menu jouable, plus de placeholder', (t) async {
    await t.pumpWidget(_host());
    await t.pumpAndSettle();

    expect(find.byType(JeuAuryelScreen), findsOneWidget);
    expect(find.text('Le Jeu Auryel'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    expect(find.text('Facile'), findsOneWidget);
    expect(find.text('Moyen'), findsOneWidget);
    expect(find.text('Intense'), findsOneWidget);
    // Aucun vestige de placeholder.
    expect(find.textContaining('prochaine étape'), findsNothing);
    expect(find.textContaining('Bientôt'), findsNothing);
  });

  Finder tiles() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey &&
        (w.key as ValueKey).value.toString().startsWith('memory-card-'),
  );

  for (final (label, count) in const [
    ('Facile', 8),
    ('Moyen', 12),
    ('Intense', 16),
  ]) {
    testWidgets('16/17/18 — niveau $label pose $count cartes / '
        '${count ~/ 2} paires', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 1400); // tout le plateau rendu
      addTearDown(t.view.reset);

      await t.pumpWidget(_host());
      await t.pumpAndSettle();
      await _startLevel(t, label);

      final MemoryGame g = _state(t).debugGame;
      expect(g.cards.length, count);
      expect(g.totalPairs, count ~/ 2);
      // Chaque paire = exactement 2 cartes.
      final counts = <String, int>{};
      for (final c in g.cards) {
        counts[c.pairKey] = (counts[c.pairKey] ?? 0) + 1;
      }
      expect(counts.length, count ~/ 2);
      expect(counts.values.every((v) => v == 2), isTrue);
      // Rendu : les tuiles apparaissent.
      expect(tiles(), findsNWidgets(count));
    });
  }

  testWidgets('24/27 — victoire affichée puis « Rejouer » relance une partie', (
    t,
  ) async {
    await t.pumpWidget(_host());
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');

    await _winCurrentGame(t);
    expect(find.text('Toutes les paires trouvées'), findsOneWidget);
    expect(find.text('Rejouer'), findsOneWidget);
    expect(find.text('Changer de niveau'), findsOneWidget);

    await t.tap(find.text('Rejouer'));
    await t.pumpAndSettle();
    expect(find.text('Toutes les paires trouvées'), findsNothing);
    final MemoryGame g = _state(t).debugGame;
    expect(g.isWon, isFalse);
    expect(g.moves, 0);
  });

  testWidgets('26 — meilleur temps enregistré localement', (t) async {
    final stats = MemoryStats();
    var now = DateTime(2026, 1, 1, 10, 0, 0);
    await t.pumpWidget(_host(stats: stats, clock: () => now));
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');

    await _winCurrentGame(
      t,
      beforeLast: () => now = DateTime(2026, 1, 1, 10, 0, 42),
    );

    expect(await stats.gamesCompleted(), 1);
    final best = await stats.bestTime(GameDifficulty.facile);
    expect(best, const Duration(seconds: 42));
    expect(find.textContaining('meilleur temps'), findsOneWidget);
  });

  testWidgets('28/29 — une victoire ne crédite AUCUN temps et ne touche PAS '
      'aux 4 missions du jour', (t) async {
    await t.pumpWidget(_host());
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');
    await _winCurrentGame(t);

    final tracker = DailyMissionTracker();
    expect(await tracker.isDone(DailyMissionTracker.tirage), isFalse);
    expect(await tracker.isDone(DailyMissionTracker.consultation), isFalse);
    expect(await tracker.isDone(DailyMissionTracker.moment), isFalse);

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    expect(
      keys.any(
        (k) =>
            k.contains('available') ||
            k.contains('seconds') ||
            k.contains('credit') ||
            k.contains('reward'),
      ),
      isFalse,
      reason: 'aucune clé de récompense / crédit écrite par le jeu',
    );
  });

  for (final w in const [360.0, 384.0, 430.0]) {
    testWidgets(
      '30/31/32 — 16 cartes jouables sans overflow à ${w.toInt()} dp',
      (t) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = Size(w, 820);
        addTearDown(t.view.reset);

        await t.pumpWidget(_host());
        await t.pumpAndSettle();
        await _startLevel(t, 'Intense');

        expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
        // La grille est présente et scrollable (plateau complet accessible).
        expect(find.byType(GridView), findsOneWidget);
        expect(_state(t).debugGame.cards.length, 16);
        expect(tiles(), findsWidgets);

        // On peut faire défiler jusqu'à la dernière carte sans exception.
        await t.drag(find.byType(GridView), const Offset(0, -400));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'scroll ${w.toInt()} dp');
      },
    );
  }
}

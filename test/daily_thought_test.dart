import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/daily_thought.dart';

// ===========================================================================
// LOT PENSÉE — source locale des 100 pensées + rotation quotidienne.
// Lit `assets/pensees/pensees_100_site.json` via rootBundle (aucune API).
// ===========================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = DailyThoughtRepository();

  test(
    'A. charge exactement 100 entrées, ids 1..100, champs non vides',
    () async {
      final all = await repo.load();
      expect(all.length, 100);
      expect(all.map((e) => e.id).toList(), List.generate(100, (i) => i + 1));
      expect(all.every((e) => e.phrase.trim().isNotEmpty), isTrue);
      expect(all.every((e) => e.interpretation.trim().isNotEmpty), isTrue);
      expect(
        all.every(
          (e) =>
              e.imageAsset.startsWith('assets/pensees/publications/') &&
              e.imageAsset.endsWith('.webp'),
        ),
        isTrue,
      );
      expect(await repo.count(), 100);
    },
  );

  test(
    'B. sélection par date : 04/09 -> id 1 ; milieu ; 12/12 -> id 100',
    () async {
      expect((await repo.thoughtFor(DateTime(2026, 9, 4, 7))).id, 1);
      expect((await repo.thoughtFor(DateTime(2026, 10, 23, 23, 59))).id, 50);
      expect((await repo.thoughtFor(DateTime(2026, 12, 12))).id, 100);
    },
  );

  test(
    'C. rotation à minuit local : l\'heure de la journée n\'influe pas',
    () async {
      final a = await repo.thoughtFor(DateTime(2026, 10, 1, 0, 1));
      final b = await repo.thoughtFor(DateTime(2026, 10, 1, 23, 59));
      expect(a.id, b.id);
    },
  );

  test(
    'D. fallback APRÈS le 12/12/2026 : déterministe, cyclique, jamais nul',
    () async {
      final d13 = await repo.thoughtFor(
        DateTime(2026, 12, 13),
      ); // 100 j -> idx 0
      expect(d13.id, 1);
      expect((await repo.thoughtFor(DateTime(2026, 12, 14))).id, 2);
      // +100 jours après le 13/12 -> même pensée (cycle de 100)
      expect((await repo.thoughtFor(DateTime(2027, 3, 23))).id, d13.id);
    },
  );

  test('E. fallback AVANT le 04/09/2026 : déterministe, jamais nul', () async {
    final t = await repo.thoughtFor(DateTime(2026, 9, 1));
    expect(t.id, inInclusiveRange(1, 100));
  });

  test(
    'F. splitAccent : la fin dorée est un SUFFIXE EXACT (texte intact)',
    () async {
      for (final e in await repo.load()) {
        final s = e.splitAccent();
        final reconstructed = s.lead.isEmpty
            ? s.accent
            : '${s.lead} ${s.accent}';
        expect(reconstructed, e.phrase, reason: 'phrase altérée id ${e.id}');
        expect(s.accent.trim().isNotEmpty, isTrue);
      }
    },
  );
}

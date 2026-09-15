import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/wake_meditation_selector.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'la méditation du jour reste stable et le snooze réutilise la séance',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final selector = WakeMeditationSelection(prefs: prefs);
      final repository = ContentRepository(prefs: prefs);
      final first = await selector.pick(repository, DateTime(2026, 9, 15));
      final second = await selector.pick(
        repository,
        DateTime(2026, 9, 15, 23, 59),
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second!.item.id, first!.item.id);
    },
  );

  test('la sélection change de jour quand le catalogue le permet', () async {
    final prefs = await SharedPreferences.getInstance();
    final selector = WakeMeditationSelection(prefs: prefs);
    final first = await selector.pick(
      ContentRepository(prefs: prefs),
      DateTime(2026, 9, 15),
    );
    final next = await selector.pick(
      ContentRepository(prefs: prefs),
      DateTime(2026, 9, 16),
    );

    expect(first, isNotNull);
    expect(next, isNotNull);
    expect(next!.item.id, isNot(first!.item.id));
  });
}

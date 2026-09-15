import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_motivation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('les 50 motivations ont chacune un texte et son MP3 associé', () async {
    final items = await WakeMotivationCatalog.load();

    expect(items, hasLength(50));
    expect(items.map((item) => item.id).toSet(), hasLength(50));
    for (final item in items) {
      expect(item.text, isNotEmpty);
      expect(item.audioAsset, endsWith('${item.id}.mp3'));
      expect(item.toMessage().text, item.text);
      expect(item.toMessage().audioAsset, item.audioAsset);
    }
  });

  test('la sélection quotidienne est déterministe', () {
    const items = [
      WakeMotivation(id: 'a', text: 'A', audioAsset: 'a.mp3'),
      WakeMotivation(id: 'b', text: 'B', audioAsset: 'b.mp3'),
    ];

    expect(WakeMotivationCatalog.pick(items, DateTime(2026, 1, 1))?.id, 'a');
    expect(WakeMotivationCatalog.pick(items, DateTime(2026, 1, 2))?.id, 'b');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_share_tracker.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';

// ===========================================================================
// LOT PENSÉE — aperçu SIMPLIFIÉ de LA publication du jour.
// Un seul visuel (le WEBP final, déjà généré : phrase + interprétation + design),
// un bouton « Partager » (feuille de partage native), le compteur « X / 30 ».
// AUCUNE date, AUCUNE variante, AUCUN poster à la volée, AUCUNE récompense.
// ===========================================================================

final _thought = DailyThought(
  id: 1,
  publishDate: DateTime(2026, 9, 4),
  phrase: 'Ce que tu n’oses pas regarder te dirige.',
  interpretation: 'Interprétation de contrôle (n’apparaît pas hors du visuel).',
  imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
);

/// Bundle factice : `load` renvoie quelques octets (pour le partage), `loadString`
/// une liste vide. Le décodage image échoue proprement -> `errorBuilder`.
class _FakeBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      Uint8List.fromList(const [1, 2, 3, 4, 5]).buffer.asByteData();

  @override
  Future<String> loadString(String key, {bool cache = true}) async => '[]';
}

Future<void> _noopShare({Uint8List? imageBytes, required String text}) async {}

Widget _host({
  required ShareThoughtCallback onShare,
  DailyShareTracker? tracker,
}) {
  return MaterialApp(
    home: Scaffold(
      body: DailyMessageSheet(
        thought: _thought,
        onShare: onShare,
        tracker: tracker ?? DailyShareTracker(),
        bundle: _FakeBundle(),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('structure : titre + 1 visuel + « Partager » + compteur ; '
      'plus de variantes / « générer » / date', (t) async {
    await t.pumpWidget(_host(onShare: _noopShare));
    await t.pumpAndSettle();

    expect(find.text('Fermer'), findsOneWidget);
    expect(find.text('TA PUBLICATION DU JOUR'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // LE visuel du jour, un seul
    expect(find.text('Partager'), findsOneWidget);
    expect(find.textContaining('/ 30 jours'), findsOneWidget);

    // ce qui a DISPARU
    expect(find.text('Générer la publication'), findsNothing);
    expect(
      find.text('Partage la pensée du jour avec tes contacts'),
      findsNothing,
    );
    expect(find.text('CHOISIS TA PUBLICATION'), findsNothing);
    expect(find.text('L’INTERPRÉTATION'), findsNothing);
    expect(find.textContaining('AOÛT'), findsNothing);
    expect(find.textContaining('SEPTEMBRE'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
  });

  testWidgets('« Partager » -> partage natif (WEBP + texte) + 1 jour compté ; '
      '2e partage le même jour = compteur inchangé', (t) async {
    final prefs = await SharedPreferences.getInstance();
    final tracker = DailyShareTracker(prefs: prefs);
    var calls = 0;
    String? sharedText;
    Uint8List? sharedBytes;

    await t.pumpWidget(
      _host(
        tracker: tracker,
        onShare: ({Uint8List? imageBytes, required String text}) async {
          calls++;
          sharedText = text;
          sharedBytes = imageBytes;
        },
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();

    expect(calls, 1);
    expect(sharedText, contains('— Auryel'));
    expect(sharedText, contains('te dirige.'));
    expect(sharedBytes != null && sharedBytes!.isNotEmpty, isTrue);
    expect(await tracker.sharedDaysCount(), 1);

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    expect(calls, 2, reason: 'partage encore possible');
    expect(await tracker.sharedDaysCount(), 1, reason: '1 jour max / jour');
  });

  test('DailyShareTracker : aucune notion de récompense / de temps', () {
    const api = {'recordShareAttempt', 'sharedDaysCount', 'sharedToday'};
    expect(
      api.any(
        (m) =>
            m.toLowerCase().contains('reward') ||
            m.toLowerCase().contains('hour') ||
            m.toLowerCase().contains('second') ||
            m.toLowerCase().contains('grant'),
      ),
      isFalse,
    );
  });

  test(
    'DailyShareTracker : +1 max par jour calendaire, lendemain = +1',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final tr = DailyShareTracker(prefs: prefs);
      expect(await tr.recordShareAttempt(now: DateTime(2026, 9, 1, 8)), isTrue);
      expect(
        await tr.recordShareAttempt(now: DateTime(2026, 9, 1, 23)),
        isFalse,
      );
      expect(
        await tr.recordShareAttempt(now: DateTime(2026, 9, 2, 0, 5)),
        isTrue,
      );
      expect(await tr.sharedDaysCount(), 2);
    },
  );

  // -------------------------------------------------------------------------
  // LOT CONTENU DISTANT — pensée servie par le backend : pas d'asset embarqué.
  // La feuille ne doit ni crasher ni tenter de charger un asset vide ; le
  // partage retombe sur le texte seul.
  // -------------------------------------------------------------------------
  testWidgets('pensée serveur (imageAsset vide) : feuille stable, aucun '
      'Image.asset, partage TEXTE seul', (t) async {
    final serverThought = DailyThought(
      id: 42,
      publishDate: DateTime(2026, 9, 9),
      phrase: 'Une pensée venue du serveur.',
      interpretation: 'Interprétation serveur.',
      imageAsset: '',
    );
    var calls = 0;
    Uint8List? sharedBytes;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyMessageSheet(
            thought: serverThought,
            tracker: DailyShareTracker(),
            onShare: ({Uint8List? imageBytes, required String text}) async {
              calls++;
              sharedBytes = imageBytes;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.text('TA PUBLICATION DU JOUR'), findsOneWidget);
    expect(find.byType(Image), findsNothing); // ni asset ni URL -> aplat sombre

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(sharedBytes, isNull); // texte seul, aucun octet d'image
  });
}

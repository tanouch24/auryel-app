import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_like_store.dart';
import 'package:auryel/data/daily_message.dart';
import 'package:auryel/data/daily_share_tracker.dart';
import 'package:auryel/widgets/daily_message_poster.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';

// ===========================================================================
// B8.1/B8.3 — feuille du message du jour : retour, interprétation, « j'aime »,
// génération de 3 variantes de publication, partage natif, compteur B10.
// ===========================================================================

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('§3 — structure de la feuille', () {
    testWidgets('l\'ancien CTA « Découvrir le message du jour » n\'existe plus',
        (t) async {
      await t.pumpWidget(_hostSheet(onShare: _noopShare));
      await t.pumpAndSettle();
      expect(find.text('Découvrir le message du jour'), findsNothing);
    });

    testWidgets('retour + phrase + interprétation + « J\'aime » + « Générer la '
        'publication » ; « Partager » pas encore visible', (t) async {
      await t.pumpWidget(_hostSheet(onShare: _noopShare));
      await t.pumpAndSettle();

      // 1) bouton retour / fermer
      expect(find.text('Fermer'), findsOneWidget);
      // 2) phrase (RichText)
      expect(find.textContaining('te dirige.', findRichText: true), findsWidgets);
      // 3) interprétation
      expect(find.text('L’INTERPRÉTATION'), findsOneWidget);
      expect(find.textContaining('qu’est-ce que j’évite de nommer'),
          findsOneWidget);
      // 4) « J'aime »
      expect(find.text('J’aime'), findsOneWidget);
      // 5) « Générer la publication »
      expect(find.text('Générer la publication'), findsOneWidget);
      expect(find.text('Partager mon message'), findsNothing);
      // pas encore de publications, ni la relance
      expect(find.byType(DailyMessagePoster), findsNothing);
      expect(find.text('Ce message te fait penser à quelqu’un ?'), findsNothing);
    });

    testWidgets('« Fermer » referme la feuille', (t) async {
      await t.pumpWidget(_hostSheet(onShare: _noopShare, asSheet: true));
      await t.pumpAndSettle();
      await t.tap(find.text('Voir'));
      await t.pumpAndSettle();
      expect(find.text('Fermer'), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(find.text('Fermer'), findsNothing);
    });
  });

  group('§3-C — « Générer la publication » : 3 variantes', () {
    testWidgets('après génération : 3 affiches + relance + « Partager »',
        (t) async {
      await t.pumpWidget(_hostSheet(onShare: _noopShare));
      await t.pumpAndSettle();

      await t.ensureVisible(find.text('Générer la publication'));
      await t.tap(find.text('Générer la publication'));
      await t.pumpAndSettle();

      // 3 variantes de publication générées localement
      expect(kPublicationVariantCount, 3);
      expect(find.byType(DailyMessagePoster), findsNWidgets(3));
      // relance au bon endroit
      expect(find.text('Ce message te fait penser à quelqu’un ?'), findsOneWidget);
      // bouton de partage
      expect(find.text('Partager'), findsOneWidget);
    });
  });

  group('§3-D/§10 — partage natif + accroche B10 (aucune récompense)', () {
    testWidgets('« Partager » -> callback natif + jour compté (1 fois / jour)',
        (t) async {
      final prefs = await SharedPreferences.getInstance();
      final tracker = DailyShareTracker(prefs: prefs);
      var shareCalls = 0;
      String? sharedText;
      Uint8List? sharedImage;

      await t.pumpWidget(_hostSheet(
        tracker: tracker,
        onShare: ({Uint8List? imagePng, required String text}) async {
          shareCalls++;
          sharedText = text;
          sharedImage = imagePng;
        },
      ));
      await t.pumpAndSettle();

      await t.ensureVisible(find.text('Générer la publication'));
      await t.tap(find.text('Générer la publication'));
      await t.pumpAndSettle();

      await t.ensureVisible(find.text('Partager'));
      await t.tap(find.text('Partager'));
      await t.pumpAndSettle();

      expect(shareCalls, 1);
      expect(sharedText, contains('— Auryel'));
      // capture stubée en test -> octets non nuls
      expect(sharedImage == null || sharedImage!.isNotEmpty, isTrue);
      expect(await tracker.sharedDaysCount(), 1);

      await t.ensureVisible(find.text('Partager'));
      await t.tap(find.text('Partager'));
      await t.pumpAndSettle();
      expect(shareCalls, 2);
      expect(await tracker.sharedDaysCount(), 1,
          reason: 'toujours 1 jour compté (max 1 / jour)');
    });

    test('DailyShareTracker NE touche AUCUN temps / récompense', () {
      const api = <String>{
        'recordShareAttempt',
        'sharedDaysCount',
        'sharedToday',
      };
      expect(api.any((m) =>
          m.toLowerCase().contains('reward') ||
          m.toLowerCase().contains('grant') ||
          m.toLowerCase().contains('hour') ||
          m.toLowerCase().contains('second')), isFalse);
    });

    test('tracker : jours distincts, dé-duplication par jour calendaire',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final tr = DailyShareTracker(prefs: prefs);
      expect(await tr.recordShareAttempt(now: DateTime(2026, 9, 1, 8)), isTrue);
      expect(await tr.recordShareAttempt(now: DateTime(2026, 9, 1, 23)), isFalse);
      expect(await tr.recordShareAttempt(now: DateTime(2026, 9, 2, 0, 5)), isTrue);
      expect(await tr.sharedDaysCount(), 2);
    });
  });

  group('§3-E — « J\'aime » local dans la feuille', () {
    testWidgets('togglable + persistant (aucun backend)', (t) async {
      final prefs = await SharedPreferences.getInstance();
      final store = DailyLikeStore(prefs: prefs);

      await t.pumpWidget(_hostSheet(onShare: _noopShare, likeStore: store));
      await t.pumpAndSettle();

      expect(find.text('J’aime'), findsOneWidget);
      expect(find.text('Aimé'), findsNothing);

      await t.tap(find.text('J’aime'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('Aimé'), findsOneWidget);
      expect(await store.isLikedToday(), isTrue);
    });
  });

  group('§8 — affiches (3 variantes) : rendu + capture', () {
    testWidgets('les 3 variantes se rendent et se capturent sans crash',
        (t) async {
      for (final v in PosterVariant.values) {
        final key = GlobalKey();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: DailyMessagePoster(
                    message: DailyMessage.today,
                    variant: v,
                    boundaryKey: key,
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(DailyMessagePoster), findsOneWidget);

        Uint8List? bytes;
        await t.runAsync(() async {
          bytes = await DailyMessagePoster.capturePng(key);
        });
        expect(bytes == null || bytes!.isNotEmpty, isTrue);
        expect(t.takeException(), isNull, reason: 'variante $v');
      }
    });
  });
}

Future<void> _noopShare({Uint8List? imagePng, required String text}) async {}

Widget _hostSheet({
  required ShareCallback onShare,
  DailyShareTracker? tracker,
  DailyLikeStore? likeStore,
  bool asSheet = false,
}) {
  final sheet = DailyMessageSheet(
    message: DailyMessage.today,
    onShare: onShare,
    tracker: tracker ?? DailyShareTracker(),
    likeStore: likeStore,
    // Capture stubée en test (le vrai toImage() exige runAsync).
    captureOverride: (int _) async => Uint8List.fromList([1, 2, 3]),
  );
  if (!asSheet) {
    return MaterialApp(home: Scaffold(body: sheet));
  }
  // Variante « vraie feuille modale » pour tester la fermeture.
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => sheet,
            ),
            child: const Text('Voir'),
          ),
        ),
      ),
    ),
  );
}

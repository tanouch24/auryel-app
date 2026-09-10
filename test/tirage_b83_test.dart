import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/daily_like_store.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/tarot_card_back.dart';

// ===========================================================================
// B8.4 §11-19 — écran Tirage SIMPLIFIÉ : UNE seule représentation des cartes
// choisies (dos posé sur l'emplacement du tapis vide), vrai asset, aucune
// duplication, retournement sur place.
// ===========================================================================

final _cardFaceImages = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.contains('images/tarot/'),
);

final _cardBackImages = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == 'assets/images/tarot_card_back.png',
);

Widget _wrap() {
  final client = ApiClient(
    httpClient: MockClient((_) async => http.Response('{}', 404)),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u',
      selectedAdvisor: 'Maïa',
      firstName: 'N',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'x',
      portraitFeedback: 'y',
      onboardingCompleted: true,
    ),
  );
  return AuthScope(
    controller: auth,
    child: AuryelStateScope(
      state: state,
      child: const MaterialApp(home: TirageScreen()),
    ),
  );
}

Future<void> _tap(WidgetTester t, int backIndex) async {
  await t.tap(find.byKey(ValueKey('tarot-back-$backIndex')));
  await t.pumpAndSettle();
}

int _tapisBacks(WidgetTester t) {
  // dos affichés SUR le tapis = total dos - 22 dos de l'éventail.
  return _cardBackImages.evaluate().length - 22;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('§2-B/§C — plus AUCUN dessin programmatique du DOS DE CARTE '
      '(CustomPainter), le dos est un vrai asset', () {
    final src = File('lib/widgets/tarot_card_back.dart').readAsStringSync();
    expect(src.contains("assets/images/tarot_card_back.png"), isTrue);
    // Le DOS de carte / le TIRAGE ne dessinent aucune rosace ni painter :
    // on scanne les fichiers tarot / tirage (le reste de l'app peut, lui,
    // légitimement peindre — ex. la carte de progression du parcours).
    const scanned = [
      'lib/widgets/tarot_card_back.dart',
      'lib/widgets/tarot_fan.dart',
      'lib/screens/tirage_screen.dart',
      'lib/screens/tirage_jeu_screen.dart',
      'lib/screens/my_cards_screen.dart',
    ];
    for (final path in scanned) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final code = f.readAsStringSync();
      expect(code.contains('extends CustomPainter'), isFalse, reason: path);
      expect(code.contains('CustomPaint('), isFalse, reason: path);
      expect(code.contains('_CompassRosePainter'), isFalse, reason: path);
    }
  });

  testWidgets('§A/§B/§D — tapis vide + vrai dos + 0 carte dans les slots',
      (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();

    // tapis VIDE en fond
    expect(
      find.byWidgetPredicate((w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName ==
              'assets/images/tarot_table_blank.png'),
      findsOneWidget,
    );
    // vrai asset de dos utilisé (constante widget)
    expect(TarotCardBack.asset, 'assets/images/tarot_card_back.png');
    // éventail = 22 dos ; 0 posé sur le tapis
    expect(_cardBackImages, findsNWidgets(22));
    expect(_tapisBacks(t), 0);
    // aucune face avant révélation
    expect(_cardFaceImages, findsNothing);
  });

  testWidgets('§E/§F/§G — 1 puis 2 puis 3 cartes posées sur le tapis', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();

    await _tap(t, 3);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(_tapisBacks(t), 1);

    await _tap(t, 10);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(_tapisBacks(t), 2);

    await _tap(t, 17);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(_tapisBacks(t), 3);

    // §H/§I — aucun récap, aucune ligne "Tes 3 cartes sont choisies"
    expect(find.text('Tes 3 cartes sont choisies'), findsNothing);
    // §L — bouton Révéler visible à 3/3
    expect(find.text('Révéler mon tirage'), findsOneWidget);
    // toujours aucune face avant révélation
    expect(_cardFaceImages, findsNothing);
  });

  testWidgets('§M — like tirage présent et togglable (local, bucket tarot)',
      (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();

    final outline = find.byWidgetPredicate((w) =>
        w is PhosphorIcon && w.icon == PhosphorIconsRegular.heart);
    final filled = find.byWidgetPredicate(
        (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.heart);

    expect(outline, findsOneWidget);
    expect(filled, findsNothing);

    await t.tap(outline);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(filled, findsOneWidget);
    expect(await DailyLikeStore(bucket: 'tarot').isLikedToday(), isTrue);
    expect(await DailyLikeStore().isLikedToday(), isFalse);
  });
}

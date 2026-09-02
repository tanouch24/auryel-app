import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_like_store.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';

// ===========================================================================
// B8.2 — hiérarchie de l'accueil : zone message du jour compacte, plus de
// bouton « Partager » sur l'accueil, cœur « j'aime » discret, conseillers
// remontés au-dessus de la ligne de flottaison.
// ===========================================================================

AuryelState _state() => AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u',
        selectedAdvisor: 'Séléna',
        firstName: 'N',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    );

Widget _host() => AuryelStateScope(
      state: _state(),
      child: const MaterialApp(home: HomeScreen()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('B. plus de bouton « Partager » sur l\'accueil', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Partager'), findsNothing);
    expect(find.text('Partager mon message'), findsNothing);
  });

  testWidgets('C. CTA « Voir l\'interprétation » présent', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Voir l’interprétation'), findsOneWidget);
  });

  testWidgets('C bis. la phrase du jour est affichée AVANT le CTA', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    final phrase = find.byWidgetPredicate((w) =>
        w is RichText && w.text.toPlainText().contains('te dirige.'));
    expect(phrase, findsWidgets);
    // B8.3 §2-B — « Voir l'interprétation » est JUSTE EN DESSOUS de la phrase.
    final phraseDy = t.getTopLeft(phrase.first).dy;
    final ctaDy = t.getTopLeft(find.text('Voir l’interprétation')).dy;
    expect(ctaDy, greaterThan(phraseDy));
  });

  testWidgets('B8.4 §5/§P — plus de hint vertical « Découvrir les conseillers »',
      (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Découvrir les conseillers'), findsNothing);
  });

  testWidgets('D. cœur « j\'aime » discret présent, togglable et persistant',
      (t) async {
    final heartOutline = find.byWidgetPredicate(
        (w) => w is PhosphorIcon && w.icon == PhosphorIconsRegular.heart);
    final heartFilled = find.byWidgetPredicate(
        (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.heart);

    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));

    // présent, non aimé au départ (cœur contour)
    expect(heartOutline, findsOneWidget);
    expect(heartFilled, findsNothing);

    await t.tap(heartOutline);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    // l'état a basculé (cœur plein)…
    expect(heartFilled, findsOneWidget);
    // …et il est persisté localement (aucun backend)
    expect(await DailyLikeStore().isLikedToday(), isTrue);
  });

  testWidgets('A. « Découvre nos conseillers » remonté (hiérarchie compacte)',
      (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(384, 850); // Galaxy A07 ~ 384 dp
    addTearDown(t.view.reset);

    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));

    final titre = find.text('Découvre nos conseillers');
    expect(titre, findsOneWidget);
    final dy = t.getTopLeft(titre).dy;
    // Avant B8.2 le titre démarrait > 800 dp (hors écran A07). Objectif :
    // nettement remonté — on exige < 720 dp.
    expect(dy, lessThan(720),
        reason: 'titre conseillers à ${dy.toStringAsFixed(0)} dp, attendu < 720');
  });

  testWidgets('H. aucun overflow accueil (384 dp, avec cœur + zone compacte)',
      (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(384, 850);
    addTearDown(t.view.reset);
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_like_store.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';

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

// Pensée du jour injectée (1 entrée) : `thoughtFor` la renvoie toujours,
// quelle que soit l'horloge -> tests déterministes, aucun accès aux assets.
DailyThoughtRepository _repo() => DailyThoughtRepository(
  seed: [
    DailyThought(
      id: 1,
      publishDate: DateTime(2026, 9, 4),
      phrase: 'Ce que tu n’oses pas regarder te dirige.',
      interpretation: 'x',
      imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
    ),
  ],
);

Widget _host() => AuryelStateScope(
  state: _state(),
  child: MaterialApp(home: HomeScreen(thoughtRepository: _repo())),
);

// Même Accueil mais « réduire les animations » activé : le repère « Cliquez
// ici » doit se rendre STATIQUE (aucune animation qui empêcherait pumpAndSettle).
Widget _hostNoAnim() => AuryelStateScope(
  state: _state(),
  child: MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: HomeScreen(thoughtRepository: _repo()),
      ),
    ),
  ),
);

// Nouveau bénéfice du bloc partage (bouton dédié « Partager maintenant »).
const _shareCta = 'gagne 1 h de consultation';
const _shareBtn = 'Partager maintenant';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('B. plus de bouton « Partager » sur l\'accueil', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Partager'), findsNothing);
    expect(find.text('Partager mon message'), findsNothing);
  });

  testWidgets('C. ancien CTA « voir l\'interprétation » supprimé ; nouveau CTA '
      'partage/récompense + compteur « X / 30 » présents', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Clique ici pour voir l’interprétation'), findsNothing);
    expect(find.textContaining(_shareCta), findsOneWidget);
    expect(find.textContaining('/ 30 jours'), findsOneWidget);
  });

  testWidgets('C quater. bénéfice + VRAI bouton « Partager maintenant » ; '
      'plus d\'encadré ambigu ni de « Cliquez ici »', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(
      find.text('Partage cette pensée et gagne 1 h de consultation'),
      findsOneWidget,
    );
    expect(find.text(_shareBtn), findsOneWidget);
    expect(find.text('Cliquez ici'), findsNothing);
    expect(
      find.textContaining('gagne 1 h de communication offerte'),
      findsNothing,
    );
  });

  testWidgets('C ter. tap sur le CTA ouvre l\'aperçu de LA publication du jour '
      '(1 visuel, pas de « générer », pas de date)', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.text(_shareBtn));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.byType(DailyMessageSheet), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    expect(find.text('Générer la publication'), findsNothing);
    expect(
      find.text('Partage la pensée du jour avec tes contacts'),
      findsNothing,
    );
    expect(find.textContaining('AOÛT'), findsNothing);
  });

  testWidgets('C bis. la phrase du jour est affichée AVANT le CTA', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    final phrase = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('te dirige.'),
    );
    expect(phrase, findsWidgets);
    final phraseDy = t.getTopLeft(phrase.first).dy;
    final ctaDy = t.getTopLeft(find.textContaining(_shareCta)).dy;
    expect(ctaDy, greaterThan(phraseDy));
  });

  testWidgets('CTA partage : bénéfice, puis VRAI bouton, puis compteur '
      '(ordre vertical) ; « Cliquez ici » supprimé', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));

    expect(find.text('Cliquez ici'), findsNothing);
    expect(find.textContaining(_shareCta), findsOneWidget); // bénéfice
    expect(find.text(_shareBtn), findsOneWidget); // vrai bouton
    expect(find.textContaining('/ 30 jours'), findsOneWidget); // compteur

    final benefitDy = t.getTopLeft(find.textContaining(_shareCta)).dy;
    final btnDy = t.getTopLeft(find.text(_shareBtn)).dy;
    final counterDy = t.getTopLeft(find.textContaining('/ 30 jours')).dy;
    expect(btnDy, greaterThan(benefitDy), reason: 'bouton sous le bénéfice');
    expect(counterDy, greaterThan(btnDy), reason: 'compteur sous le bouton');
  });

  testWidgets('tap « Partager maintenant » -> aperçu de la publication', (
    t,
  ) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.text(_shareBtn));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.byType(DailyMessageSheet), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
  });

  testWidgets('GUIDE. animation désactivable (MediaQuery.disableAnimations) : '
      'rendu statique, pumpAndSettle aboutit, guide toujours présent', (
    t,
  ) async {
    await t.pumpWidget(_hostNoAnim());
    await t.pumpAndSettle(); // ne DOIT pas expirer : aucune animation en cours
    expect(find.text('Cliquez ici'), findsNothing);
    expect(find.text(_shareBtn), findsOneWidget);
    expect(find.textContaining(_shareCta), findsOneWidget);
    expect(find.textContaining('/ 30 jours'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('GUIDE. aucun overflow avec le repère à ~384 dp', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(384, 850);
    addTearDown(t.view.reset);
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text(_shareBtn), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'B8.4 §5/§P — plus de hint vertical « Découvrir les conseillers »',
    (t) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Découvrir les conseillers'), findsNothing);
    },
  );

  testWidgets('D. cœur « j\'aime » discret présent, togglable et persistant', (
    t,
  ) async {
    final heartOutline = find.byWidgetPredicate(
      (w) => w is PhosphorIcon && w.icon == PhosphorIconsRegular.heart,
    );
    final heartFilled = find.byWidgetPredicate(
      (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.heart,
    );

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

  testWidgets('A. les conseillers ne sont plus présentés sur l\'Accueil '
      '(carrousel + « Changer de conseiller » retirés)', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Découvre nos conseillers'), findsNothing);
    expect(find.text('Changer de conseiller'), findsNothing);
    expect(find.text('Découvrir les conseillers'), findsNothing);
  });

  testWidgets('H. aucun overflow accueil (384 dp, avec cœur + zone compacte)', (
    t,
  ) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(384, 850);
    addTearDown(t.view.reset);
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('DATE — aucune date affichée sur l\'Accueil ; « ESPACE PRIVÉ » '
      'conservé', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));

    expect(find.textContaining('25 AOÛT'), findsNothing);
    expect(find.textContaining('AOÛT'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').contains('·') &&
            (w.data ?? '').contains('ESPACE PRIVÉ'),
      ),
      findsNothing,
    );
    expect(find.text('ESPACE PRIVÉ'), findsOneWidget);
  });

  testWidgets('DATE — l\'aperçu de la publication n\'affiche aucune date', (
    t,
  ) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text(_shareBtn));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.byType(DailyMessageSheet), findsOneWidget);
    expect(find.textContaining('AOÛT'), findsNothing);
    expect(find.textContaining('SEPTEMBRE'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
  });
}

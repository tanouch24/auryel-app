import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/experience_intro_store.dart';
import 'package:auryel/data/intro_video_store.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/auryel_experience_screen.dart';
import 'package:auryel/screens/onboarding/wake_onboarding_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// « Bienvenue dans Auryel » — présentation premium après création de compte.
// ===========================================================================

const _slogan =
    'Auryel réinvente la voyance et la méditation pour en faire une véritable '
    'expérience quotidienne, personnelle et immersive.';

const _blockTitles = [
  'Ton conseiller',
  'Ta pensée du jour',
  'Tes tirages',
  'Ton moment',
  'Partage & récompenses',
  'Le Jeu Auryel',
  'Boutique Auryel',
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // L'Accueil (via MainNavShell après « Découvrir Auryel ») a besoin de
  // l'état onboarding : on l'enveloppe pour que la navigation aboutisse.
  // `animations` = false par défaut (déterministe + couvre « réduire les
  // animations ») ; un test dédié les active avec pumpAndSettle.
  Widget shell(Widget child, {bool animations = false}) => AuryelStateScope(
    state: AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u',
        selectedAdvisor: 'Séléna',
        firstName: 'Nina',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    ),
    // MediaQuery À L'INTÉRIEUR de MaterialApp (sinon MaterialApp recrée le
    // sien depuis la fenêtre et écrase le flag).
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: !animations),
          child: child,
        ),
      ),
    ),
  );

  Widget buildAuto(ExperienceIntroStore store, {bool animations = false}) =>
      shell(AuryelExperienceScreen(store: store), animations: animations);

  Widget buildReplay() =>
      shell(const AuryelExperienceScreen(fromDashboard: true));

  // -----------------------------------------------------------------------
  group('ExperienceIntroStore — flag local dédié', () {
    test('clé distincte de la vidéo d\'intro', () {
      expect(ExperienceIntroStore.key, 'auryel.experience_intro_seen.v1');
      expect(ExperienceIntroStore.key == IntroVideoStore.key, isFalse);
    });

    test('par défaut : non vu ; markSeen persiste ; reset oublie', () async {
      final s = ExperienceIntroStore();
      expect(await s.hasSeen(), isFalse);
      await s.markSeen();
      expect(await s.hasSeen(), isTrue);
      await s.reset();
      expect(await s.hasSeen(), isFalse);
    });
  });

  // -----------------------------------------------------------------------
  testWidgets('B — slogan officiel affiché EXACTEMENT', (t) async {
    await t.pumpWidget(buildAuto(ExperienceIntroStore()));
    await t.pump();
    expect(find.text('Bienvenue dans Auryel'), findsOneWidget);
    expect(find.text(_slogan), findsOneWidget);
  });

  testWidgets('C — les 7 fonctionnalités présentées + badge « À venir » '
      'Boutique', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(
      384,
      4000,
    ); // tout à l'écran, pas de scroll
    addTearDown(t.view.reset);

    await t.pumpWidget(buildAuto(ExperienceIntroStore()));
    await t.pump();

    for (final title in _blockTitles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('À venir'), findsOneWidget); // badge Boutique
    expect(find.text('TON EXPÉRIENCE AURYEL'), findsOneWidget);
    // aucune promesse d'humain / de certitude / de récompense acquise
    expect(find.textContaining('expert humain'), findsNothing);
    expect(find.textContaining('5 minutes de consultation'), findsNothing);
  });

  testWidgets('D/E — « Découvrir Auryel » -> flag vu + MainNavShell', (
    t,
  ) async {
    final store = ExperienceIntroStore();
    await t.pumpWidget(buildAuto(store));
    await t.pump();

    expect(find.text('Découvrir Auryel'), findsOneWidget);
    expect(await store.hasSeen(), isFalse);

    await t.tap(find.text('Découvrir Auryel'));
    await t.pumpAndSettle();

    expect(await store.hasSeen(), isTrue);
    expect(find.byType(WakeOnboardingScreen), findsOneWidget);
    expect(find.byType(AuryelExperienceScreen), findsNothing);
  });

  testWidgets('F — après « vu », rien ne réaffiche l\'écran automatiquement '
      '(le splash ne le route jamais)', (t) async {
    // La seule voie automatique est AccountCreationScreen (couvert par
    // auth_password_test). Le splash / IntroGate n'y touchent pas : ré-ouvrir
    // l'app avec le flag posé ne repasse pas par cet écran.
    await ExperienceIntroStore().markSeen();
    expect(await ExperienceIntroStore().hasSeen(), isTrue);
    // IntroGate inchangé (aucune branche « experience »).
    expect(
      IntroGate.decide(onboardingCompleted: true, introVideoSeen: true),
      IntroStep.authRouting,
    );
  });

  testWidgets('G/H — replay depuis le Dashboard : « Retour à Auryel », pop, '
      'flag INCHANGÉ', (t) async {
    // flag déjà posé par le parcours auto
    SharedPreferences.setMockInitialValues({ExperienceIntroStore.key: true});

    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const AuryelExperienceScreen(fromDashboard: true),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.byType(AuryelExperienceScreen), findsOneWidget);
    expect(find.text(_slogan), findsOneWidget);
    // CTA de replay ≠ « Découvrir Auryel »
    expect(find.text('Découvrir Auryel'), findsNothing);
    expect(find.text('Retour à Auryel'), findsOneWidget);

    await t.tap(find.text('Retour à Auryel'));
    await t.pumpAndSettle();

    // Revenu à l'écran précédent, PAS MainNavShell, flag intact.
    expect(find.byType(AuryelExperienceScreen), findsNothing);
    expect(find.byType(MainNavShell), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(await ExperienceIntroStore().hasSeen(), isTrue); // toujours vrai
  });

  testWidgets('replay : la flèche retour de l\'en-tête pop aussi', (t) async {
    await t.pumpWidget(buildReplay());
    await t.pump();
    expect(find.byTooltip('Retour'), findsOneWidget);
  });

  testWidgets('parcours auto : pas de flèche retour d\'en-tête', (t) async {
    await t.pumpWidget(buildAuto(ExperienceIntroStore()));
    await t.pump();
    expect(find.byTooltip('Retour'), findsNothing);
  });

  for (final w in const [360.0, 384.0, 430.0]) {
    testWidgets('aucun overflow à ${w.toInt()} dp (reduce motion)', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 780);
      addTearDown(t.view.reset);
      await t.pumpWidget(buildAuto(ExperienceIntroStore()));
      await t.pump();
      expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
      expect(find.text('Découvrir Auryel'), findsOneWidget); // CTA accessible
    });
  }

  testWidgets('ANIM — animations activées : révélation se termine, aucun '
      'overflow, tout le contenu visible, CTA fonctionnel', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(384, 820);
    addTearDown(t.view.reset);

    final store = ExperienceIntroStore();
    await t.pumpWidget(buildAuto(store, animations: true));
    // Laisse toute la séquence (fade/slide décalés + glow + shimmer CTA) finir.
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.text('Bienvenue dans Auryel'), findsOneWidget);
    expect(find.text(_slogan), findsOneWidget);
    for (final title in _blockTitles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('À venir'), findsOneWidget);

    // CTA toujours actif après les animations.
    await t.tap(find.text('Découvrir Auryel'));
    await t.pumpAndSettle();
    expect(await store.hasSeen(), isTrue);
    expect(find.byType(WakeOnboardingScreen), findsOneWidget);
  });

  testWidgets('ANIM — reduce motion : rendu final immédiat (aucun Timer '
      'd\'animation en attente)', (t) async {
    await t.pumpWidget(buildAuto(ExperienceIntroStore())); // disableAnimations
    await t.pump(); // une seule frame suffit
    expect(find.text('Bienvenue dans Auryel'), findsOneWidget);
    expect(find.text('Découvrir Auryel'), findsOneWidget);
    // pas de pumpAndSettle nécessaire : aucun widget Animate monté.
  });
}

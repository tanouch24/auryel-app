import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/onboarding/account_creation_screen.dart';
import 'package:auryel/screens/onboarding/advisor_selection_screen.dart';
import 'package:auryel/screens/onboarding/birth_date_screen.dart';
import 'package:auryel/screens/onboarding/first_name_screen.dart';
import 'package:auryel/screens/onboarding/portrait_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/onboarding_scaffold.dart';

AuryelState _state({
  String? firstName,
  DateTime? birthDate,
  String? selectedAdvisor,
  String? portraitData,
  String? portraitFeedback,
}) => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: null,
    selectedAdvisor: selectedAdvisor,
    firstName: firstName,
    birthDate: birthDate,
    portraitData: portraitData,
    portraitFeedback: portraitFeedback,
    onboardingCompleted: false,
  ),
);

Future<void> _pump(WidgetTester tester, AuryelState state) => tester.pumpWidget(
  AuryelStateScope(
    state: state,
    child: const MaterialApp(home: FirstNameScreen()),
  ),
);

int _step(WidgetTester tester) =>
    tester.widget<OnboardingScaffold>(find.byType(OnboardingScaffold)).step;

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.text('Continuer'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('nouvel ordre : prénom(1) -> date(2) -> parle-moi de toi(3) -> '
      'conseiller(4) -> compte(5)', (tester) async {
    final state = _state();
    await _pump(tester, state);

    // 1/5 — prénom, premier écran, sans retour.
    expect(find.byType(FirstNameScreen), findsOneWidget);
    expect(find.text('Comment veux-tu qu’on t’appelle ?'), findsOneWidget);
    expect(_step(tester), 1);
    expect(find.text('Choisis ton conseiller'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    await _tapContinue(tester);

    // 2/5 — date de naissance, saisie libre.
    expect(find.byType(BirthDateScreen), findsOneWidget);
    expect(find.text('Quelle est ta date de naissance ?'), findsOneWidget);
    expect(_step(tester), 2);

    await tester.enterText(find.byType(TextField), '17 mai 2000');
    await tester.pump();
    expect(find.text('17 mai 2000 ✓'), findsOneWidget); // confirmation lisible
    await _tapContinue(tester);

    // 3/5 — « parle-moi un peu de toi » (ex-PortraitScreen).
    expect(find.byType(PortraitScreen), findsOneWidget);
    expect(find.text('Parle-moi un peu de toi'), findsOneWidget);
    expect(_step(tester), 3);
    await _tapContinue(tester);

    // 4/5 — conseiller, APRÈS le profil.
    expect(find.byType(AdvisorSelectionScreen), findsOneWidget);
    expect(find.text('Choisis ton conseiller'), findsOneWidget);
    expect(_step(tester), 4);

    // spécialité + tagline visibles AVANT sélection.
    expect(find.text('AMOUR & RELATIONS'), findsWidgets);
    expect(
      find.text(kAdvisors.first.tagline), // Séléna
      findsOneWidget,
    );

    await tester.tap(find.text('Luna'));
    await tester.pump();
    expect(state.selectedAdvisor, isNull); // pas encore validé
    await _tapContinue(tester);

    // 5/5 — création du compte.
    expect(find.byType(AccountCreationScreen), findsOneWidget);
    expect(_step(tester), 5);
    expect(state.selectedAdvisor, 'Luna');
    expect(state.firstName, 'Alice');
    expect(state.birthDate, DateTime(2000, 5, 17));
  });

  testWidgets('retour arrière : conseiller -> parle-moi de toi -> date', (
    tester,
  ) async {
    await _pump(tester, _state());
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    await _tapContinue(tester);
    await tester.enterText(find.byType(TextField), '17 mai 2000');
    await tester.pump();
    await _tapContinue(tester); // -> portrait
    await _tapContinue(tester); // -> conseiller
    expect(find.byType(AdvisorSelectionScreen), findsOneWidget);

    // Bouton retour de l'OnboardingScaffold (1er IconButton de l'écran).
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(PortraitScreen), findsOneWidget);
    expect(_step(tester), 3);

    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(BirthDateScreen), findsOneWidget);
    expect(_step(tester), 2);
  });

  testWidgets('données existantes préremplies (prénom, date, conseiller)', (
    tester,
  ) async {
    final state = _state(
      firstName: 'Bob',
      birthDate: DateTime(2000, 5, 17),
      selectedAdvisor: 'Luna',
      portraitData: 'portrait déjà généré',
      portraitFeedback: 'déjà répondu',
    );
    await _pump(tester, state);

    // Prénom prérempli, CTA actif d'emblée.
    expect(_fieldText(tester), 'Bob');
    await _tapContinue(tester);

    // Date préremplie de façon lisible.
    expect(_fieldText(tester), '17 mai 2000');
    expect(find.text('17 mai 2000 ✓'), findsOneWidget);
    await _tapContinue(tester);

    // Portrait conservé (texte serveur), pas écrasé.
    expect(find.text('portrait déjà généré'), findsOneWidget);
    await _tapContinue(tester);

    // Conseiller déjà choisi -> CTA actif sans nouvelle sélection.
    expect(find.byType(AdvisorSelectionScreen), findsOneWidget);
    await _tapContinue(tester);
    expect(find.byType(AccountCreationScreen), findsOneWidget);
    expect(state.selectedAdvisor, 'Luna');
    expect(state.firstName, 'Bob');
    expect(state.birthDate, DateTime(2000, 5, 17));
    expect(state.portraitFeedback, 'déjà répondu'); // pas écrasé par du vide
  });

  testWidgets('date invalide -> message + Continuer désactivé', (tester) async {
    await _pump(tester, _state());
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    await _tapContinue(tester);

    await tester.enterText(find.byType(TextField), '31 février 2000');
    await tester.pump();
    expect(find.text('Vérifie ta date de naissance'), findsOneWidget);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    // Toujours sur l'écran date : CTA désactivé a bloqué la navigation.
    expect(find.byType(BirthDateScreen), findsOneWidget);
  });

  testWidgets('règle 18+ : date valide mais < 18 ans -> message neutre + '
      'Continuer désactivé ; corrigée -> on peut avancer', (tester) async {
    await _pump(tester, _state());
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    await _tapContinue(tester);
    expect(find.byType(BirthDateScreen), findsOneWidget);

    // ~10 ans : date parfaitement valide mais sous le seuil.
    final minorYear = DateTime.now().year - 10;
    await tester.enterText(find.byType(TextField), '1 janvier $minorYear');
    await tester.pump();

    expect(
      find.text('Auryel est réservé aux personnes âgées de 18 ans ou plus.'),
      findsOneWidget,
    );
    expect(find.textContaining('✓'), findsNothing);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    // Bloqué : l'onboarding ne peut pas se terminer.
    expect(find.byType(BirthDateScreen), findsOneWidget);
    expect(find.byType(PortraitScreen), findsNothing);

    // Correction avec une date adulte -> le message disparaît, on avance.
    await tester.enterText(find.byType(TextField), '17 mai 1995');
    await tester.pump();
    expect(
      find.text('Auryel est réservé aux personnes âgées de 18 ans ou plus.'),
      findsNothing,
    );
    expect(find.text('17 mai 1995 ✓'), findsOneWidget);
    await _tapContinue(tester);
    expect(find.byType(PortraitScreen), findsOneWidget);
  });
}

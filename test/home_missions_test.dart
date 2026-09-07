import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// LOT « MON AURYEL AUJOURD'HUI » — nouvelle Home : Pensée -> Missions -> Temps.
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

Widget _host({List<int>? tabTaps}) => AuryelStateScope(
  state: _state(),
  child: MaterialApp(
    home: MainNavScope(
      goToTab: (i) => tabTaps?.add(i),
      currentIndex: kTabHome,
      child: HomeScreen(thoughtRepository: _repo()),
    ),
  ),
);

String _todayKey() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Home — ordre & conseillers retirés', () {
    testWidgets('Pensée AVANT Missions AVANT Temps disponible', (t) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));

      final penseeDy = t
          .getTopLeft(
            find.byWidgetPredicate(
              (w) =>
                  w is RichText && w.text.toPlainText().contains('te dirige.'),
            ),
          )
          .dy;
      final missionsDy = t.getTopLeft(find.text('TES MISSIONS DU JOUR')).dy;
      final tempsDy = t.getTopLeft(find.text('TEMPS DISPONIBLE')).dy;

      expect(missionsDy, greaterThan(penseeDy));
      expect(tempsDy, greaterThan(missionsDy));
    });

    testWidgets('aucun carrousel conseillers, aucun lien conseiller', (
      t,
    ) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(AdvisorsCarousel), findsNothing);
      expect(find.text('Changer de conseiller'), findsNothing);
      expect(find.text('Découvre nos conseillers'), findsNothing);
    });
  });

  group('Missions', () {
    testWidgets('exactement 4 missions, compteur 0/4 au départ', (t) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));

      expect(find.text('Fais ton tirage'), findsOneWidget);
      expect(find.text('Consulte ton conseiller'), findsOneWidget);
      expect(find.text('Partage ta pensée'), findsOneWidget);
      expect(find.text('Prends ton Moment'), findsOneWidget);
      expect(find.text('0/4'), findsOneWidget);
      expect(find.text('Journée Auryel complétée'), findsNothing);
      // aucune coche
      expect(
        find.byWidgetPredicate(
          (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.checkCircle,
        ),
        findsNothing,
      );
    });

    testWidgets('partage déjà fait aujourd\'hui -> mission « Partage » cochée, '
        'compteur 1/4', (t) async {
      SharedPreferences.setMockInitialValues({
        'auryel.daily_share.days': [_todayKey()],
      });
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('1/4'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is PhosphorIcon && w.icon == PhosphorIconsFill.checkCircle,
        ),
        findsOneWidget,
      );
    });

    testWidgets('4/4 -> « Journée Auryel complétée »', (t) async {
      final today = _todayKey();
      SharedPreferences.setMockInitialValues({
        'auryel.daily_share.days': [today],
        'auryel.daily_mission.tirage': today,
        'auryel.daily_mission.consultation': today,
        'auryel.daily_mission.moment': today,
      });
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('Journée Auryel complétée'), findsOneWidget);
    });

    testWidgets('tap « Fais ton tirage » -> demande l\'onglet Tirage (1)', (
      t,
    ) async {
      final taps = <int>[];
      await t.pumpWidget(_host(tabTaps: taps));
      await t.pump(const Duration(seconds: 1));

      await t.tap(find.text('Fais ton tirage'));
      await t.pump();
      expect(taps, contains(kTabTirage));
    });

    testWidgets('tap « Consulte ton conseiller » -> demande l\'onglet '
        'CONSULTATION (2), sans cocher la mission', (t) async {
      final taps = <int>[];
      await t.pumpWidget(_host(tabTaps: taps));
      await t.pump(const Duration(seconds: 1));

      await t.tap(find.text('Consulte ton conseiller'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(taps, contains(kTabConsultation));
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.consultation),
        isFalse,
      );
    });

    testWidgets('tap « Prends ton Moment » -> onglet Méditation, mission NON '
        'marquée à l\'ouverture (uniquement sur une séance aboutie)', (
      t,
    ) async {
      final taps = <int>[];
      await t.pumpWidget(_host(tabTaps: taps));
      await t.pump(const Duration(seconds: 1));

      await t.tap(find.text('Prends ton Moment'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      expect(taps, contains(kTabMeditation));
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
      );
    });

    testWidgets(
      'tap « Partage ta pensée » -> ouvre l\'aperçu de la publication',
      (t) async {
        await t.pumpWidget(_host());
        await t.pump(const Duration(seconds: 1));

        await t.tap(find.text('Partage ta pensée'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(DailyMessageSheet), findsOneWidget);
      },
    );

    testWidgets('lignes de mission : Semantics bouton + état coché', (t) async {
      final today = _todayKey();
      SharedPreferences.setMockInitialValues({
        'auryel.daily_mission.tirage': today,
      });
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 50));

      // Chaque ligne = un Semantics(button:true, checked:<état>).
      final missionSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            (w.properties.label ?? '').contains('tirage'),
      );
      expect(missionSemantics, findsOneWidget);
      final props = t.widget<Semantics>(missionSemantics).properties;
      expect(
        props.checked,
        isTrue,
        reason: 'tirage fait aujourd\'hui -> coché',
      );
    });
  });

  group('DailyMissionTracker', () {
    test('reset logique automatique au changement de jour', () async {
      final tr = DailyMissionTracker();
      await tr.markDone(
        DailyMissionTracker.tirage,
        now: DateTime(2026, 9, 5, 10),
      );
      expect(
        await tr.isDone(
          DailyMissionTracker.tirage,
          now: DateTime(2026, 9, 5, 23),
        ),
        isTrue,
      );
      expect(
        await tr.isDone(
          DailyMissionTracker.tirage,
          now: DateTime(2026, 9, 6, 0, 1),
        ),
        isFalse,
      );
    });

    test('aucune notion de récompense / temps / achat', () {
      const api = {'isDone', 'markDone', 'tirage', 'consultation', 'moment'};
      expect(
        api.any(
          (m) =>
              m.toLowerCase().contains('reward') ||
              m.toLowerCase().contains('hour') ||
              m.toLowerCase().contains('second') ||
              m.toLowerCase().contains('credit') ||
              m.toLowerCase().contains('purchase'),
        ),
        isFalse,
      );
    });
  });

  group('Temps disponible (bloc compact)', () {
    testWidgets(
      'sans ConsultationScope -> « TEMPS DISPONIBLE » + « 1 h offerte » '
      '+ CTA « Consulter »',
      (t) async {
        await t.pumpWidget(_host());
        await t.pump(const Duration(seconds: 1));
        expect(find.text('TEMPS DISPONIBLE'), findsOneWidget);
        expect(find.text('1 h offerte'), findsOneWidget);
        expect(find.text('Consulter'), findsOneWidget);
      },
    );
  });

  group('Pensée du jour — préservée', () {
    testWidgets(
      'CTA partage + « Cliquez ici » + « X / 30 jours » + aucune date',
      (t) async {
        await t.pumpWidget(_host());
        await t.pump(const Duration(seconds: 1));
        expect(
          find.textContaining('gagne 1 h de consultation offerte'),
          findsOneWidget,
        );
        expect(find.text('Cliquez ici'), findsOneWidget);
        expect(find.textContaining('/ 30 jours'), findsOneWidget);
        expect(find.textContaining('AOÛT'), findsNothing);
        expect(find.textContaining('2026'), findsNothing);
      },
    );

    testWidgets('la publication du jour reste ouvrable depuis le CTA', (
      t,
    ) async {
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.textContaining('gagne 1 h de consultation offerte'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(DailyMessageSheet), findsOneWidget);
    });
  });

  group('Responsive ~384 dp', () {
    testWidgets('aucun overflow avec toutes les sections', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(384, 850);
      addTearDown(t.view.reset);
      await t.pumpWidget(_host());
      await t.pump(const Duration(seconds: 1));
      expect(find.text('TES MISSIONS DU JOUR'), findsOneWidget);
      expect(find.text('TEMPS DISPONIBLE'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

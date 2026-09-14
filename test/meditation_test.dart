import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/daily_mission_tracker.dart';
import 'package:auryel/data/meditation_audio.dart';
import 'package:auryel/data/meditation_catalog.dart';
import 'package:auryel/screens/meditation_screen.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// Faux lecteur — aucun canal plateforme, la progression est pilotée par le test.
// ===========================================================================
class _FakeMeditationAudio implements MeditationAudio {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _done = StreamController<void>.broadcast();

  final List<String> calls = [];
  bool available = true;
  bool _playing = false;

  void emitPosition(Duration d) => _pos.add(d);
  void emitDuration(Duration d) => _dur.add(d);
  void emitComplete() => _done.add(null);

  @override
  Stream<Duration> get onPosition => _pos.stream;
  @override
  Stream<Duration> get onDuration => _dur.stream;
  @override
  Stream<void> get onComplete => _done.stream;
  @override
  bool get isPlaying => _playing;

  @override
  Future<void> prepare(String source) async {
    calls.add('prepare:$source');
  }

  @override
  Future<bool> play(String assetPath) async {
    calls.add('play:$assetPath');
    _playing = available;
    return available;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing = false;
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _playing = true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _playing = false;
  }

  @override
  void dispose() {
    calls.add('dispose');
    _pos.close();
    _dur.close();
    _done.close();
  }
}

Widget _host(
  MeditationAudio audio, {
  int currentIndex = kTabMeditation,
  DateTime? now,
}) {
  return MaterialApp(
    home: MainNavScope(
      goToTab: (_) {},
      currentIndex: currentIndex,
      child: Scaffold(
        body: MeditationScreen(
          audioOverride: audio,
          now: now ?? DateTime(2026, 1, 1),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1/2 — vrai écran : « Ton Moment du jour » + séance du jour, '
      'plus de PlaceholderScreen', (t) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    expect(find.byType(MeditationScreen), findsOneWidget);
    // REFONTE ÉPURÉE — l'ancien bloc de légende « Ton Moment du jour » /
    // « Méditation », redondant avec l'en-tête « AURYEL · MÉDITATION » et le
    // titre affiché, a été supprimé. La preuve que la VRAIE séance du jour
    // est affichée (pas de PlaceholderScreen) reste le titre exact.
    // Séance déterministe pour le 2026-01-01 (index 0 du catalogue).
    expect(find.text(MeditationCatalog.items.first.title), findsOneWidget);
  });

  testWidgets('3/5 — play lance la lecture ; la progression se met à jour', (
    t,
  ) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(
      a.calls,
      contains('play:${MeditationCatalog.items.first.assetPath}'),
    );

    a.emitDuration(const Duration(minutes: 4));
    a.emitPosition(const Duration(minutes: 1));
    await t.pump();
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('04:00'), findsOneWidget);
  });

  testWidgets('4 — pause fonctionne', (t) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);

    await t.ensureVisible(find.bySemanticsLabel('Mettre en pause'));
    await t.tap(find.bySemanticsLabel('Mettre en pause'));
    await t.pump();
    expect(a.calls, contains('pause'));
    expect(find.bySemanticsLabel('Lancer le moment'), findsOneWidget);
  });

  testWidgets('6 — quitter l\'onglet met la séance en pause', (t) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();

    // On simule un changement d'onglet (currentIndex != Méditation).
    await t.pumpWidget(_host(a, currentIndex: kTabConsultation));
    await t.pump();
    expect(a.calls, contains('pause'));
  });

  testWidgets('7 — passage en arrière-plan met en pause', (t) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(a.calls, contains('pause'));
  });

  testWidgets('8 — retour au premier plan : AUCUNE reprise automatique', (
    t,
  ) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    final callsAfterPause = [...a.calls];
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(a.calls, callsAfterPause, reason: 'pas de resume/play auto');
  });

  testWidgets('9 — ouvrir l\'écran seul ne coche pas la mission Moment', (
    t,
  ) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();
    expect(
      await DailyMissionTracker().isDone(DailyMissionTracker.moment),
      isFalse,
    );
  });

  // RÈGLE PRODUIT DÉFINITIVE (ce lot) : « Prends ton temps » se coche
  // UNIQUEMENT quand une vidéo de relaxation commence RÉELLEMENT à être lue.
  // AUCUN repli sur l'audio, jamais. Cet écran (`_host`) n'a aucun
  // `ContentScope` -> aucune vidéo n'est jamais disponible -> la mission ne
  // doit JAMAIS se cocher ici, quels que soient les signaux audio (tap,
  // position, complétion). Les scénarios AVEC vidéo sont couverts dans
  // meditation_video_test.dart.
  testWidgets(
    '10 — sans vidéo disponible : le démarrage de l\'audio NE coche PAS la '
    'mission',
    (t) async {
      final a = _FakeMeditationAudio();
      await t.pumpWidget(_host(a));
      await t.pumpAndSettle();
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
      );

      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pump();
      expect(a.isPlaying, isTrue, reason: 'l’audio, lui, démarre bien');
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
        reason: 'audio démarré SANS vidéo -> aucun repli, mission non cochée',
      );
    },
  );

  testWidgets(
    '10 bis — tap qui échoue à démarrer l\'audio ne coche pas non plus '
    '(à plus forte raison)',
    (t) async {
      final a = _FakeMeditationAudio()..available = false;
      await t.pumpWidget(_host(a));
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pump();
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
      );
    },
  );

  testWidgets(
    '11 — sans vidéo disponible, même la fin naturelle de l\'audio ne coche '
    'PAS la mission',
    (t) async {
      final a = _FakeMeditationAudio();
      await t.pumpWidget(_host(a));
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pump();

      a.emitDuration(const Duration(minutes: 5));
      a.emitComplete();
      await t.pump();
      expect(find.textContaining('Moment terminé'), findsOneWidget);
      expect(
        await DailyMissionTracker().isDone(DailyMissionTracker.moment),
        isFalse,
        reason: 'la fin naturelle de l’audio n’est pas un démarrage vidéo',
      );
    },
  );

  testWidgets(
    '12 — sans vidéo, la mission ne se marque JAMAIS, quels que soient les '
    'signaux audio',
    (t) async {
      var markCalls = 0;
      final tracker = _CountingTracker(() => markCalls++);
      final a = _FakeMeditationAudio();
      await t.pumpWidget(
        MaterialApp(
          home: MainNavScope(
            goToTab: (_) {},
            currentIndex: kTabMeditation,
            child: Scaffold(
              body: MeditationScreen(
                audioOverride: a,
                now: DateTime(2026, 1, 1),
                missionTracker: tracker,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
      await t.tap(find.bySemanticsLabel('Lancer le moment'));
      await t.pump();

      a.emitDuration(const Duration(seconds: 100));
      a.emitPosition(const Duration(seconds: 95));
      a.emitPosition(const Duration(seconds: 96));
      a.emitPosition(const Duration(seconds: 99));
      a.emitComplete();
      await t.pump();
      expect(markCalls, 0, reason: 'aucune vidéo -> jamais de markDone');
    },
  );

  testWidgets('13 — fichier absent : pas de crash, état « bientôt » affiché', (
    t,
  ) async {
    final a = _FakeMeditationAudio()..available = false;
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle();

    await t.ensureVisible(find.bySemanticsLabel('Lancer le moment'));
    await t.tap(find.bySemanticsLabel('Lancer le moment'));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.textContaining('bientôt'), findsOneWidget);
    expect(
      await DailyMissionTracker().isDone(DailyMissionTracker.moment),
      isFalse,
    );
  });

  testWidgets('14 — aucun chevauchement logique avec Consultation : Méditation '
      'ne joue jamais en autoplay', (t) async {
    final a = _FakeMeditationAudio();
    // L\'écran est monté alors que l\'onglet visible est Consultation.
    await t.pumpWidget(_host(a, currentIndex: kTabConsultation));
    await t.pumpAndSettle();
    expect(a.calls.where((c) => c.startsWith('play')), isEmpty);

    // On arrive sur l\'onglet Méditation : toujours pas d\'autoplay.
    await t.pumpWidget(_host(a, currentIndex: kTabMeditation));
    await t.pumpAndSettle();
    expect(a.calls.where((c) => c.startsWith('play')), isEmpty);
  });

  testWidgets('catalogue — sélection du jour déterministe et stable', (
    t,
  ) async {
    const cat = MeditationCatalog();
    final d1 = cat.momentOfDay(DateTime(2026, 3, 10, 8));
    final d1b = cat.momentOfDay(DateTime(2026, 3, 10, 23));
    final d2 = cat.momentOfDay(DateTime(2026, 3, 11, 8));
    expect(d1.id, d1b.id);
    expect(d1.id, isNot(d2.id));
  });

  // Anti-régression : pas d\'animation infinie (sinon pumpAndSettle bloque).
  testWidgets('no timeout — pumpAndSettle se termine', (t) async {
    final a = _FakeMeditationAudio();
    await t.pumpWidget(_host(a));
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
  });
}

/// Tracker qui compte les `markDone` sans jamais persister (fenêtre du jour).
class _CountingTracker extends DailyMissionTracker {
  _CountingTracker(this._onMark);
  final VoidCallback _onMark;

  @override
  Future<void> markDone(String mission, {DateTime? now}) async {
    _onMark();
  }

  @override
  Future<bool> isDone(String mission, {DateTime? now}) async => false;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/intro_video_store.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/screens/intro_video_screen.dart';
import 'package:auryel/screens/onboarding/first_name_screen.dart';
import 'package:auryel/state/auryel_state.dart';

// ===========================================================================
// UX-LOT §8-13 — vidéo d'intro Auryel : décision PURE + persistance + écran.
// ===========================================================================

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ------------------------------------------------------------------------
  group('IntroGate — décision pure', () {
    test('A — onboarding terminé -> jamais de vidéo (authRouting)', () {
      expect(
        IntroGate.decide(onboardingCompleted: true, introVideoSeen: false),
        IntroStep.authRouting,
      );
      expect(
        IntroGate.decide(onboardingCompleted: true, introVideoSeen: true),
        IntroStep.authRouting,
      );
    });

    test('B — onboarding non terminé + intro non vue -> vidéo', () {
      expect(
        IntroGate.decide(onboardingCompleted: false, introVideoSeen: false),
        IntroStep.video,
      );
    });

    test('C — intro vue + onboarding non terminé -> onboarding direct', () {
      expect(
        IntroGate.decide(onboardingCompleted: false, introVideoSeen: true),
        IntroStep.onboarding,
      );
    });
  });

  // ------------------------------------------------------------------------
  group('introPlaybackFinished — détection de fin robuste (Android)', () {
    const d = Duration(seconds: 6);

    test('isCompleted signalé par le plugin -> fini', () {
      expect(
        introPlaybackFinished(
          isCompleted: true,
          hasError: false,
          position: const Duration(seconds: 3),
          duration: d,
        ),
        isTrue,
      );
    });

    test('dernière frame atteinte (position >= duration) -> fini, '
        'indépendamment de isPlaying', () {
      expect(
        introPlaybackFinished(
          isCompleted: false,
          hasError: false,
          position: d, // tête de lecture au bout
          duration: d,
        ),
        isTrue,
      );
      // 80 ms avant la fin compte aussi comme fini (tolérance).
      expect(
        introPlaybackFinished(
          isCompleted: false,
          hasError: false,
          position: d - const Duration(milliseconds: 50),
          duration: d,
        ),
        isTrue,
      );
    });

    test('en cours de lecture -> pas fini', () {
      expect(
        introPlaybackFinished(
          isCompleted: false,
          hasError: false,
          position: const Duration(seconds: 2),
          duration: d,
        ),
        isFalse,
      );
    });

    test('erreur -> fini (on ne bloque jamais)', () {
      expect(
        introPlaybackFinished(
          isCompleted: false,
          hasError: true,
          position: Duration.zero,
          duration: Duration.zero,
        ),
        isTrue,
      );
    });

    test('pas encore initialisé (duration = 0) -> pas fini', () {
      expect(
        introPlaybackFinished(
          isCompleted: false,
          hasError: false,
          position: Duration.zero,
          duration: Duration.zero,
        ),
        isFalse,
      );
    });
  });

  // ------------------------------------------------------------------------
  group('IntroVideoStore — persistance locale', () {
    test('par défaut : non vue', () async {
      expect(await IntroVideoStore().hasSeen(), isFalse);
    });

    test(
      'D/E/H — markSeen persiste, survit à un nouveau store (= relance)',
      () async {
        await IntroVideoStore().markSeen();
        expect(await IntroVideoStore().hasSeen(), isTrue);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(IntroVideoStore.key), isTrue);
      },
    );

    test('reset (DEBUG ciblé) : oublie sans toucher au reste', () async {
      SharedPreferences.setMockInitialValues({
        IntroVideoStore.key: true,
        'autre.cle': 'garde-moi',
      });
      await IntroVideoStore().reset();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(IntroVideoStore.key), isNull);
      expect(prefs.getString('autre.cle'), 'garde-moi');
    });
  });

  // ------------------------------------------------------------------------
  group('IntroVideoScreen — pas de plugin vidéo en test', () {
    testWidgets('F/E/G — vidéo indisponible -> marque vue + onDone UNE fois, '
        'jamais de blocage', (t) async {
      final store = IntroVideoStore();
      var doneCalls = 0;

      await t.pumpWidget(
        MaterialApp(
          home: IntroVideoScreen(store: store, onDone: () => doneCalls++),
        ),
      );
      // Pas de plugin vidéo en test : soit l'init lève (fallback immédiat),
      // soit le watchdog (5 s) prend le relais.
      await t.pump();
      await t.pump(const Duration(seconds: 6));
      await t.pump();

      expect(doneCalls, 1, reason: 'onDone appelé exactement une fois');
      expect(await store.hasSeen(), isTrue);

      // idempotence : plus aucun appel ensuite.
      await t.pump(const Duration(seconds: 6));
      expect(doneCalls, 1);
    });

    testWidgets('« Passer » visible + skip -> marque vue + onDone', (t) async {
      final store = IntroVideoStore();
      var done = 0;
      await t.pumpWidget(
        MaterialApp(
          home: IntroVideoScreen(store: store, onDone: () => done++),
        ),
      );
      await t.pump();
      expect(find.text('Passer'), findsOneWidget);

      await t.tap(find.text('Passer'));
      await t.pump();
      await t.pump();
      expect(done, 1);
      expect(await store.hasSeen(), isTrue);
    });

    testWidgets(
      'G — onDone enchaîne (route remplacée) sans double navigation',
      (t) async {
        var navPushes = 0;
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => IntroVideoScreen(
                onDone: () {
                  navPushes++;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          const Scaffold(key: ValueKey('after-intro')),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(seconds: 6));
        await t.pumpAndSettle();

        expect(navPushes, 1);
        expect(find.byType(IntroVideoScreen), findsNothing);
        expect(find.byKey(const ValueKey('after-intro')), findsOneWidget);
      },
    );

    testWidgets(
      'destination = écran prénom (FirstNameScreen), une seule fois',
      (t) async {
        var pushes = 0;
        await t.pumpWidget(
          AuryelStateScope(
            state: AuryelState(repository: LocalOnboardingRepository()),
            child: MaterialApp(
              home: Builder(
                builder: (context) => IntroVideoScreen(
                  onDone: () {
                    pushes++;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const FirstNameScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(seconds: 6));
        await t.pumpAndSettle();

        expect(pushes, 1);
        expect(find.byType(FirstNameScreen), findsOneWidget);
        expect(find.text('Comment veux-tu qu’on t’appelle ?'), findsOneWidget);
      },
    );
  });
}

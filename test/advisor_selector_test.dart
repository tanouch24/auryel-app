import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/advisor_audio.dart';
import 'package:auryel/screens/advisor_selector_screen.dart';
import 'package:auryel/widgets/advisors_carousel.dart';

// ===========================================================================
// J6-F2 §16 — le PageView vertical des 10 conseillers est réutilisé COMME
// SÉLECTEUR (« Choisir un conseiller » / « Demander un autre avis » / tirage
// « En parler »). Il renvoie (Navigator.pop) le conseiller choisi et
// n'appelle JAMAIS changeAdvisor.
// ===========================================================================

class _FakeAudio implements AdvisorAudio {
  final List<String> calls = [];
  String? lastAsset;

  @override
  Future<void> play(String assetPath, {Duration fadeIn = Duration.zero}) async {
    lastAsset = assetPath;
    calls.add('play:$assetPath');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  void dispose() => calls.add('dispose');
}

Widget _host({
  required AdvisorAudio audio,
  Set<String> existing = const {},
  String title = 'Choisis un conseiller',
  void Function(AdvisorInfo?)? onPicked,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final picked = await Navigator.of(context).push<AdvisorInfo>(
                MaterialPageRoute(
                  builder: (_) => AdvisorSelectorScreen(
                    existingAdvisorIds: existing,
                    title: title,
                    audioOverride: audio,
                  ),
                ),
              );
              onPicked?.call(picked);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('feed vertical : 10 conseillers, 1 visible, titre affiché', (
    t,
  ) async {
    await t.pumpWidget(
      _host(audio: _FakeAudio(), title: 'Avec qui veux-tu en parler ?'),
    );
    await _open(t);

    final pv = t.widget<PageView>(find.byType(PageView));
    expect(pv.scrollDirection, Axis.vertical);
    expect(find.text('Avec qui veux-tu en parler ?'), findsOneWidget);
    // 1er conseiller = Séléna (nouveau) -> « Demander un avis avec Séléna ».
    expect(find.text('Demander un avis avec Séléna'), findsOneWidget);
    expect(find.text('Demander un avis avec Luna'), findsNothing);
  });

  testWidgets('conseiller déjà consulté -> « Reprendre » ; nouveau -> '
      '« Demander un avis »', (t) async {
    await t.pumpWidget(_host(audio: _FakeAudio(), existing: {'selena'}));
    await _open(t);
    expect(find.text('Reprendre avec Séléna'), findsOneWidget);
    expect(find.text('DÉJÀ CONSULTÉ'), findsOneWidget);

    await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
    await t.pumpAndSettle();
    expect(find.text('Demander un avis avec Luna'), findsOneWidget);
  });

  testWidgets('tap CTA -> renvoie le conseiller choisi (Navigator.pop)', (
    t,
  ) async {
    AdvisorInfo? picked;
    await t.pumpWidget(_host(audio: _FakeAudio(), onPicked: (a) => picked = a));
    await _open(t);
    await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
    await t.pumpAndSettle();
    await t.tap(find.text('Demander un avis avec Luna'));
    await t.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.name, 'Luna');
    expect(picked!.guideKey, 'luna');
    expect(find.byType(AdvisorSelectorScreen), findsNothing); // écran fermé
  });

  group('Audio (repris de l\'ancien feed)', () {
    testWidgets('autoplay au montage + un seul lecteur ; swipe stoppe avant '
        'de jouer le suivant', (t) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await _open(t);

      expect(audio.lastAsset, kAdvisors[0].voicePath);
      audio.calls.clear();

      await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
      await t.pumpAndSettle();

      final stopIdx = audio.calls.indexOf('stop');
      final playIdx = audio.calls.indexWhere(
        (c) => c == 'play:${kAdvisors[1].voicePath}',
      );
      expect(stopIdx, isNonNegative);
      expect(playIdx, isNonNegative);
      expect(stopIdx, lessThan(playIdx));
    });

    testWidgets('bouton mute : coupe l\'audio + préférence persistée', (
      t,
    ) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await _open(t);

      await t.tap(find.bySemanticsLabel('Couper le son des présentations'));
      await t.pumpAndSettle();
      expect(audio.calls, contains('stop'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auryel.consultation.audio_muted.v1'), isTrue);
    });

    testWidgets('lifecycle : arrière-plan arrête l\'audio', (t) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await _open(t);
      audio.calls.clear();

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pumpAndSettle();
      expect(audio.calls, contains('stop'));
    });
  });

  for (final w in const [360.0, 384.0, 430.0]) {
    testWidgets('aucun overflow à ${w.toInt()} dp', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 820);
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(audio: _FakeAudio()));
      await _open(t);
      expect(find.byType(PageView), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}

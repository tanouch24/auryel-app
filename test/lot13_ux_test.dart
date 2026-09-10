import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/advisor_audio.dart';
import 'package:auryel/screens/advisor_selector_screen.dart';

// ===========================================================================
// LOT 13 — UX final : indice « il y a d'autres conseillers plus bas » sur le
// sélecteur de conseillers (feed vertical). Discret, disparaît une fois que
// l'utilisateur a défilé, ne gêne jamais le CTA, compatible petits écrans.
// ===========================================================================

class _FakeAudio implements AdvisorAudio {
  @override
  Future<void> play(String assetPath, {Duration fadeIn = Duration.zero}) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

Widget _host(AdvisorAudio audio) => MaterialApp(
  home: AdvisorSelectorScreen(
    title: 'Avec qui veux-tu en parler ?',
    audioOverride: audio,
  ),
);

Finder _cueLabel() => find.text('Découvrir les autres conseillers');
Finder _cueChevron() => find.byIcon(PhosphorIconsRegular.caretDown);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('indice de défilement visible sur la 1re carte', (t) async {
    await t.pumpWidget(_host(_FakeAudio()));
    await t.pumpAndSettle();

    expect(_cueLabel(), findsOneWidget);
    expect(_cueChevron(), findsOneWidget);
    // le CTA principal reste présent et n'est pas gêné
    expect(find.textContaining('avec '), findsWidgets); // « Parler avec … »
  });

  testWidgets('l\'indice DISPARAÎT après le 1er défilement et ne revient pas', (
    t,
  ) async {
    await t.pumpWidget(_host(_FakeAudio()));
    await t.pumpAndSettle();
    expect(_cueLabel(), findsOneWidget);

    // défilement vers le conseiller suivant
    await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
    await t.pumpAndSettle();
    expect(_cueLabel(), findsNothing);

    // retour à la 1re carte : l'indice ne réapparaît pas (l'utilisateur a compris)
    await t.fling(find.byType(PageView), const Offset(0, 400), 1200);
    await t.pumpAndSettle();
    expect(_cueLabel(), findsNothing);
  });

  testWidgets('l\'indice n\'intercepte aucun tap (IgnorePointer)', (t) async {
    await t.pumpWidget(_host(_FakeAudio()));
    await t.pumpAndSettle();
    expect(
      find.ancestor(of: _cueLabel(), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
  });

  for (final size in const [
    Size(320, 480),
    Size(320, 520),
    Size(360, 640),
    Size(412, 915),
  ]) {
    testWidgets(
      'aucun overflow avec l\'indice à ${size.width.toInt()}×${size.height.toInt()}',
      (t) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = size;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(_host(_FakeAudio()));
        await t.pumpAndSettle();

        expect(t.takeException(), isNull);
        expect(_cueLabel(), findsOneWidget);
        // CTA toujours atteignable
        expect(find.byType(AdvisorSelectorScreen), findsOneWidget);
      },
    );
  }

  testWidgets('reduce motion : indice affiché sans animation, pas de crash', (
    t,
  ) async {
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(_FakeAudio()),
      ),
    );
    await t.pumpAndSettle();
    expect(_cueLabel(), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

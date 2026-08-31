import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/widgets/consultation_block.dart';

void main() {
  group('J — ConsultationBlock (F5-C)', () {
    testWidgets('firstFree affiche "2 h" et plus "24h"', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsultationBlock(
              state: ConsultationState.firstFree,
              advisorName: 'Séléna',
              advisorAssetPath: 'assets/conseillers/selena.webp',
              onStart: () {},
            ),
          ),
        ),
      );
      expect(
        find.text('Ta première consultation de 2 h est offerte'),
        findsOneWidget,
      );
      expect(find.textContaining('24h'), findsNothing);
      expect(find.textContaining('24 h'), findsNothing);
    });

    testWidgets('locked : le CTA appelle onSubscribe, pas onStart', (t) async {
      var started = 0;
      var subscribed = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsultationBlock(
              state: ConsultationState.locked,
              advisorName: 'Séléna',
              advisorAssetPath: 'assets/conseillers/selena.webp',
              onStart: () => started++,
              onSubscribe: () => subscribed++,
            ),
          ),
        ),
      );
      await t.tap(find.text('S’abonner pour consulter'));
      await t.pump();
      expect(subscribed, 1);
      expect(started, 0);
    });
  });

  // O — aucune constante debug de bloc consultation ne subsiste dans l'accueil.
  test('O — home_screen.dart ne contient plus _debugConsultationState', () {
    final src = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(src.contains('_debugConsultationState'), isFalse);
    expect(src.contains('Variable de test pour visualiser'), isFalse);
  });
}

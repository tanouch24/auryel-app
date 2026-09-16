import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/wellbeing_ebooks_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/screens/wellbeing_library_screen.dart';
import 'package:auryel/screens/wellbeing_program_screen.dart';
import 'package:auryel/state/wellbeing_ebooks_controller.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });
  final thought = DailyThought(
    id: 1,
    publishDate: DateTime(2026, 9, 16),
    phrase: 'Une vraie pensée pour aujourd’hui.',
    interpretation: 'Une interprétation utile et suffisamment longue.',
    imageAsset: '',
  );

  Future<WellbeingEbooksController> ebooksController() async {
    final api = WellbeingEbooksApi(
      ApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ebooks': [
                {
                  'id': 1,
                  'slug': 'guide',
                  'title': 'Guide réel',
                  'subtitle': 'Un guide Auryel',
                  'description': 'Un contenu réel.',
                  'cover_url': null,
                  'pdf_url': 'https://example.com/guide.pdf',
                  'version': 1,
                  'active': true,
                  'featured': true,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    final controller = WellbeingEbooksController(
      api: api,
      tokenProvider: () async => 'test-token',
    );
    await controller.refresh();
    return controller;
  }

  testWidgets('V1 affiche un contenu du jour et un seul CTA conseiller',
      (tester) async {
    final ebooks = await ebooksController();
    addTearDown(ebooks.dispose);
    final content = ContentRepository(
      embeddedThoughts: DailyThoughtRepository(seed: [thought]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ContentScope(
          repository: content,
          child: WellbeingEbooksScope(
            controller: ebooks,
            child: const WellbeingProgramScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text(thought.phrase), findsOneWidget);
    expect(find.text('Jour 3 sur 30'), findsNothing);
    expect(find.text('0 sur 5 aujourd’hui'), findsNothing);
    expect(find.text('En parler à mon conseiller'), findsOneWidget);
    expect(find.text('Bibliothèque'), findsOneWidget);

  });

  testWidgets('V1 ouvre la bibliothèque unique avec le vrai ebook',
      (tester) async {
    final ebooks = await ebooksController();
    addTearDown(ebooks.dispose);
    final content = ContentRepository(
      embeddedThoughts: DailyThoughtRepository(seed: [thought]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ContentScope(
          repository: content,
          child: WellbeingEbooksScope(
            controller: ebooks,
            child: const WellbeingProgramScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();

    expect(find.byType(WellbeingLibraryScreen), findsOneWidget);
    expect(find.text('Guide réel'), findsOneWidget);
    expect(find.text('Tout'), findsOneWidget);
  });
}

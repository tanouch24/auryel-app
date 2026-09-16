import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/exercise.dart';
import 'package:auryel/screens/exercise_detail_screen.dart';
import 'package:auryel/screens/wellbeing_library_screen.dart';

Map<String, dynamic> _exercise(String category, int index) => {
  'id': 'exercise-$category-$index',
  'slug': '$category-$index',
  'title': 'Pratique ${index + 1}',
  'category': category,
  'description': 'Une pratique guidée pour prendre un temps pour soi.',
  'duration_seconds': 180,
  'level': 'Débutant',
  'steps': [
    {
      'order': 1,
      'title': 'S’installer',
      'instruction': 'Trouve une position confortable.',
      'seconds': 30,
    },
  ],
  'precautions': '',
  'sort_order': index,
  'version': 1,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Exercise parse ses champs et rejette une étape malformée', () {
    final exercise = Exercise.tryFromJson(_exercise('breathing', 0));
    expect(exercise, isNotNull);
    expect(exercise!.categoryLabel, 'Respiration');
    expect(exercise.steps.single.seconds, 30);
    expect(
      Exercise.tryFromJson({..._exercise('breathing', 0), 'steps': []}),
      isNull,
    );
    expect(ExerciseStep.tryFromJson({'order': 1, 'title': 'x'}), isNull);
  });

  test(
    'ContentApi charge 50 exercices et ignore une entrée invalide',
    () async {
      final all = [
        for (final category in [
          'breathing',
          'relaxation',
          'stretching',
          'mobility',
          'sleep',
        ])
          for (var i = 0; i < 10; i++) _exercise(category, i),
        {'broken': true},
      ];
      final api = ContentApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({'exercises': all}),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      final result = await api.exercises(bearer: 'test-token');
      expect(result.ok, isTrue);
      expect(result.exercises, hasLength(50));
      expect(
        result.exercises.where((e) => e.category == 'sleep'),
        hasLength(10),
      );
    },
  );

  test(
    'ContentRepository conserve le catalogue exercices dans son cache dédié',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = ContentRepository(
        api: ContentApi(
          ApiClient(
            baseUrl: 'http://test.local',
            httpClient: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'exercises': [_exercise('mobility', 0)],
                }),
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
        ),
        tokenProvider: () async => 'token',
        prefs: prefs,
      );
      expect((await repository.exercises()).single.category, 'mobility');
      expect(prefs.getString('auryel.content.exercises.v1'), isNotNull);
      expect(prefs.getString('auryel.content.meditations.v1'), isNull);
    },
  );

  testWidgets('catalogue affiche les catégories françaises et ouvre la fiche', (
    tester,
  ) async {
    final repository = ContentRepository(
      api: ContentApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'exercises': [_exercise('breathing', 0), _exercise('sleep', 1)],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
      tokenProvider: () async => 'token',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ContentScope(
          repository: repository,
          child: const WellbeingLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Respiration'), findsOneWidget);
    expect(find.text('Pratique 1'), findsOneWidget);
    expect(find.text('/50'), findsNothing);
    await tester.tap(find.text('Pratique 1'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseSessionScreen), findsOneWidget);
  });
}

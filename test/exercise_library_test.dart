import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/content_api.dart';
import 'package:auryel/data/content_repository.dart';
import 'package:auryel/data/daily_exercise_session.dart';
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
  'image_url': index == 0
      ? 'https://r2.example.test/exercise-images/$category-${index}_01.webp'
      : null,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('la séance quotidienne est stable, distincte et équilibrée', () {
    final source = [
      for (final category in ['breathing', 'relaxation', 'stretching', 'mobility', 'sleep'])
        for (var i = 0; i < 10; i++)
          Exercise.tryFromJson(_exercise(category, i))!,
    ];
    final day1 = dailyExerciseSession(source, day: DateTime(2026, 9, 17));
    final day1Again = dailyExerciseSession(source, day: DateTime(2026, 9, 17));
    final day2 = dailyExerciseSession(source, day: DateTime(2026, 9, 18));
    expect(day1, orderedEquals(day1Again));
    expect(day1, hasLength(5));
    expect(day1.map((e) => e.category).toSet(), hasLength(5));
    expect(day2.map((e) => e.slug), isNot(orderedEquals(day1.map((e) => e.slug))));
  });

  test('Exercise parse ses champs et rejette une étape malformée', () {
    final exercise = Exercise.tryFromJson(_exercise('breathing', 0));
    expect(exercise, isNotNull);
    expect(exercise!.categoryLabel, 'Respiration');
    expect(exercise.steps.single.seconds, 30);
    expect(exercise.imageUrl, contains('exercise-images/breathing-0_01.webp'));
    expect(
      Exercise.tryFromJson({..._exercise('breathing', 0), 'image_url': null})
          ?.imageUrl,
      isNull,
    );
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

  testWidgets('séance du jour affiche cinq exercices et ouvre la fiche', (
    tester,
  ) async {
    final repository = ContentRepository(
      api: ContentApi(
        ApiClient(
          baseUrl: 'http://test.local',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'exercises': [
                  for (final category in ['breathing', 'relaxation', 'stretching', 'mobility', 'sleep'])
                    _exercise(category, 0),
                  for (final category in ['breathing', 'relaxation', 'stretching', 'mobility', 'sleep'])
                    _exercise(category, 1),
                ],
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
    expect(find.text('Ta séance Bien-être du jour'), findsOneWidget);
    expect(find.text('Commencer ma séance'), findsOneWidget);
    expect(find.text('Pratique 1'), findsAtLeastNWidgets(1));
    expect(find.byType(Image), findsAtLeastNWidgets(1));
    expect(find.text('/50'), findsNothing);
    await tester.tap(find.text('Pratique 1').first);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    final detailImageFrame = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(detailImageFrame.aspectRatio, closeTo(4 / 5, 0.001));
    await tester.scrollUntilVisible(
      find.text('Commencer'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Commencer'), findsOneWidget);
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseSessionScreen), findsOneWidget);
  });

  testWidgets(
    'méditations charge le catalogue à l’ouverture après disponibilité auth',
    (tester) async {
      var meditationCalls = 0;
      final repository = ContentRepository(
        api: ContentApi(
          ApiClient(
            baseUrl: 'http://test.local',
            httpClient: MockClient((request) async {
              if (request.url.queryParameters['media'] == 'video') {
                meditationCalls++;
                return http.Response(
                  jsonEncode({'meditation_videos': []}),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response(
                jsonEncode({'exercises': [_exercise('breathing', 0)]}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
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
      expect(meditationCalls, 0);

      await tester.tap(find.text('Méditations'));
      await tester.pumpAndSettle();

      expect(meditationCalls, 1);
      expect(find.text('Aucune vidéo n’est disponible pour le moment.'),
          findsOneWidget);
    },
  );
}

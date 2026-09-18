import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/content_recommendation.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/screens/chat_screen.dart';

void main() {
  test('recommendation ebook parse les champs canoniques', () {
    final value = ContentRecommendation.tryFromJson({
      'recommendation_id': 'rec-1',
      'content_type': 'ebook',
      'content_id': '42',
      'title': 'Le sommeil sans combat',
      'cover_url': 'https://cdn.example/cover.webp',
      'pdf_url': 'https://cdn.example/book.pdf',
    });
    expect(value.type, 'ebook');
    expect(value.id, '42');
    expect(value.title, 'Le sommeil sans combat');
    expect(value.coverUrl, contains('cover.webp'));
  });

  test('metadata invalide est ignorée par le message historique', () {
    final value = ConsultationMessageDto.fromJson({
      'role': 'assistant',
      'content': 'Réponse',
      'recommendation': {'content_type': 'ebook', 'content_id': 'unknown'},
    });
    expect(value.recommendation, isNull);
  });

  test('une réponse normale sans recommendation ne crée aucune carte', () {
    final value = ConsultationMessageDto.fromJson({
      'role': 'assistant',
      'content': 'Je suis là, prends ton temps.',
      'recommendation': null,
    });
    expect(value.recommendation, isNull);
    expect(value.content, contains('prends ton temps'));
  });

  test('PDF absent et contrat invalide restent fail-safe', () {
    final value = ContentRecommendation.tryFromJson({
      'recommendation_id': 'rec-no-pdf',
      'content_type': 'ebook',
      'content_id': 'ebook-1',
      'title': 'Titre canonique',
    });
    expect(value.pdfUrl, isNull);
    expect(
      () => ContentRecommendation.tryFromJson({
        'recommendation_id': 'rec-invalid',
        'content_type': 'ebook',
        'content_id': '',
        'title': 'Titre',
      }),
      throwsFormatException,
    );
  });

  test('exercice réel est reconstructible pour le flow existant', () {
    final value = ContentRecommendation.tryFromJson({
      'recommendation_id': 'rec-2',
      'content_type': 'exercise',
      'content_id': 'ex-1',
      'title': 'Respirer lentement',
      'category': 'breathing',
      'description': 'Un exercice court.',
      'duration_seconds': 60,
      'level': 'easy',
      'precautions': '',
      'sort_order': 1,
      'version': 1,
      'steps': [
        {
          'order': 1,
          'title': 'Inspirer',
          'instruction': 'Doucement',
          'seconds': 4,
        },
      ],
    });
    expect(value.asExercise(), isNotNull);
  });

  testWidgets('la carte native affiche les actions canoniques', (tester) async {
    final recommendation = ContentRecommendation.tryFromJson({
      'recommendation_id': '11111111-1111-4111-8111-111111111111',
      'content_type': 'ebook',
      'content_id': 'ebook-1',
      'title': 'Le sommeil sans combat',
      'cover_url': 'https://example.test/cover.webp',
      'pdf_url': 'https://example.test/book.pdf',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecommendationCard(
            recommendation: recommendation,
            onOpen: () {},
            onDownload: () {},
            busy: false,
          ),
        ),
      ),
    );

    expect(find.text('Le sommeil sans combat'), findsOneWidget);
    expect(find.text('Lire dans Auryel'), findsOneWidget);
    expect(find.text('Télécharger le PDF'), findsOneWidget);
  });

  testWidgets('les cartes méditation et exercice exposent le bon flow', (
    tester,
  ) async {
    var opened = 0;
    final meditation = ContentRecommendation.tryFromJson({
      'recommendation_id': '22222222-2222-4222-8222-222222222222',
      'content_type': 'meditation',
      'content_id': 'med-1',
      'title': 'Retour au calme',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecommendationCard(
            recommendation: meditation,
            onOpen: () => opened++,
            onDownload: () => fail('une méditation ne télécharge pas de PDF'),
            busy: false,
          ),
        ),
      ),
    );
    expect(find.text('Écouter'), findsOneWidget);
    expect(find.text('Télécharger le PDF'), findsNothing);
    await tester.tap(find.text('Écouter'));
    expect(opened, 1);

    final exercise = ContentRecommendation.tryFromJson({
      'recommendation_id': '33333333-3333-4333-8333-333333333333',
      'content_type': 'exercise',
      'content_id': 'ex-1',
      'title': 'Respirer lentement',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecommendationCard(
            recommendation: exercise,
            onOpen: () => opened++,
            onDownload: () => fail('un exercice ne télécharge pas de PDF'),
            busy: false,
          ),
        ),
      ),
    );
    expect(find.text("Faire l'exercice"), findsOneWidget);
    await tester.tap(find.text("Faire l'exercice"));
    expect(opened, 2);
  });

  testWidgets('une nouvelle recommandation méditation navigue sans lecteur', (
    tester,
  ) async {
    var opened = 0;
    final recommendation = ContentRecommendation.tryFromJson({
      'recommendation_id': '55555555-5555-4555-8555-555555555555',
      'content_type': 'meditation',
      'content_id': 'video-med-1',
      'title': 'Déposer la journée avant de dormir',
      'image_url': 'https://example.test/thumb.webp',
      'navigation_only': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecommendationCard(
            recommendation: recommendation,
            onOpen: () => opened++,
            onDownload: () => fail('une méditation ne télécharge pas de PDF'),
            busy: false,
          ),
        ),
      ),
    );

    expect(recommendation.audioUrl, isNull);
    expect(recommendation.navigationOnly, isTrue);
    expect(find.text('Voir les méditations'), findsOneWidget);
    expect(find.text('Écouter'), findsNothing);
    await tester.tap(find.text('Voir les méditations'));
    expect(opened, 1);
  });

  testWidgets('la carte ebook reste utilisable sur petite largeur', (
    tester,
  ) async {
    final recommendation = ContentRecommendation.tryFromJson({
      'recommendation_id': '44444444-4444-4444-8444-444444444444',
      'content_type': 'ebook',
      'content_id': 'ebook-1',
      'title':
          'Un titre volontairement assez long pour tester le retour à la ligne',
    });
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(280, 700)),
        child: MaterialApp(
          home: Scaffold(
            body: RecommendationCard(
              recommendation: recommendation,
              onOpen: () {},
              onDownload: () {},
              busy: true,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Télécharger le PDF'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

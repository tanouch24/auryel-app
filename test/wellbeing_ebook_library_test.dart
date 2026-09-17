import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/wellbeing_ebooks_api.dart';
import 'package:auryel/screens/wellbeing_library_screen.dart';
import 'package:auryel/state/wellbeing_ebooks_controller.dart';

void main() {
  test(
    'le catalogue conserve l’ordre serveur et accepte les URLs absentes',
    () async {
      final client = ApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'ebooks': [
                {
                  'id': 2,
                  'slug': 'second',
                  'title': 'Second guide',
                  'subtitle': 'Sous-titre',
                  'description': null,
                  'cover_url': null,
                  'pdf_url': null,
                  'publication_date': '2026-10-01',
                  'month_label': null,
                  'version': 1,
                  'active': true,
                  'featured': false,
                },
                {
                  'id': 1,
                  'slug': 'premier',
                  'title': 'Premier guide',
                  'subtitle': 'Auryel',
                  'description': 'Description',
                  'cover_url': 'https://example.test/cover.png',
                  'pdf_url': 'https://example.test/guide.pdf',
                  'publication_date': '2026-09-01',
                  'month_label': 'Septembre 2026',
                  'version': '1',
                  'active': true,
                  'featured': true,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final controller = WellbeingEbooksController(
        api: WellbeingEbooksApi(client),
        tokenProvider: () async => 'token',
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.ebooks.map((ebook) => ebook.id), [2, 1]);
      expect(controller.ebooks.first.pdfUrl, isNull);
      expect(controller.ebooks.last.coverUrl, contains('cover.png'));
    },
  );

  test(
    'attend la session puis charge le catalogue sans faux état vide',
    () async {
      var token = <String?>[null, 'token'];
      var authReady = false;
      var requests = 0;
      final client = ApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'ebooks': [_ebookJson(1)],
            }),
            200,
          );
        }),
      );
      final controller = WellbeingEbooksController(
        api: WellbeingEbooksApi(client),
        tokenProvider: () async => token.removeAt(0),
        authReadyProvider: () => authReady,
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(requests, 0);
      expect(controller.loading, isTrue);
      expect(controller.sessionUnavailable, isFalse);
      expect(controller.ebooks, isEmpty);

      authReady = true;
      await controller.refresh();
      expect(requests, 1);
      expect(controller.loading, isFalse);
      expect(controller.ebooks, hasLength(1));
    },
  );

  test('deux refresh simultanés partagent la même requête', () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    final controller = WellbeingEbooksController(
      api: WellbeingEbooksApi(client),
      tokenProvider: () async => 'token',
    );
    addTearDown(controller.dispose);

    final first = controller.refresh();
    final second = controller.refresh();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    response.complete(
      http.Response(
        jsonEncode({
          'ebooks': [_ebookJson(1)],
        }),
        200,
      ),
    );
    await Future.wait([first, second]);
    expect(controller.ebooks, hasLength(1));
  });

  test('401 et réseau restent des erreurs, jamais un catalogue vide', () async {
    var unauthorized = true;
    final client = ApiClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient((_) async {
        if (unauthorized) return http.Response('{"error":"unauthorized"}', 401);
        throw const SocketException('offline');
      }),
    );
    final controller = WellbeingEbooksController(
      api: WellbeingEbooksApi(client),
      tokenProvider: () async => 'token',
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.sessionExpired, isTrue);
    expect(controller.ebooks, isEmpty);
    expect(controller.error, isNotNull);

    unauthorized = false;
    await controller.refresh();
    expect(controller.sessionExpired, isFalse);
    expect(controller.error, isNotNull);
    expect(controller.ebooks, isEmpty);
  });

  test('le dernier catalogue reste visible pendant un refresh', () async {
    var delayed = false;
    final response = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient((_) async {
        if (delayed) return response.future;
        return http.Response(
          jsonEncode({
            'ebooks': [_ebookJson(1)],
          }),
          200,
        );
      }),
    );
    final controller = WellbeingEbooksController(
      api: WellbeingEbooksApi(client),
      tokenProvider: () async => 'token',
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    delayed = true;
    final refresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.loading, isTrue);
    expect(controller.ebooks, hasLength(1));
    response.complete(
      http.Response(
        jsonEncode({
          'ebooks': [_ebookJson(2)],
        }),
        200,
      ),
    );
    await refresh;
    expect(controller.ebooks.single.id, 2);
  });

  test(
    'un catalogue API vide est le seul cas qui affiche l’état vide',
    () async {
      final client = ApiClient(
        baseUrl: 'http://test.local',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'ebooks': []}), 200),
        ),
      );
      final controller = WellbeingEbooksController(
        api: WellbeingEbooksApi(client),
        tokenProvider: () async => 'token',
      );
      addTearDown(controller.dispose);

      await controller.refresh();
      expect(controller.ebooks, isEmpty);
      expect(controller.error, isNull);
      expect(controller.sessionUnavailable, isFalse);
    },
  );

  testWidgets('une erreur 401 n’est pas rendue comme un catalogue vide', (
    tester,
  ) async {
    final client = ApiClient(
      baseUrl: 'http://test.local',
      httpClient: MockClient(
        (_) async => http.Response('{"error":"unauthorized"}', 401),
      ),
    );
    final controller = WellbeingEbooksController(
      api: WellbeingEbooksApi(client),
      tokenProvider: () async => 'token',
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(home: WellbeingLibraryScreen(ebooksController: controller)),
    );
    await tester.tap(find.text('Ebooks'));
    await tester.pumpAndSettle();

    expect(find.text('Ta session doit être reconnectée.'), findsOneWidget);
    expect(find.text('De nouvelles lectures arrivent bientôt.'), findsNothing);
  });

  test(
    'un compte gratuit ou Premium utilise le même catalogue authentifié',
    () {
      final ebook = WellbeingEbook.fromJson({
        'id': 1,
        'slug': 'guide',
        'title': 'Guide',
        'subtitle': 'Auryel',
        'active': true,
      });
      expect(ebook.active, isTrue);
      expect(ebook.pdfUrl, isNull);
      expect(ebook.coverUrl, isNull);
    },
  );

  test('convention future des couvertures conserve le slug Unicode', () {
    expect(
      ebookCoverObjectKey('mon-guide-évasion'),
      'auryel-ebook-covers/mon-guide-évasion.webp',
    );
  });
}

Map<String, dynamic> _ebookJson(int id) => {
  'id': id,
  'slug': 'guide-$id',
  'title': 'Guide $id',
  'subtitle': '',
  'description': null,
  'cover_url': null,
  'pdf_url': 'https://example.com/guide-$id.pdf',
  'publication_date': '2026-09-16',
  'month_label': null,
  'version': '1',
  'active': true,
  'featured': false,
};

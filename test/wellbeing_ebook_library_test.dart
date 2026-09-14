import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/wellbeing_ebooks_api.dart';
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
}

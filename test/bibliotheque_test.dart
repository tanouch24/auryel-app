import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/bibliotheque_screen.dart';
import 'package:auryel/state/auth_controller.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _t(String id, {String key = 'le_fou'}) => {
  'tirage_id': id,
  'card_keys': [key, 'la_lune', 'le_soleil'],
  'cards': [
    {'key': key, 'name': 'NOM-$id-1', 'interpretation': 'i1'},
    {'key': 'la_lune', 'name': 'NOM-$id-2', 'interpretation': 'i2'},
    {'key': 'le_soleil', 'name': 'NOM-$id-3', 'interpretation': 'i3'},
  ],
  'combined_interpretation': 'LECTURE-$id',
  'advisor_id': 'maia',
  'created_at': '2026-08-31T09:00:00Z',
};

typedef _Env = ({AuthController auth, List<Uri> urls});

_Env _env(
  Future<http.Response> Function(Uri url, int call) handler, {
  String? token = 'tok',
}) {
  final urls = <Uri>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      urls.add(req.url);
      if (req.url.path == '/api/tirages') return handler(req.url, urls.length);
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  return (auth: auth, urls: urls);
}

Future<void> _pump(WidgetTester tester, AuthController auth) =>
    tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: const MaterialApp(home: BibliothequeScreen()),
      ),
    );

void main() {
  testWidgets('A. loading -> spinner puis contenu', (tester) async {
    final e = _env(
      (_, _) async => _json({
        'tirages': [_t('a')],
        'next_cursor': null,
      }),
    );
    await _pump(tester, e.auth); // 1re frame : état loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Mon parcours'), findsOneWidget);
    expect(find.text('LECTURE-a'), findsOneWidget);
  });

  testWidgets('B. liste vide -> "Tes tirages apparaîtront ici."', (
    tester,
  ) async {
    final e = _env(
      (_, _) async => _json({'tirages': <dynamic>[], 'next_cursor': null}),
    );
    await _pump(tester, e.auth);
    await tester.pumpAndSettle();
    expect(find.text('Tes tirages apparaîtront ici.'), findsOneWidget);
  });

  testWidgets('C/D/E. un tirage : 3 noms dans l\'ordre + combined', (
    tester,
  ) async {
    final e = _env(
      (_, _) async => _json({
        'tirages': [_t('z')],
        'next_cursor': null,
      }),
    );
    await _pump(tester, e.auth);
    await tester.pumpAndSettle();
    expect(find.text('NOM-z-1 · NOM-z-2 · NOM-z-3'), findsOneWidget);
    expect(find.text('LECTURE-z'), findsOneWidget);
    expect(find.text('Avec maia'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3)); // vignettes
  });

  testWidgets(
    'F. plusieurs tirages : ordre = ordre reçu (newest-first serveur)',
    (tester) async {
      final e = _env(
        (_, _) async => _json({
          'tirages': [_t('n3'), _t('n2'), _t('n1')],
          'next_cursor': null,
        }),
      );
      await _pump(tester, e.auth);
      await tester.pumpAndSettle();
      final y3 = tester.getTopLeft(find.text('LECTURE-n3')).dy;
      final y2 = tester.getTopLeft(find.text('LECTURE-n2')).dy;
      final y1 = tester.getTopLeft(find.text('LECTURE-n1')).dy;
      expect(y3 < y2 && y2 < y1, isTrue);
    },
  );

  testWidgets(
    'G/H/I. next_cursor -> "Afficher plus" -> append -> plus de bouton',
    (tester) async {
      final e = _env((url, call) async {
        if (call == 1) {
          return _json({
            'tirages': [_t('p1')],
            'next_cursor': 'cur-1',
          });
        }
        // page 2 : before doit être le curseur
        expect(url.queryParameters['before'], 'cur-1');
        return _json({
          'tirages': [_t('p2')],
          'next_cursor': null,
        });
      });
      await _pump(tester, e.auth);
      await tester.pumpAndSettle();

      expect(find.text('Afficher plus'), findsOneWidget);
      expect(find.text('LECTURE-p1'), findsOneWidget);
      expect(find.text('LECTURE-p2'), findsNothing);

      await tester.tap(find.text('Afficher plus'));
      await tester.pumpAndSettle();

      expect(find.text('LECTURE-p1'), findsOneWidget); // conservé (append)
      expect(find.text('LECTURE-p2'), findsOneWidget);
      expect(find.text('Afficher plus'), findsNothing); // cursor == null
    },
  );

  testWidgets('J. erreur réseau -> "Réessayer" -> recharge OK', (tester) async {
    final e = _env((_, call) async {
      if (call == 1) throw http.ClientException('down');
      return _json({
        'tirages': [_t('ok')],
        'next_cursor': null,
      });
    });
    await _pump(tester, e.auth);
    await tester.pumpAndSettle();

    expect(
      find.text('Impossible de charger ton parcours pour le moment.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('LECTURE-ok'), findsOneWidget);
  });

  testWidgets('K. refresh (RefreshIndicator) recharge depuis le début', (
    tester,
  ) async {
    var call = 0;
    final e = _env((_, _) async {
      call++;
      return _json({
        'tirages': [_t('r$call')],
        'next_cursor': null,
      });
    });
    await _pump(tester, e.auth);
    await tester.pumpAndSettle();
    expect(find.text('LECTURE-r1'), findsOneWidget);

    await tester.fling(find.text('Mon parcours'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('LECTURE-r2'), findsOneWidget);
    expect(find.text('LECTURE-r1'), findsNothing);
  });

  testWidgets('token absent -> message reconnexion', (tester) async {
    final e = _env(
      (_, _) async => _json({'tirages': <dynamic>[], 'next_cursor': null}),
      token: null,
    );
    await _pump(tester, e.auth);
    await tester.pumpAndSettle();
    expect(
      find.text('Reconnecte-toi pour retrouver ton parcours.'),
      findsOneWidget,
    );
  });
}

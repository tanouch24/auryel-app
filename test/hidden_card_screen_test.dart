import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/mini_game_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/hidden_card_screen.dart';
import 'package:auryel/state/auth_controller.dart';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

AuthController _auth() {
  final client = ApiClient(
    httpClient: MockClient((_) async => _json({})),
    baseUrl: 'http://test.local',
  );
  return AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
}

Widget _host(MiniGameApi api, {Random? random}) => AuthScope(
  controller: _auth(),
  child: MaterialApp(home: HiddenCardScreen(random: random, miniGameApi: api)),
);

void main() {
  testWidgets('ouvre une session avec game_key=hidden_card', (t) async {
    var startCalled = false;
    final api = MiniGameApi(
      ApiClient(
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/start')) {
            startCalled = true;
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['game_key'], 'hidden_card');
            return _json({'session_id': 's-1', 'game_key': 'hidden_card'});
          }
          return _json({'status': 'completed', 'awarded': false});
        }),
        baseUrl: 'http://test.local',
      ),
    );
    await t.pumpWidget(_host(api, random: Random(2)));
    await t.pump();
    expect(startCalled, isTrue);
  });

  testWidgets(
    'choisit une carte -> finish appelé, résultat affiché — récompense la '
    'PARTICIPATION (manche terminée), pas la bonne réponse',
    (t) async {
      var finishCalled = false;
      final api = MiniGameApi(
        ApiClient(
          httpClient: MockClient((req) async {
            if (req.url.path.endsWith('/start')) {
              return _json({'session_id': 's-1', 'game_key': 'hidden_card'});
            }
            finishCalled = true;
            return _json({
              'status': 'completed',
              'outcome': 'rewarded',
              'awarded': true,
              'stars_awarded': 15,
              'new_balance': 15,
            });
          }),
          baseUrl: 'http://test.local',
        ),
      );
      await t.pumpWidget(_host(api, random: Random(2)));
      await t.pump();
      // Laisse passer la révélation + le mélange (900ms + 500ms).
      await t.pump(const Duration(milliseconds: 1500));

      await t.tap(find.byIcon(PhosphorIconsRegular.question).first);
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();

      expect(finishCalled, isTrue);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Tu as gagné 15 ⭐.'), findsOneWidget);
      // Jamais de vocabulaire casino/pari.
      expect(find.textContaining('mise'), findsNothing);
      expect(find.textContaining('chance'), findsNothing);
      expect(find.textContaining('pari'), findsNothing);
    },
  );

  testWidgets('tap avant la fin du mélange (encore en révélation) -> ignoré, '
      'jamais de finish prématuré', (t) async {
    var finishCalled = false;
    final api = MiniGameApi(
      ApiClient(
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/start')) {
            return _json({'session_id': 's-1', 'game_key': 'hidden_card'});
          }
          finishCalled = true;
          return _json({'status': 'completed', 'awarded': false});
        }),
        baseUrl: 'http://test.local',
      ),
    );
    await t.pumpWidget(_host(api, random: Random(2)));
    await t.pump();
    // Encore en phase de révélation : les cartes ne sont pas cliquables.
    await t.tap(find.byIcon(PhosphorIconsRegular.question).first, warnIfMissed: false);
    await t.pump();

    expect(finishCalled, isFalse);
  });
}

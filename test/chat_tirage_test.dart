import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _ok({String reply = 'Je te vois.'}) => {
  'reply': reply,
  'consultation': {
    'id': 'c-1',
    'advisor_id': 'maia',
    'started_at': '2026-08-31T10:00:00Z',
    'expires_at': '2026-08-31T12:00:00Z',
    'seconds_remaining': 7000,
    'credit_source': 'monthly',
    'opened_now': true,
  },
  'quota': {
    'is_premium': true,
    'monthly_limit': 4,
    'monthly_used': 1,
    'monthly_remaining': 3,
    'earned_available': 0,
    'period_start': '2026-08-01T00:00:00Z',
    'period_end': '2026-09-01T00:00:00Z',
  },
};

typedef _Env = ({AuthController auth, List<Map<String, dynamic>> msgBodies});

_Env _env(Future<http.Response> Function(int call) handler) {
  final bodies = <Map<String, dynamic>>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/consultation/message') {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return handler(bodies.length);
      }
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  return (auth: auth, msgBodies: bodies);
}

Future<void> _pump(
  WidgetTester tester,
  AuthController auth, {
  String? tirageId,
}) {
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u',
      selectedAdvisor: 'Maïa',
      firstName: 'N',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'x',
      portraitFeedback: 'y',
      onboardingCompleted: true,
    ),
  );
  return tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: AuryelStateScope(
        state: state,
        child: MaterialApp(
          home: ChatScreen(
            advisor: advisorByNameOrNull('Maïa')!,
            tirageId: tirageId,
          ),
        ),
      ),
    ),
  );
}

Future<void> _send(WidgetTester tester, String msg) async {
  await tester.enterText(find.byType(TextField), msg);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  // 1re ouverture -> dialogue « consultation de 2 h »
  if (find.text('Commencer').evaluate().isNotEmpty) {
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('A. sans tirageId : body historique {"message": ...}', (
    tester,
  ) async {
    final e = _env((_) async => _json(_ok()));
    await _pump(tester, e.auth); // pas de tirageId
    await tester.enterText(find.byType(TextField), 'bonjour');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await _confirm(tester);
    await tester.pumpAndSettle();

    expect(e.msgBodies.single, {'message': 'bonjour'});
  });

  testWidgets(
    'B/C. avec tirageId : 1er POST le contient, 2e POST ne l\'a plus',
    (tester) async {
      final e = _env((_) async => _json(_ok()));
      await _pump(tester, e.auth, tirageId: 'tir-42');

      await tester.enterText(find.byType(TextField), 'premier');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      await _confirm(tester);
      await tester.pumpAndSettle();

      expect(e.msgBodies.length, 1);
      expect(e.msgBodies[0], {'message': 'premier', 'tirage_id': 'tir-42'});

      await _send(tester, 'deuxième');
      expect(e.msgBodies.length, 2);
      expect(e.msgBodies[1], {'message': 'deuxième'}); // plus de tirage_id
    },
  );

  testWidgets('D. 1er POST réseau KO : retry conserve tirage_id', (
    tester,
  ) async {
    final e = _env((call) async {
      if (call == 1) throw http.ClientException('boom');
      return _json(_ok());
    });
    await _pump(tester, e.auth, tirageId: 'tir-net');

    await tester.enterText(find.byType(TextField), 'msg');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await _confirm(tester);
    await tester.pumpAndSettle();

    expect(e.msgBodies[0], {'message': 'msg', 'tirage_id': 'tir-net'});
    // retry
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(e.msgBodies.length, 2);
    expect(e.msgBodies[1], {'message': 'msg', 'tirage_id': 'tir-net'});
  });

  testWidgets('E. 1er POST 5xx : retry conserve tirage_id', (tester) async {
    final e = _env((call) async => call == 1 ? _json({}, 503) : _json(_ok()));
    await _pump(tester, e.auth, tirageId: 'tir-5xx');

    await tester.enterText(find.byType(TextField), 'msg');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await _confirm(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(e.msgBodies.length, 2);
    expect(e.msgBodies[1]['tirage_id'], 'tir-5xx');
  });

  testWidgets('F. 402 no_credit : tirage_id reste pending', (tester) async {
    final e = _env(
      (_) async => _json({
        'error': 'no_credit',
        'consultation': null,
        'quota': {
          'is_premium': true,
          'monthly_limit': 4,
          'monthly_used': 4,
          'monthly_remaining': 0,
          'earned_available': 0,
          'period_start': '2026-08-01T00:00:00Z',
          'period_end': '2026-09-01T00:00:00Z',
        },
      }, 402),
    );
    await _pump(tester, e.auth, tirageId: 'tir-402');

    await tester.enterText(find.byType(TextField), 'msg');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await _confirm(tester);
    await tester.pumpAndSettle();

    expect(e.msgBodies[0], {'message': 'msg', 'tirage_id': 'tir-402'});
    final st = tester.state(find.byType(ChatScreen));
    expect((st as dynamic).debugPendingTirageId, 'tir-402');
  });

  testWidgets('G. 404 tirage_not_found : message contrôlé, pas de crash', (
    tester,
  ) async {
    final e = _env(
      (call) async =>
          call == 1 ? _json({'error': 'tirage_not_found'}, 404) : _json(_ok()),
    );
    await _pump(tester, e.auth, tirageId: 'tir-gone');

    await tester.enterText(find.byType(TextField), 'msg');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await _confirm(tester);
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Ce tirage n'est plus disponible"),
      findsOneWidget,
    );
    final st = tester.state(find.byType(ChatScreen));
    expect((st as dynamic).debugPendingTirageId, isNull);

    // On peut réessayer : le 2e POST part sans tirage_id et réussit.
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(e.msgBodies.last, {'message': 'msg'});
  });
}

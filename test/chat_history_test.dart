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
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Réponse POST /message minimale (sert aux tests « chat toujours utilisable »).
Map<String, dynamic> _okMessage({String reply = 'Réponse conseiller'}) => {
      'reply': reply,
      'consultation': {
        'id': 'c-live',
        'advisor_id': 'maia',
        'started_at': '2026-08-31T10:00:00Z',
        'expires_at': '2999-01-01T00:00:00Z',
        'seconds_remaining': 7000,
        'credit_source': 'monthly',
        'opened_now': false,
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

typedef _Env = ({
  AuthController auth,
  ConsultationController consultation,
  List<String> getMessagesCalls,
  List<Map<String, dynamic>> postBodies,
});

/// [messagesHandler] répond au `GET /api/consultation/messages`.
_Env _env(
  Future<http.Response> Function(int call) messagesHandler, {
  String? token = 'tok',
}) {
  final getCalls = <String>[];
  final postBodies = <Map<String, dynamic>>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/consultation/messages' && req.method == 'GET') {
        getCalls.add(path);
        return messagesHandler(getCalls.length);
      }
      if (path == '/api/consultation/message' && req.method == 'POST') {
        postBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json(_okMessage());
      }
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
  final consultation =
      ConsultationController(api: ConsultationApi(client), auth: auth);
  // Session active injectée (id = c-live), expiration lointaine.
  consultation.updateFromMessageResponse(
    ConsultationMessageResponse.fromJson({
      'reply': 'x',
      'consultation': {
        'id': 'c-live',
        'advisor_id': 'maia',
        'started_at': '2026-08-31T10:00:00Z',
        'expires_at': '2999-01-01T00:00:00Z',
        'seconds_remaining': 7000,
        'credit_source': 'monthly',
      },
      'quota': {
        'is_premium': true,
        'monthly_limit': 4,
        'monthly_used': 1,
        'monthly_remaining': 3,
        'earned_available': 0,
      },
    }),
  );
  addTearDown(consultation.dispose);
  return (
    auth: auth,
    consultation: consultation,
    getMessagesCalls: getCalls,
    postBodies: postBodies,
  );
}

Future<void> _pumpChat(
  WidgetTester tester,
  _Env e, {
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
      controller: e.auth,
      child: ConsultationScope(
        controller: e.consultation,
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
    ),
  );
}

Map<String, dynamic> _history(
  String consultationId,
  List<(String, String)> msgs,
) =>
    {
      'consultation_id': consultationId,
      'messages': [
        for (final (role, content) in msgs)
          {'role': role, 'content': content, 'timestamp': '2026-08-31T10:00:00Z'},
      ],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('DTO ConsultationMessagesResponse.fromJson : parsing + robustesse', () {
    final r = ConsultationMessagesResponse.fromJson(_history('c-1', [
      ('user', 'salut'),
      ('assistant', 'bonjour'),
    ]));
    expect(r.consultationId, 'c-1');
    expect(r.messages.length, 2);
    expect(r.messages.first.isUser, isTrue);
    expect(r.messages[1].isUser, isFalse);
    expect(r.messages.first.timestamp, isA<DateTime>());

    final empty = ConsultationMessagesResponse.fromJson(
        {'consultation_id': null, 'messages': null});
    expect(empty.consultationId, isNull);
    expect(empty.messages, isEmpty);
  });

  testWidgets('reprise avec historique -> anciens messages affichés, dans l’ordre',
      (t) async {
    final e = _env((_) async => _json(_history('c-live', [
          ('user', 'ma première question'),
          ('assistant', 'ma réponse de conseiller'),
          ('user', 'et ensuite ?'),
        ])));
    await _pumpChat(t, e);
    await t.pump();
    await t.pump();

    expect(find.text('ma première question'), findsOneWidget);
    expect(find.text('ma réponse de conseiller'), findsOneWidget);
    expect(find.text('et ensuite ?'), findsOneWidget);

    // Ordre chronologique conservé (haut -> bas).
    final y1 = t.getTopLeft(find.text('ma première question')).dy;
    final y2 = t.getTopLeft(find.text('ma réponse de conseiller')).dy;
    final y3 = t.getTopLeft(find.text('et ensuite ?')).dy;
    expect(y1 < y2, isTrue);
    expect(y2 < y3, isTrue);

    // user = bulle à droite, assistant = bulle à gauche.
    final userAlign = t.widget<Align>(find.ancestor(
      of: find.text('ma première question'),
      matching: find.byType(Align),
    ));
    final assistantAlign = t.widget<Align>(find.ancestor(
      of: find.text('ma réponse de conseiller'),
      matching: find.byType(Align),
    ));
    expect(userAlign.alignment, Alignment.centerRight);
    expect(assistantAlign.alignment, Alignment.centerLeft);
    e.consultation.dispose();
  });

  testWidgets('chargement une seule fois (GET /messages == 1)', (t) async {
    final e = _env((_) async => _json(_history('c-live', [('user', 'x')])));
    await _pumpChat(t, e);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));

    expect(e.getMessagesCalls.length, 1);
    e.consultation.dispose();
  });

  testWidgets('historique vide -> aucun faux historique, invite de départ',
      (t) async {
    final e = _env((_) async => _json(_history('c-live', const [])));
    await _pumpChat(t, e);
    await t.pump();
    await t.pump();

    expect(find.text('Écris ton premier message pour commencer.'), findsOneWidget);
    expect(e.getMessagesCalls.length, 1);
    e.consultation.dispose();
  });

  testWidgets('consultation_id inattendu -> aucun message injecté', (t) async {
    final e = _env((_) async => _json(_history('c-AUTRE', [
          ('user', 'message qui ne doit pas apparaître'),
          ('assistant', 'ni celui-ci'),
        ])));
    await _pumpChat(t, e);
    await t.pump();
    await t.pump();

    expect(find.text('message qui ne doit pas apparaître'), findsNothing);
    expect(find.text('ni celui-ci'), findsNothing);
    expect(find.text('Écris ton premier message pour commencer.'), findsOneWidget);
    e.consultation.dispose();
  });

  testWidgets('erreur réseau historique -> chat toujours utilisable + retry',
      (t) async {
    var call = 0;
    final e = _env((c) async {
      call = c;
      if (c == 1) throw http.ClientException('offline');
      return _json(_history('c-live', [('assistant', 'récupéré au 2e essai')]));
    });
    await _pumpChat(t, e);
    await t.pump();
    await t.pump();

    // Le chat reste utilisable : champ de saisie présent, bandeau retry visible.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    final st = t.state(find.byType(ChatScreen));
    expect((st as dynamic).debugHistoryError, isTrue);

    // On peut envoyer un message malgré l'échec d'historique.
    await t.enterText(find.byType(TextField), 'je continue quand même');
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pump();
    await t.pump();
    expect(e.postBodies.single, {'message': 'je continue quand même'});
    expect(find.text('Réponse conseiller'), findsOneWidget);

    // Retry historique -> 2e GET, messages injectés, bandeau disparu.
    await t.tap(find.text('Réessayer'));
    await t.pump();
    await t.pump();
    expect(e.getMessagesCalls.length, 2);
    expect(find.text('récupéré au 2e essai'), findsOneWidget);
    expect((t.state(find.byType(ChatScreen)) as dynamic).debugHistoryError,
        isFalse);
    expect(call, 2);
    e.consultation.dispose();
  });

  testWidgets('tirage_id inchangé : 1er POST le porte malgré l’historique chargé',
      (t) async {
    final e = _env((_) async => _json(_history('c-live', [
          ('assistant', 'contexte précédent'),
        ])));
    await _pumpChat(t, e, tirageId: 'tir-77');
    await t.pump();
    await t.pump();

    expect(find.text('contexte précédent'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'à propos du tirage');
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pump();
    await t.pump();

    expect(e.postBodies.single, {
      'message': 'à propos du tirage',
      'tirage_id': 'tir-77',
    });
    e.consultation.dispose();
  });
}

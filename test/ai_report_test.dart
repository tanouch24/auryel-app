import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/ai_report_api.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';

// ===========================================================================
// PARTIE J — SIGNALEMENT D'UNE RÉPONSE IA
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _time() => {
  'first_free_remaining_seconds': 0,
  'premium_remaining_seconds': 6000,
  'purchased_remaining_seconds': 0,
  'total_remaining_seconds': 6000,
  'window_active': true,
  'window_expires_at': '2999-01-01T00:05:00Z',
};

Map<String, dynamic> _quota() => {
  'is_premium': true,
  'monthly_limit': 8,
  'monthly_used': 1,
  'monthly_remaining': 7,
  'earned_available': 0,
  'first_free_available': false,
  'period_start': '2026-08-01T00:00:00Z',
  'period_end': '2026-09-01T00:00:00Z',
};

class _Rig {
  _Rig({
    int reportStatus = 200,
    Completer<void>? reportGate,
    String? replyMessageId = 'm-1',
    Map<String, dynamic>? history,
  }) {
    final client = ApiClient(
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/consultation/message') {
          return _json({
            'reply': 'Voici ma réponse de conseiller.',
            'message_id': ?replyMessageId,
            'llm_status': 'ok',
            'consultation': {
              'id': 'c-1',
              'advisor_id': 'selena',
              'started_at': '2026-09-06T10:00:00Z',
              'expires_at': '2026-09-06T12:00:00Z',
              'seconds_remaining': 6000,
              'credit_source': 'time',
              'opened_now': true,
            },
            'quota': _quota(),
            'time': _time(),
          });
        }
        if (p == '/api/consultation/messages') {
          return _json(history ?? {'consultation_id': null, 'messages': []});
        }
        if (p == '/api/app/ai/report') {
          reportBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          if (reportGate != null) await reportGate.future;
          if (reportStatus >= 300) {
            return _json({'error': 'boom'}, reportStatus);
          }
          return _json({'status': 'ok'});
        }
        return _json({}, 404);
      }),
      baseUrl: 'http://test.local',
    );
    aiReportApi = AiReportApi(client);
    auth = AuthController(
      repository: AuthRepository(
        api: AuthApi(client),
        tokenStore: InMemoryTokenStore('tok'),
      ),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
    );
  }

  late final AuthController auth;
  late final AiReportApi aiReportApi;
  final List<Map<String, dynamic>> reportBodies = [];
}

Future<void> _pump(
  WidgetTester t,
  _Rig rig, {
  ConsultationController? consultation,
}) {
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u',
      selectedAdvisor: 'Séléna',
      firstName: 'N',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'x',
      portraitFeedback: 'y',
      onboardingCompleted: true,
    ),
  );
  Widget chat = ChatScreen(
    advisor: advisorByNameOrNull('Séléna')!,
    aiReportApi: rig.aiReportApi,
  );
  if (consultation != null) {
    chat = ConsultationScope(controller: consultation, child: chat);
  }
  return t.pumpWidget(
    AuthScope(
      controller: rig.auth,
      child: AuryelStateScope(
        state: state,
        child: MaterialApp(home: chat),
      ),
    ),
  );
}

/// Session active injectée (id `c-1`) pour tester la reprise d'historique.
ConsultationController _resumableConsultation(_Rig rig) {
  final c = ConsultationController(
    api: rig.auth.consultationApi,
    auth: rig.auth,
  );
  c.updateFromMessageResponse(
    ConsultationMessageResponse.fromJson({
      'reply': 'x',
      'consultation': {
        'id': 'c-1',
        'advisor_id': 'selena',
        'started_at': '2026-09-06T10:00:00Z',
        'expires_at': '2999-01-01T00:00:00Z',
        'seconds_remaining': 6000,
        'credit_source': 'time',
      },
      'quota': _quota(),
      // window_active: false -> aucun Timer.periodic (pas de tick à nettoyer).
      'time': {
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': 6000,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': 6000,
        'window_active': false,
        'window_expires_at': null,
      },
    }),
  );
  return c;
}

/// Envoie un message et obtient une réponse conseiller à l'écran.
Future<void> _sendAndReceive(WidgetTester t) async {
  await t.enterText(find.byType(TextField), 'coucou');
  await t.pump();
  await t.tap(find.byIcon(Icons.send_rounded));
  await t.pumpAndSettle();
  // 1er message -> dialogue de confirmation.
  if (find.text('Commencer').evaluate().isNotEmpty) {
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();
  }
}

Future<void> _openReportSheet(WidgetTester t) async {
  await t.tap(find.byType(PopupMenuButton<String>));
  await t.pumpAndSettle();
  await t.tap(find.text('Signaler cette réponse'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('J1/J2 — « ⋯ » présent UNE fois, sur la réponse conseiller '
      '(jamais sur le message utilisateur)', (t) async {
    final rig = _Rig();
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _sendAndReceive(t);

    expect(find.text('Voici ma réponse de conseiller.'), findsOneWidget);
    expect(find.text('coucou'), findsOneWidget);
    // Un seul bouton d'options -> attaché à la seule réponse conseiller.
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });

  testWidgets(
    'J3/J4/J5 — la feuille s\'ouvre : 4 raisons + commentaire optionnel',
    (t) async {
      final rig = _Rig();
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _sendAndReceive(t);
      await _openReportSheet(t);

      expect(find.text('Signaler cette réponse'), findsOneWidget);
      expect(
        find.textContaining('Ton signalement nous aide à améliorer Auryel'),
        findsOneWidget,
      );
      expect(find.text('Réponse inappropriée'), findsOneWidget);
      expect(find.text('Réponse dangereuse'), findsOneWidget);
      expect(find.text('Réponse trompeuse'), findsOneWidget);
      expect(find.text('Autre'), findsOneWidget);
      expect(find.widgetWithText(TextField, ''), findsWidgets); // champ présent
      expect(find.text('Ajouter un commentaire'), findsOneWidget); // hint
      expect(find.text('Envoyer le signalement'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    },
  );

  testWidgets(
    'J6/J7 — envoi : POST /api/app/ai/report avec raison + '
    'message_id réel + consultation_id + commentaire ; succès -> confirmation',
    (t) async {
      final rig = _Rig();
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _sendAndReceive(t);
      await _openReportSheet(t);

      await t.tap(find.text('Réponse dangereuse'));
      await t.pump();
      await t.enterText(find.byType(TextField).last, 'ça me choque');
      await t.pump();
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();

      expect(rig.reportBodies, hasLength(1));
      expect(rig.reportBodies.single['reason'], 'unsafe');
      // Le contrat backend expose maintenant un message_id stable : la réponse
      // assistant fraîche le porte, il est transmis au signalement.
      expect(rig.reportBodies.single['message_id'], 'm-1');
      expect(
        rig.reportBodies.single['consultation_id'],
        'c-1',
      ); // contexte conservé
      expect(rig.reportBodies.single['comment'], 'ça me choque');

      expect(
        find.text('Signaler cette réponse'),
        findsNothing,
      ); // feuille fermée
      expect(
        find.text('Merci. Ton signalement a bien été transmis.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('J11 — réponse assistant issue de l\'historique : le message_id '
      'du DTO est transmis au signalement', (t) async {
    final rig = _Rig(
      history: {
        'consultation_id': 'c-1',
        'messages': [
          {
            'role': 'assistant',
            'content': 'réponse restaurée',
            'timestamp': '2026-09-06T10:00:00Z',
            'message_id': 'h-9',
            'llm_status': 'ok',
          },
        ],
      },
    );
    addTearDown(rig.auth.dispose);
    final consultation = _resumableConsultation(rig);
    addTearDown(consultation.dispose);
    await _pump(t, rig, consultation: consultation);
    await t.pumpAndSettle();

    expect(find.text('réponse restaurée'), findsOneWidget);
    await _openReportSheet(t);
    await t.tap(find.text('Envoyer le signalement'));
    await t.pumpAndSettle();

    expect(rig.reportBodies.single['message_id'], 'h-9');
    expect(rig.reportBodies.single['consultation_id'], 'c-1');
  });

  testWidgets('J12 — réponse sans message_id (backend ancien) : signalement '
      'encore possible via consultation_id, aucun message_id inventé', (
    t,
  ) async {
    final rig = _Rig(replyMessageId: null);
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _sendAndReceive(t);
    await _openReportSheet(t);

    await t.tap(find.text('Envoyer le signalement'));
    await t.pumpAndSettle();

    expect(rig.reportBodies, hasLength(1));
    expect(rig.reportBodies.single.containsKey('message_id'), isFalse);
    expect(rig.reportBodies.single['consultation_id'], 'c-1');
    expect(
      find.text('Merci. Ton signalement a bien été transmis.'),
      findsOneWidget,
    );
  });

  testWidgets('J13 — le champ commentaire est plafonné à 1000 caractères', (
    t,
  ) async {
    final rig = _Rig();
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _sendAndReceive(t);
    await _openReportSheet(t);

    final field = t.widget<TextField>(find.byType(TextField).last);
    expect(field.maxLength, 1000);
  });

  testWidgets('J8/J10 — erreur serveur : PAS de faux succès, écran stable', (
    t,
  ) async {
    final rig = _Rig(reportStatus: 500);
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _sendAndReceive(t);
    await _openReportSheet(t);

    await t.tap(find.text('Envoyer le signalement'));
    await t.pumpAndSettle();

    expect(
      find.textContaining('Impossible d’envoyer le signalement'),
      findsOneWidget,
    );
    expect(
      find.text('Merci. Ton signalement a bien été transmis.'),
      findsNothing,
    );
    // feuille toujours ouverte, aucune exception, chat intact
    expect(find.text('Signaler cette réponse'), findsOneWidget);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('J9 — double soumission bloquée pendant l\'envoi', (t) async {
    final gate = Completer<void>();
    final rig = _Rig(reportGate: gate);
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _sendAndReceive(t);
    await _openReportSheet(t);

    await t.tap(find.text('Envoyer le signalement'));
    await t.pump();
    // 2e tap pendant que le 1er est en vol
    await t.tap(find.text('Envoi…'));
    await t.pump();

    gate.complete();
    await t.pumpAndSettle();

    expect(rig.reportBodies, hasLength(1));
  });
}

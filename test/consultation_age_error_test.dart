import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/account_api.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/screens/adult_gate.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// LOT CORRECTIF 1 — un 403 d'âge sur l'envoi d'un message consultation NE
// DOIT PAS s'afficher comme « le serveur n'a pas répondu » ni proposer un
// retry : il renvoie vers le parcours 18+ existant (AdultGate), qui refait
// autorité serveur et route vers `needsDob` (age_verification_required) ou
// l'écran bloqué (adult_required). Aucun second système d'âge.
// ===========================================================================

final DateTime _fixedNow = DateTime(2026, 9, 9);

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _profile({String? dob}) => {
  'user_id': 'U',
  'guide': 'selena',
  'prenom': 'Ana',
  'date_naissance': dob,
  'chemin_de_vie': '',
  'signe_zodiaque': '',
};

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _Rig {
  _Rig({
    required int messageStatus,
    required Map<String, dynamic> messageBody,
    required Map<String, dynamic> profileBody,
  }) {
    final client = ApiClient(
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/consultation/message') {
          return _json(messageBody, messageStatus);
        }
        if (p == '/api/consultation/messages') {
          return _json({'consultation_id': null, 'messages': []});
        }
        if (p == '/api/app/profile' && req.method == 'GET') {
          return _json(profileBody);
        }
        return _json({}, 404);
      }),
      baseUrl: 'http://test.local',
    );
    auth = AuthController(
      repository: AuthRepository(
        api: AuthApi(client),
        tokenStore: InMemoryTokenStore('tok'),
      ),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
      accountApi: AccountApi(client),
    );
  }

  late final AuthController auth;
}

Future<void> _pump(WidgetTester t, _Rig rig) {
  // DOB locale ADULTE : prouve que le routage 403 force bien l'autorité
  // serveur (AdultGate.forceServerCheck) au lieu du chemin rapide local.
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u',
      selectedAdvisor: 'Séléna',
      firstName: 'Ana',
      birthDate: DateTime(1990, 1, 1),
      portraitData: 'x',
      portraitFeedback: 'y',
      onboardingCompleted: true,
    ),
  );
  return t.pumpWidget(
    AuthScope(
      controller: rig.auth,
      child: AuryelStateScope(
        state: state,
        child: MaterialApp(
          home: ChatScreen(advisor: advisorByNameOrNull('Séléna')!),
        ),
      ),
    ),
  );
}

Future<void> _sendFirstMessage(WidgetTester t) async {
  await t.enterText(find.byType(TextField), 'coucou');
  await t.pump();
  await t.tap(find.byIcon(Icons.send_rounded));
  await t.pumpAndSettle();
  // 1er message -> confirmation.
  if (find.text('Commencer').evaluate().isNotEmpty) {
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    '403 age_verification_required -> AdultGate (Vérification de l’âge), '
    'jamais « le serveur n’a pas répondu », jamais de retry',
    (t) async {
      final rig = _Rig(
        messageStatus: 403,
        messageBody: {'error': 'age_verification_required'},
        profileBody: _profile(dob: null),
      );
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _sendFirstMessage(t);

      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(AdultGate), findsOneWidget);
      expect(find.text('Vérification de l’âge'), findsOneWidget);
      expect(find.byType(MainNavShell), findsNothing);
      expect(find.textContaining('n’a pas répondu'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    '403 adult_required -> AdultGate écran bloqué (Accès réservé aux adultes)',
    (t) async {
      final minorDob = _iso(DateTime(_fixedNow.year - 14, 1, 1));
      final rig = _Rig(
        messageStatus: 403,
        messageBody: {'error': 'adult_required'},
        profileBody: _profile(dob: minorDob),
      );
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _sendFirstMessage(t);

      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(AdultGate), findsOneWidget);
      expect(find.text('Accès réservé aux adultes'), findsOneWidget);
      expect(find.byType(MainNavShell), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'autre 403 (hors périmètre âge) -> comportement inchangé : erreur '
    'générique + retry, on reste dans le chat',
    (t) async {
      final rig = _Rig(
        messageStatus: 403,
        messageBody: {'error': 'some_other_forbidden'},
        profileBody: _profile(dob: '1990-01-01'),
      );
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _sendFirstMessage(t);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(AdultGate), findsNothing);
      expect(find.textContaining('n’a pas répondu'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    },
  );
}

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
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/advisor_chooser_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

typedef _Env = ({
  AuthController auth,
  AuryelState state,
  List<String> requests,
  List<String> patchBodies,
});

/// Environnement : `AuryelState` branché sur le VRAI `AuthController.syncGuide`
/// (donc `ProfileApi` + `ApiClient` + `MockClient`). Toute requête HTTP est
/// capturée -> on peut prouver « guide seul », « aucun crédit », etc.
_Env _env({
  int patchStatus = 200,
  bool networkError = false,
  String? token = 'tok',
  OnboardingRecord? initial,
  OnboardingRepository? repository,
}) {
  final requests = <String>[];
  final patchBodies = <String>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/app/profile' && req.method == 'PATCH') {
        patchBodies.add(req.body);
        if (networkError) throw http.ClientException('boom');
        return _json({'guide': 'x'}, patchStatus);
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
  final state = AuryelState(
    repository: repository ?? LocalOnboardingRepository(),
    initial:
        initial ??
        const OnboardingRecord(
          userId: 'u-1',
          selectedAdvisor: 'Séléna',
          firstName: 'Nina',
          birthDate: null,
          portraitData: 't',
          portraitFeedback: 'ok',
          onboardingCompleted: true,
        ),
    guideSync: (guideKey) => auth.syncGuide(guide: guideKey),
  );
  return (
    auth: auth,
    state: state,
    requests: requests,
    patchBodies: patchBodies,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // A / B / C — les 10 conseillers, avec spécialité + accroche
  // -------------------------------------------------------------------------
  test('A/B/C. 10 conseillers, chacun avec specialty ET tagline', () {
    expect(kAdvisors.length, 10);
    for (final a in kAdvisors) {
      expect(a.specialty.trim(), isNotEmpty, reason: a.name);
      expect(a.tagline.trim(), isNotEmpty, reason: a.name);
    }
  });

  // -------------------------------------------------------------------------
  // D — changement sans session active
  // -------------------------------------------------------------------------
  test(
    'D. changeAdvisor sans session active -> synced + état à jour',
    () async {
      final e = _env();
      final out = await e.state.changeAdvisor('Luna', 'luna');
      expect(out, AdvisorChangeOutcome.synced);
      expect(e.state.selectedAdvisor, 'Luna');
    },
  );

  test(
    'changeAdvisor vers le conseiller DÉJÀ préféré -> unchanged, aucun appel',
    () async {
      final e = _env();
      final out = await e.state.changeAdvisor('Séléna', 'selena');
      expect(out, AdvisorChangeOutcome.unchanged);
      expect(e.requests, isEmpty);
    },
  );

  // -------------------------------------------------------------------------
  // E — persistance locale (SharedPreferences via le repository)
  // -------------------------------------------------------------------------
  test(
    'E. le changement persiste localement (relecture du repository)',
    () async {
      final repo = LocalOnboardingRepository();
      final e = _env(repository: repo);
      await e.state.changeAdvisor('Maïa', 'maia');

      final reloaded = await repo.load();
      expect(reloaded?.selectedAdvisor, 'Maïa');
    },
  );

  // -------------------------------------------------------------------------
  // F — PATCH backend : « guide » SEUL (jamais prénom / date de naissance)
  // -------------------------------------------------------------------------
  test('F. PATCH /api/app/profile ne porte QUE {guide}', () async {
    final e = _env();
    await e.state.changeAdvisor('Théa', 'thea');

    expect(e.requests, contains('PATCH /api/app/profile'));
    expect(e.patchBodies, hasLength(1));
    final body = jsonDecode(e.patchBodies.single) as Map<String, dynamic>;
    expect(body, {'guide': 'thea'});
    expect(body.containsKey('prenom'), isFalse);
    expect(body.containsKey('date_naissance'), isFalse);
  });

  // -------------------------------------------------------------------------
  // G — échec PATCH -> état cohérent (RIEN ne change), réessai possible
  // -------------------------------------------------------------------------
  test('G. PATCH réseau KO -> networkFailed, aucun changement local', () async {
    final repo = LocalOnboardingRepository();
    final e = _env(networkError: true, repository: repo);
    final out = await e.state.changeAdvisor('Luna', 'luna');
    expect(out, AdvisorChangeOutcome.networkFailed);
    expect(e.state.selectedAdvisor, 'Séléna'); // inchangé
    expect(await repo.load(), isNull); // rien persisté
  });

  test('G bis. PATCH 401 -> unauthorized, aucun changement local', () async {
    final e = _env(patchStatus: 401);
    final out = await e.state.changeAdvisor('Luna', 'luna');
    expect(out, AdvisorChangeOutcome.unauthorized);
    expect(e.state.selectedAdvisor, 'Séléna');
  });

  // -------------------------------------------------------------------------
  // H / I / J — consultation active conseiller A, nouveau préféré B
  // -------------------------------------------------------------------------
  test('H/I/J. session active avec Séléna + nouveau préféré Luna : '
      'la session reste Séléna, la prochaine sera Luna, sans erreur', () async {
    final e = _env();
    final consultation = ConsultationController(
      api: ConsultationApi(
        ApiClient(
          httpClient: MockClient((_) async => _json({}, 200)),
          baseUrl: 'http://test.local',
        ),
      ),
      auth: e.auth,
    );
    addTearDown(consultation.dispose);
    consultation.updateFromMessageResponse(
      ConsultationMessageResponse.fromJson({
        'reply': 'x',
        'consultation': {
          'id': 'c-live',
          'advisor_id': 'selena',
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 2))
              .toIso8601String(),
          'seconds_remaining': 7000,
          'credit_source': 'monthly',
        },
        'quota': {
          'is_premium': true,
          'monthly_limit': 10,
          'monthly_used': 1,
          'monthly_remaining': 9,
          'earned_available': 0,
        },
      }),
    );

    final out = await e.state.changeAdvisor('Luna', 'luna');

    expect(out, AdvisorChangeOutcome.synced);
    // I. la consultation active n'a PAS bougé.
    expect(consultation.active?.advisorId, 'selena');
    expect(consultation.hasActiveSession, isTrue);
    // J. le conseiller de la prochaine consultation est bien Luna.
    expect(e.state.selectedAdvisor, 'Luna');
  });

  // -------------------------------------------------------------------------
  // K / L — aucun crédit consommé, aucune consultation créée
  // -------------------------------------------------------------------------
  test('K/L. changer de conseiller ne touche QUE le profil '
      '(aucun /api/consultation, aucun /api/tirages)', () async {
    final e = _env();
    await e.state.changeAdvisor('Orion', 'orion');

    expect(e.requests, ['PATCH /api/app/profile']);
    expect(e.requests.where((r) => r.contains('/api/consultation')), isEmpty);
    expect(e.requests.where((r) => r.contains('/api/tirages')), isEmpty);
  });

  // -------------------------------------------------------------------------
  // Point d'entrée Accueil + liste des 10
  // -------------------------------------------------------------------------
  testWidgets('Accueil : les conseillers ne sont PLUS présentés (ni carrousel, '
      'ni « Changer de conseiller ») — ils reviendront dans l\'onglet '
      'Consultation', (tester) async {
    final e = _env();
    await tester.pumpWidget(
      AuryelStateScope(
        state: e.state,
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Changer de conseiller'), findsNothing);
    expect(find.text('Découvre nos conseillers'), findsNothing);
    expect(find.byType(AdvisorsCarousel), findsNothing);
    expect(find.byType(AdvisorChooserScreen), findsNothing);
  });
}

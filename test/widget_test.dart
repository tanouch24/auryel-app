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
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/main.dart';
import 'package:auryel/screens/onboarding/otp_code_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';

/// AuthController de test : jeton initial optionnel + réponse HTTP contrôlée
/// (utilisé par les tests de splash).
AuthController _auth({
  String? token,
  http.Response Function(http.Request req)? respond,
  bool throwNetwork = false,
}) {
  final mock = MockClient((req) async {
    if (throwNetwork) throw http.ClientException('offline');
    return respond?.call(req) ?? http.Response('{}', 200);
  });
  final client = ApiClient(httpClient: mock, baseUrl: 'http://test.local');
  return AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
  );
}

/// AuthController + son TokenStore, piloté par un handler complet (tests OTP).
({AuthController auth, InMemoryTokenStore tokens}) _authFrom(
  Future<http.Response> Function(http.Request req) handler, {
  String? token,
}) {
  final tokens = InMemoryTokenStore(token);
  final client = ApiClient(httpClient: MockClient(handler), baseUrl: 'http://test.local');
  return (
    auth: AuthController(
      repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
    ),
    tokens: tokens,
  );
}

AuryelState _onboardingState({
  bool completed = false,
  String? userId = 'temp_deadbeef',
  String? selectedAdvisor = 'Maïa',
  String? firstName = 'Nathanyel',
  DateTime? birthDate,
}) {
  return AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: userId,
      selectedAdvisor: selectedAdvisor,
      firstName: firstName,
      birthDate: birthDate ?? DateTime(1994, 1, 1),
      portraitData: 'texte',
      portraitFeedback: 'ok',
      onboardingCompleted: completed,
    ),
  );
}

AuryelState _completedOnboardingState({String userId = 'temp_deadbeef'}) =>
    _onboardingState(
      completed: true,
      userId: userId,
      selectedAdvisor: 'Séléna',
      firstName: 'Nina',
    );

/// Monte l'app complète avec un [ConsultationController] adossé au même
/// [AuthController] (F4). Le GET /state du boot n'est déclenché que si la
/// session est restaurée valide.
AuryelApp _app({required AuryelState state, required AuthController auth}) =>
    AuryelApp(
      state: state,
      auth: auth,
      consultation:
          ConsultationController(api: auth.consultationApi, auth: auth),
    );

Future<void> _bootSplash(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2100)); // délai mini du splash
  await tester.pumpAndSettle();
}

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Handler par défaut d'un flux OTP complet ; [onPatch] observe le corps du
/// PATCH, [patchResponder] le personnalise (throw / statut).
Future<http.Response> Function(http.Request) _otpHandler({
  void Function(http.Request req)? onVerify,
  void Function(Map<String, dynamic> body)? onPatch,
  Future<http.Response> Function(http.Request req)? patchResponder,
}) {
  return (req) async {
    if (req.url.path == '/api/auth/verify-code') {
      onVerify?.call(req);
      return _json({'token': 'sess-tok'});
    }
    if (req.url.path == '/api/account') {
      return _json({'user_id': 'uuid-real', 'email': 'user@test.co'});
    }
    if (req.url.path == '/api/app/profile' && req.method == 'PATCH') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      onPatch?.call(body);
      if (patchResponder != null) return patchResponder(req);
      return _json({
        'user_id': 'uuid-real',
        'guide': body['guide'] ?? 'selena',
        'prenom': body['prenom'] ?? '',
        'date_naissance': body['date_naissance'],
        'chemin_de_vie': '6',
        'signe_zodiaque': 'Capricorne',
      });
    }
    return _json({}, 404);
  };
}

Future<void> _pumpOtp(
  WidgetTester tester, {
  required AuthController auth,
  required AuryelState state,
}) {
  return tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: AuryelStateScope(
        state: state,
        child: const MaterialApp(home: OtpCodeScreen(email: 'user@test.co')),
      ),
    ),
  );
}

Future<void> _enterCodeAndValidate(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pump();
  await tester.tap(find.text('Valider'));
  await tester.pumpAndSettle();
}

const _emailScreenMarker = 'Ton adresse email';
const _homeMarker = 'Découvrir le message du jour';
const _syncRetryMarker = 'Réessayer';
const _syncBlockedMarker = 'Revenir en arrière';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // SPLASH — routage (inchangé F1)
  // =========================================================================
  testWidgets('Splash : nouvel utilisateur -> parcours onboarding', (tester) async {
    final state = AuryelState(repository: LocalOnboardingRepository());
    await tester.pumpWidget(_app(state: state, auth: _auth()));
    expect(find.text('AURYEL'), findsOneWidget);
    await _bootSplash(tester);
    expect(find.text('Choisis ton conseiller'), findsOneWidget);
  });

  testWidgets('Splash : onboarding terminé + AUCUN token -> EmailAuthScreen',
      (tester) async {
    await tester.pumpWidget(
      _app(state: _completedOnboardingState(), auth: _auth(token: null)),
    );
    await _bootSplash(tester);
    expect(find.text(_emailScreenMarker), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
  });

  testWidgets('Splash : token valide (GET /account 200) -> MainNavShell',
      (tester) async {
    await tester.pumpWidget(
      _app(
        state: _completedOnboardingState(),
        auth: _auth(
          token: 'good-tok',
          respond: (_) => _json({'user_id': 'uuid-1', 'email': 'a@b.co'}),
        ),
      ),
    );
    await _bootSplash(tester);
    expect(find.text(_homeMarker), findsOneWidget);
  });

  testWidgets(
      'Splash : token présent + erreur réseau -> token conservé + MainNavShell',
      (tester) async {
    final auth = _auth(token: 'keep-tok', throwNetwork: true);
    await tester.pumpWidget(
      _app(state: _completedOnboardingState(), auth: auth),
    );
    await _bootSplash(tester);
    expect(find.text(_homeMarker), findsOneWidget);
    expect(auth.status, AuthStatus.networkError);
  });

  testWidgets('Splash : token rejeté (401) -> purge + EmailAuthScreen',
      (tester) async {
    final b = _authFrom((_) async => _json({'error': 'unauthorized'}, 401),
        token: 'bad-tok');
    await tester.pumpWidget(
      _app(state: _completedOnboardingState(), auth: b.auth),
    );
    await _bootSplash(tester);
    expect(find.text(_emailScreenMarker), findsOneWidget);
    expect(await b.tokens.read(), isNull);
    expect(b.auth.status, AuthStatus.sessionExpired);
  });

  // =========================================================================
  // OTP -> SYNCHRO PROFIL (B4.3)
  // =========================================================================
  testWidgets(
      'OTP OK + PATCH OK -> profil envoyé (guide=maia, prénom trimé, date ISO), '
      'completeOnboarding, MainNavShell', (tester) async {
    Map<String, dynamic>? patched;
    final b = _authFrom(_otpHandler(onPatch: (body) => patched = body));
    final state = _onboardingState(
      firstName: '  Nathanyel  ',
      selectedAdvisor: 'Maïa',
      birthDate: DateTime(2001, 3, 9),
    );

    await _pumpOtp(tester, auth: b.auth, state: state);
    await _enterCodeAndValidate(tester);

    expect(patched, {
      'guide': 'maia',
      'prenom': 'Nathanyel',
      'date_naissance': '2001-03-09',
    });
    expect(patched!.containsKey('user_id'), isFalse);
    expect(state.onboardingCompleted, isTrue);
    expect(state.userId, 'uuid-real');
    expect(find.text(_homeMarker), findsOneWidget);
  });

  testWidgets(
      'PATCH réseau KO -> reste sur OTP, token conservé, onboarding NON terminé, '
      'CTA Réessayer', (tester) async {
    final b = _authFrom(_otpHandler(
      patchResponder: (_) async => throw http.ClientException('offline'),
    ));
    final state = _onboardingState();

    await _pumpOtp(tester, auth: b.auth, state: state);
    await _enterCodeAndValidate(tester);

    expect(find.text(_homeMarker), findsNothing);
    expect(state.onboardingCompleted, isFalse);
    expect(await b.tokens.read(), 'sess-tok'); // jeton conservé
    expect(find.text(_syncRetryMarker), findsOneWidget);
  });

  testWidgets(
      'Retry après réseau KO -> ne redemande PAS d’OTP, PATCH 2e OK -> MainNavShell',
      (tester) async {
    var verifyCalls = 0;
    var patchCalls = 0;
    final b = _authFrom((req) async {
      if (req.url.path == '/api/auth/verify-code') {
        verifyCalls++;
        return _json({'token': 'sess-tok'});
      }
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'uuid-real', 'email': 'user@test.co'});
      }
      if (req.url.path == '/api/app/profile') {
        patchCalls++;
        if (patchCalls == 1) throw http.ClientException('offline');
        return _json({
          'user_id': 'uuid-real', 'guide': 'maia', 'prenom': 'Nathanyel',
          'date_naissance': '1994-01-01', 'chemin_de_vie': '6',
          'signe_zodiaque': 'Capricorne',
        });
      }
      return _json({}, 404);
    });
    final state = _onboardingState();

    await _pumpOtp(tester, auth: b.auth, state: state);
    await _enterCodeAndValidate(tester);
    expect(find.text(_syncRetryMarker), findsOneWidget);

    await tester.tap(find.text(_syncRetryMarker));
    await tester.pumpAndSettle();

    expect(find.text(_homeMarker), findsOneWidget);
    expect(state.onboardingCompleted, isTrue);
    expect(verifyCalls, 1); // aucun nouvel OTP
    expect(patchCalls, 2);
  });

  testWidgets('PATCH 401 -> token purgé + retour EmailAuthScreen', (tester) async {
    final b = _authFrom(_otpHandler(
      patchResponder: (_) async => _json({'error': 'unauthorized'}, 401),
    ));
    final state = _onboardingState();

    await _pumpOtp(tester, auth: b.auth, state: state);
    await _enterCodeAndValidate(tester);

    expect(find.text(_emailScreenMarker), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
    expect(await b.tokens.read(), isNull);
    expect(b.auth.status, AuthStatus.sessionExpired);
    expect(state.onboardingCompleted, isFalse);
  });

  testWidgets(
      'Donnée onboarding manquante (birthDate absent) -> syncBlocked, '
      'PATCH jamais appelé, pas d’entrée dans l’app', (tester) async {
    var patchCalled = false;
    final b = _authFrom(_otpHandler(onPatch: (_) => patchCalled = true));
    final state = AuryelState(
      repository: LocalOnboardingRepository(),
      initial: const OnboardingRecord(
        userId: 'temp_x',
        selectedAdvisor: 'Maïa',
        firstName: 'Nathanyel',
        birthDate: null,
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: false,
      ),
    );

    await _pumpOtp(tester, auth: b.auth, state: state);
    await _enterCodeAndValidate(tester);

    expect(patchCalled, isFalse);
    expect(state.onboardingCompleted, isFalse);
    expect(find.text(_homeMarker), findsNothing);
    expect(find.text(_syncBlockedMarker), findsOneWidget);
  });

  testWidgets('mauvais code -> reste sur OTP, aucune synchro', (tester) async {
    var patchCalled = false;
    final b = _authFrom((req) async {
      if (req.url.path == '/api/auth/verify-code') {
        return _json({'error': 'invalid_code'}, 401);
      }
      if (req.url.path == '/api/app/profile') patchCalled = true;
      return _json({}, 404);
    });

    await _pumpOtp(tester, auth: b.auth, state: _onboardingState());
    await _enterCodeAndValidate(tester);

    expect(patchCalled, isFalse);
    expect(find.textContaining('Code incorrect'), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
  });

  // =========================================================================
  // NON-RÉGRESSION F1
  // =========================================================================
  test('ancien onboarding local (shared_preferences) non cassé', () async {
    final legacy = OnboardingRecord(
      userId: 'temp_deadbeef',
      selectedAdvisor: 'Séléna',
      firstName: 'Nina',
      birthDate: DateTime(1994, 6, 3),
      portraitData: 'texte',
      portraitFeedback: 'ok',
      onboardingCompleted: true,
    );
    SharedPreferences.setMockInitialValues({
      'auryel_onboarding_v1': jsonEncode(legacy.toJson()),
    });

    final loaded = await LocalOnboardingRepository().load();
    expect(loaded, isNotNull);
    expect(loaded!.onboardingCompleted, isTrue);
    expect(loaded.selectedAdvisor, 'Séléna');
    expect(loaded.firstName, 'Nina');
  });
}

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
import 'package:auryel/screens/onboarding/account_creation_screen.dart';
import 'package:auryel/screens/onboarding/email_auth_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';

// ===========================================================================
// LOT AUTH V1 — cas limites : 429, double-tap, changement de compte,
// accessibilité 360 dp + clavier, absence de social login.
// L'essentiel (register/login/token/401/409/restore/logout/no-OTP) est couvert
// par test/auth_test.dart + test/auth_password_test.dart.
// ===========================================================================

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

typedef _Bundle = ({
  AuthController auth,
  InMemoryTokenStore tokens,
  List<String> hits,
});

_Bundle _build(
  Future<http.Response> Function(http.Request) handler, {
  String? token,
}) {
  final hits = <String>[];
  final client = ApiClient(
    httpClient: MockClient((req) {
      hits.add('${req.method} ${req.url.path}');
      return handler(req);
    }),
    baseUrl: _base,
  );
  final tokens = InMemoryTokenStore(token);
  final repo = AuthRepository(api: AuthApi(client), tokenStore: tokens);
  final auth = AuthController(
    repository: repo,
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  return (auth: auth, tokens: tokens, hits: hits);
}

AuryelState _state({
  String? userId,
  String? firstName = 'Nina',
  String? advisor = 'Maïa',
}) => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: userId,
    selectedAdvisor: advisor,
    firstName: firstName,
    birthDate: DateTime(1994, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: userId != null,
  ),
);

Widget _wrap(Widget child, _Bundle b, {AuryelState? state}) => AuthScope(
  controller: b.auth,
  child: AuryelStateScope(
    state: state ?? _state(),
    child: MaterialApp(home: child),
  ),
);

Future<void> _typeLogin(WidgetTester t) async {
  await t.enterText(find.byType(TextField).first, 'nina@example.com');
  await t.enterText(find.byType(TextField).last, 'motdepasse1');
  await t.pump();
}

Future<void> _typeRegister(WidgetTester t) async {
  await t.enterText(find.byType(TextField).first, 'nina@example.com');
  await t.enterText(find.byType(TextField).last, 'motdepasse1');
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // R8 — 429 : message propre, jamais de code HTTP
  // -------------------------------------------------------------------------
  testWidgets('8 — login 429 -> « Trop de tentatives… », pas de jargon', (
    t,
  ) async {
    final b = _build((_) async => _json({'error': 'rate_limited'}, 429));
    await t.pumpWidget(_wrap(const EmailAuthScreen(), b));
    await _typeLogin(t);
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();

    expect(find.textContaining('Trop de tentatives'), findsOneWidget);
    expect(find.textContaining('429'), findsNothing);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(await b.tokens.read(), isNull); // aucune session inventée
  });

  testWidgets('8 — register 429 -> message propre', (t) async {
    final b = _build((_) async => _json({'error': 'rate_limited'}, 429));
    await t.pumpWidget(_wrap(const AccountCreationScreen(), b));
    await _typeRegister(t);
    await t.tap(find.text('Créer mon compte'));
    await t.pumpAndSettle();

    expect(find.textContaining('Trop de tentatives'), findsOneWidget);
    expect(find.textContaining('429'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // R3 — double tap -> une seule requête
  // -------------------------------------------------------------------------
  testWidgets('3 — double tap « Se connecter » -> 1 seul POST login', (
    t,
  ) async {
    final b = _build((req) async {
      if (req.url.path == '/api/app/auth/login') {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return _json({'token': 'tok-A'});
      }
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'A', 'email': 'nina@example.com'});
      }
      return _json({}, 404);
    });
    await t.pumpWidget(_wrap(const EmailAuthScreen(), b));
    await _typeLogin(t);
    await t.tap(find.text('Se connecter'));
    await t.pump(); // _loading = true
    await t.tap(find.text('Connexion…'), warnIfMissed: false);
    await t.pump();
    await t.pumpAndSettle();

    expect(b.hits.where((h) => h == 'POST /api/app/auth/login').length, 1);
  });

  testWidgets('3 — double tap « Créer mon compte » -> 1 seul POST register', (
    t,
  ) async {
    final b = _build((req) async {
      if (req.url.path == '/api/app/auth/register') {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return _json({'token': 'tok-A'});
      }
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'A', 'email': 'nina@example.com'});
      }
      return _json({}, 404);
    });
    await t.pumpWidget(_wrap(const AccountCreationScreen(), b));
    await _typeRegister(t);
    await t.tap(find.text('Créer mon compte'));
    await t.pump();
    await t.tap(find.text('Création…'), warnIfMissed: false);
    await t.pump();
    await t.pumpAndSettle();

    expect(b.hits.where((h) => h == 'POST /api/app/auth/register').length, 1);
  });

  // -------------------------------------------------------------------------
  // R19 — changement de compte : aucune identité de A pour B
  // -------------------------------------------------------------------------
  testWidgets('19 — B se connecte sur l\'appareil de A -> prénom/conseiller '
      'de A effacés, pas affichés à B', (t) async {
    final b = _build((req) async {
      if (req.url.path == '/api/app/auth/login') {
        return _json({'token': 'tok-B'});
      }
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'B', 'email': 'b@example.com'});
      }
      return _json({}, 404);
    });
    // État local = celui de A.
    final state = _state(userId: 'A', firstName: 'Nina', advisor: 'Maïa');
    await t.pumpWidget(_wrap(const EmailAuthScreen(), b, state: state));
    await _typeLogin(t);
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();

    expect(state.userId, 'B');
    expect(state.firstName, isNull, reason: 'prénom de A effacé');
    expect(state.selectedAdvisor, isNull, reason: 'conseiller de A effacé');
    expect(state.birthDate, isNull);
  });

  testWidgets('19b — même utilisateur re-login -> identité CONSERVÉE', (
    t,
  ) async {
    final b = _build((req) async {
      if (req.url.path == '/api/app/auth/login') {
        return _json({'token': 'tok-A2'});
      }
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'A', 'email': 'nina@example.com'});
      }
      return _json({}, 404);
    });
    final state = _state(userId: 'A', firstName: 'Nina', advisor: 'Maïa');
    await t.pumpWidget(_wrap(const EmailAuthScreen(), b, state: state));
    await _typeLogin(t);
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();

    expect(state.userId, 'A');
    expect(state.firstName, 'Nina');
    expect(state.selectedAdvisor, 'Maïa');
  });

  // -------------------------------------------------------------------------
  // R21 — aucun bouton de social login
  // -------------------------------------------------------------------------
  for (final screen in <(String, Widget)>[
    ('EmailAuthScreen', const EmailAuthScreen()),
    ('AccountCreationScreen', const AccountCreationScreen()),
  ]) {
    testWidgets('21 — ${screen.$1} : aucun bouton Google / Apple / social', (
      t,
    ) async {
      final b = _build((_) async => _json({}, 404));
      await t.pumpWidget(_wrap(screen.$2, b));
      await t.pump();
      expect(find.textContaining('Google'), findsNothing);
      expect(find.textContaining('Apple'), findsNothing);
      expect(find.textContaining('Continuer avec'), findsNothing);
      expect(find.textContaining('Se connecter avec'), findsNothing);
    });
  }

  // -------------------------------------------------------------------------
  // R20 — accessibilité : 360 dp + clavier, aucun overflow
  // -------------------------------------------------------------------------
  for (final w in const [360.0, 384.0, 430.0]) {
    for (final screen in <(String, Widget)>[
      ('EmailAuthScreen', const EmailAuthScreen()),
      ('AccountCreationScreen', const AccountCreationScreen()),
    ]) {
      testWidgets(
        '20 — ${screen.$1} @ ${w.toInt()} dp + clavier : pas d\'overflow',
        (t) async {
          t.view.devicePixelRatio = 1.0;
          t.view.physicalSize = Size(w, 640);
          t.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(t.view.reset);
          addTearDown(t.view.resetViewInsets);

          final b = _build((_) async => _json({}, 404));
          await t.pumpWidget(_wrap(screen.$2, b));
          await t.pumpAndSettle();

          expect(
            t.takeException(),
            isNull,
            reason: '${screen.$1} ${w.toInt()}',
          );
          expect(find.byType(TextField), findsNWidgets(2));
          // le CTA reste atteignable (scroll si nécessaire)
          final cta = screen.$1 == 'EmailAuthScreen'
              ? 'Se connecter'
              : 'Créer mon compte';
          await t.ensureVisible(find.text(cta));
        },
      );
    }
  }

  // -------------------------------------------------------------------------
  // R9/R10 — password_not_set : message spécifique, aucun faux reset
  // -------------------------------------------------------------------------
  testWidgets('9/10 — 409 password_not_set : message legacy + « Définir mon '
      'mot de passe » ouvre un message honnête, aucun endpoint appelé', (
    t,
  ) async {
    final b = _build((_) async => _json({'error': 'password_not_set'}, 409));
    await t.pumpWidget(_wrap(const EmailAuthScreen(), b));
    await _typeLogin(t);
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();

    expect(find.textContaining('aucun mot de passe'), findsOneWidget);
    final hitsAfterLogin = [...b.hits];

    await t.tap(find.text('Définir mon mot de passe'));
    await t.pumpAndSettle();
    expect(find.textContaining('arrive très bientôt'), findsOneWidget);
    // aucun nouvel appel réseau (pas de faux endpoint reset)
    expect(b.hits, hitsAfterLogin);
    expect(await b.tokens.read(), isNull);
  });
}

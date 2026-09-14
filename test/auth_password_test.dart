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
import 'package:auryel/data/intro_video_store.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/auryel_experience_screen.dart';
import 'package:auryel/screens/onboarding/account_creation_screen.dart';
import 'package:auryel/screens/onboarding/email_auth_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// AUTH V2 — email + mot de passe (register / login), suppression OTP du parcours.
// ===========================================================================

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

typedef _Bundle = ({
  AuthRepository repo,
  AuthController auth,
  ConsultationApi consultationApi,
  InMemoryTokenStore tokens,
  List<String> hitPaths,
});

_Bundle _build(
  Future<http.Response> Function(http.Request) handler, {
  String? token,
}) {
  final hits = <String>[];
  final tokens = InMemoryTokenStore(token);
  final client = ApiClient(
    httpClient: MockClient((req) {
      hits.add('${req.method} ${req.url.path}');
      return handler(req);
    }),
    baseUrl: _base,
  );
  final repo = AuthRepository(api: AuthApi(client), tokenStore: tokens);
  final consultationApi = ConsultationApi(client);
  return (
    repo: repo,
    consultationApi: consultationApi,
    auth: AuthController(
      repository: repo,
      profileApi: ProfileApi(client),
      consultationApi: consultationApi,
      tirageApi: TirageApi(client),
    ),
    tokens: tokens,
    hitPaths: hits,
  );
}

AuryelState _state({
  bool completed = false,
  String? firstName = 'Nina',
  String? advisor = 'Maïa',
  DateTime? birth,
}) => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: null,
    selectedAdvisor: advisor,
    firstName: firstName,
    birthDate: birth ?? DateTime(1994, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: completed,
  ),
);

Widget _wrap(Widget child, {required _Bundle b, AuryelState? state}) =>
    AuthScope(
      controller: b.auth,
      child: AuryelStateScope(
        state: state ?? _state(),
        child: MaterialApp(home: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -----------------------------------------------------------------------
  // Couche API / repo / controller
  // -----------------------------------------------------------------------
  group('AuthApi / AuthRepository', () {
    test('A/B — register : POST /api/app/auth/register, token stocké, aucun OTP', () async {
      final b = _build((req) async {
        expect(req.url.path, '/api/app/auth/register');
        // Flutter trime l'email ; la mise en minuscules (normalisation) est
        // faite côté backend (`_normalize_email`). Le mot de passe est intact.
        expect(jsonDecode(req.body), {
          'email': 'Alice@Example.com',
          'password': 'correcthorse',
        });
        return _json({'token': 'tok-reg', 'user_id': 'u1'});
      });
      final tok = await b.repo.registerWithPasswordAndStore(
        '  Alice@Example.com ',
        'correcthorse',
      );
      expect(tok, 'tok-reg');
      expect(await b.tokens.read(), 'tok-reg');
      expect(b.hitPaths, ['POST /api/app/auth/register']);
      expect(b.hitPaths.any((p) => p.contains('request-code')), isFalse);
      expect(b.hitPaths.any((p) => p.contains('verify-code')), isFalse);
    });

    test('I — login : POST /api/app/auth/login, token stocké', () async {
      final b = _build((req) async {
        expect(req.url.path, '/api/app/auth/login');
        return _json({'token': 'tok-login', 'user_id': 'u2'});
      });
      final tok = await b.repo.loginWithPasswordAndStore(
        'bob@example.com',
        'passphrase 1',
      );
      expect(tok, 'tok-login');
      expect(await b.tokens.read(), 'tok-login');
    });

    test('mot de passe NON modifié (espaces conservés, pas de trim)', () async {
      Map<String, dynamic>? sent;
      final b = _build((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'token': 't'});
      });
      await b.repo.loginWithPasswordAndStore(
        '  x@y.co  ',
        '  garde mes espaces  ',
      );
      expect(sent!['email'], 'x@y.co'); // email trimé
      expect(sent!['password'], '  garde mes espaces  '); // mdp intact
    });

    test(
      'F — register email invalide -> 400 invalid_email, aucun token',
      () async {
        final b = _build((_) async => _json({'error': 'invalid_email'}, 400));
        await expectLater(
          b.repo.registerWithPasswordAndStore('pas-un-email', 'motdepasse1'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 400)
                .having((e) => e.code, 'code', 'invalid_email'),
          ),
        );
        expect(await b.tokens.read(), isNull);
      },
    );

    test('E — register mot de passe faible -> 400 weak_password', () async {
      final b = _build((_) async => _json({'error': 'weak_password'}, 400));
      await expectLater(
        b.repo.registerWithPasswordAndStore('a@b.co', '1234567'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'weak_password'),
        ),
      );
    });

    test('G — register email déjà pris -> 409 email_taken', () async {
      final b = _build((_) async => _json({'error': 'email_taken'}, 409));
      await expectLater(
        b.repo.registerWithPasswordAndStore('taken@b.co', 'motdepasse1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.code, 'code', 'email_taken'),
        ),
      );
    });

    test(
      'J — login mauvais identifiants -> 401 invalid_credentials, aucun token',
      () async {
        final b = _build(
          (_) async => _json({
            'error': 'invalid_credentials',
            'message': 'Email ou mot de passe incorrect.',
          }, 401),
        );
        await expectLater(
          b.repo.loginWithPasswordAndStore('a@b.co', 'mauvais'),
          throwsA(isA<ApiUnauthorizedException>()),
        );
        expect(await b.tokens.read(), isNull);
      },
    );

    test(
      'K — login compte legacy sans mot de passe -> 409 password_not_set',
      () async {
        final b = _build(
          (_) async => _json({'error': 'password_not_set'}, 409),
        );
        await expectLater(
          b.repo.loginWithPasswordAndStore('legacy@b.co', 'peu importe'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 409)
                .having((e) => e.code, 'code', 'password_not_set'),
          ),
        );
      },
    );

    test(
      'H — AuthController.registerWithPassword -> signedIn + compte',
      () async {
        final b = _build((req) async {
          if (req.url.path == '/api/app/auth/register') {
            return _json({'token': 'tk'});
          }
          if (req.url.path == '/api/account') {
            return _json({'user_id': 'uuid-9', 'email': 'c@d.co'});
          }
          return _json({}, 404);
        });
        await b.auth.registerWithPassword('c@d.co', 'motdepasse1');
        expect(b.auth.status, AuthStatus.signedIn);
        expect(b.auth.account?.email, 'c@d.co');
        expect(await b.tokens.read(), 'tk');
      },
    );
  });

  // -----------------------------------------------------------------------
  // AccountCreationScreen — création de compte
  // -----------------------------------------------------------------------
  group('AccountCreationScreen (register)', () {
    Finder passwordField() =>
        find.byWidgetPredicate((w) => w is TextField && w.obscureText == true);

    testWidgets('C/D — champ mot de passe masqué par défaut + toggle œil', (
      t,
    ) async {
      final b = _build((_) async => _json({}, 404));
      await t.pumpWidget(_wrap(const AccountCreationScreen(), b: b));
      await t.pump();

      expect(passwordField(), findsOneWidget); // obscure au départ
      await t.tap(find.byTooltip('Afficher le mot de passe'));
      await t.pump();
      expect(passwordField(), findsNothing); // révélé
      await t.tap(find.byTooltip('Masquer le mot de passe'));
      await t.pump();
      expect(passwordField(), findsOneWidget); // re-masqué
    });

    testWidgets('E — mot de passe < 8 : CTA « Créer mon compte » désactivé', (
      t,
    ) async {
      final b = _build((_) async => _json({}, 404));
      await t.pumpWidget(_wrap(const AccountCreationScreen(), b: b));
      await t.pump();
      await t.enterText(find.byType(TextField).first, 'a@b.co');
      await t.enterText(passwordField(), '1234567');
      await t.pump();
      final cta = t.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text('Créer mon compte'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      // Le CTA de l'OnboardingScaffold : on vérifie plutôt qu'aucun POST ne part.
      await t.tap(find.text('Créer mon compte'));
      await t.pump();
      expect(b.hitPaths, isEmpty);
      expect(cta, isNotNull);
    });

    testWidgets(
      'A/B/P — register OK -> PATCH profil -> écran Expérience Auryel '
      '-> « Découvrir Auryel » -> MainNavShell, aucun OTP',
      (t) async {
        final b = _build((req) async {
          if (req.url.path == '/api/app/auth/register') {
            return _json({'token': 'tk'});
          }
          if (req.url.path == '/api/account') {
            return _json({'user_id': 'uuid-real', 'email': 'new@user.co'});
          }
          if (req.url.path == '/api/app/profile' && req.method == 'PATCH') {
            return _json({
              'user_id': 'uuid-real',
              'guide': 'maia',
              'prenom': 'Nina',
            });
          }
          if (req.url.path == '/api/consultation/state') {
            return _json({
              'consultation': null,
              'time': {
                'first_free_remaining_seconds': 1200,
                'premium_remaining_seconds': 0,
                'earned_remaining_seconds': 0,
                'purchased_remaining_seconds': 0,
                'total_remaining_seconds': 1200,
                'window_active': false,
                'window_expires_at': null,
              },
              'quota': {
                'is_premium': false,
                'monthly_limit': 4,
                'monthly_used': 0,
                'monthly_remaining': 0,
                'earned_available': 0,
                'first_free_available': true,
              },
            });
          }
          return _json({}, 404);
        });
        final state = _state();
        final consultation = ConsultationController(
          api: b.consultationApi,
          auth: b.auth,
        );
        await t.pumpWidget(
          ConsultationScope(
            controller: consultation,
            child: _wrap(const AccountCreationScreen(), b: b, state: state),
          ),
        );
        await t.pump();
        await t.enterText(find.byType(TextField).first, 'new@user.co');
        await t.enterText(passwordField(), 'motdepasse-solide');
        await t.pump();
        await t.tap(find.text('Créer mon compte'));
        await t.pumpAndSettle();

        // Étape présentation avant l'Accueil.
        expect(find.byType(AuryelExperienceScreen), findsOneWidget);
        expect(find.byType(MainNavShell), findsNothing);
        expect(await b.tokens.read(), 'tk');
        expect(state.onboardingCompleted, isTrue);
        expect(consultation.time?.totalRemainingSeconds, 1200);
        expect(b.hitPaths, contains('GET /api/consultation/state'));

        await t.tap(find.text('Découvrir Auryel'));
        await t.pumpAndSettle();
        expect(find.byType(MainNavShell), findsOneWidget);
        expect(
          b.hitPaths.any((p) => p.contains('/api/auth/')),
          isFalse,
          reason: 'aucun endpoint OTP legacy appelé',
        );
      },
    );

    testWidgets('G — 409 email_taken : message + lien « Se connecter »', (
      t,
    ) async {
      final b = _build((_) async => _json({'error': 'email_taken'}, 409));
      await t.pumpWidget(_wrap(const AccountCreationScreen(), b: b));
      await t.pump();
      await t.enterText(find.byType(TextField).first, 'taken@user.co');
      await t.enterText(passwordField(), 'motdepasse-solide');
      await t.pump();
      await t.tap(find.text('Créer mon compte'));
      await t.pumpAndSettle();

      expect(find.textContaining('Un compte existe déjà'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets(
      'L — double tap pendant le chargement : un seul POST register',
      (t) async {
        var registerCalls = 0;
        final b = _build((req) async {
          if (req.url.path == '/api/app/auth/register') {
            registerCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return _json({'token': 'tk'});
          }
          if (req.url.path == '/api/account') {
            return _json({'user_id': 'u', 'email': 'x@y.co'});
          }
          if (req.url.path == '/api/app/profile') {
            return _json({'user_id': 'u'});
          }
          return _json({}, 404);
        });
        await t.pumpWidget(_wrap(const AccountCreationScreen(), b: b));
        await t.pump();
        await t.enterText(find.byType(TextField).first, 'x@y.co');
        await t.enterText(passwordField(), 'motdepasse-solide');
        await t.pump();
        await t.tap(find.text('Créer mon compte'));
        await t.pump(); // busy = true
        await t.tap(find.text('Création…'), warnIfMissed: false);
        await t.pump();
        await t.pumpAndSettle();
        expect(registerCalls, 1);
      },
    );

    testWidgets('Q — aucun écran / texte OTP dans le parcours création', (
      t,
    ) async {
      final b = _build((_) async => _json({}, 404));
      await t.pumpWidget(_wrap(const AccountCreationScreen(), b: b));
      await t.pump();
      expect(find.textContaining('code'), findsNothing);
      expect(find.textContaining('Recevoir mon code'), findsNothing);
      expect(find.textContaining('Renvoyer le code'), findsNothing);
      expect(find.text('Ton compte'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // EmailAuthScreen — connexion
  // -----------------------------------------------------------------------
  group('EmailAuthScreen (login)', () {
    Finder passwordField() =>
        find.byWidgetPredicate((w) => w is TextField && w.obscureText == true);

    testWidgets('I — login OK -> token stocké -> MainNavShell', (t) async {
      final b = _build((req) async {
        if (req.url.path == '/api/app/auth/login') {
          return _json({'token': 'tk-l'});
        }
        if (req.url.path == '/api/account') {
          return _json({'user_id': 'u', 'email': 'r@user.co'});
        }
        return _json({}, 404);
      });
      final state = _state(completed: true);
      await t.pumpWidget(_wrap(const EmailAuthScreen(), b: b, state: state));
      await t.pump();
      await t.enterText(find.byType(TextField).first, 'r@user.co');
      await t.enterText(passwordField(), 'mon-mot-de-passe');
      await t.pump();
      await t.tap(find.text('Se connecter'));
      await t.pumpAndSettle();

      expect(find.byType(MainNavShell), findsOneWidget);
      expect(await b.tokens.read(), 'tk-l');
    });

    testWidgets('J — 401 -> « Email ou mot de passe incorrect. »', (t) async {
      final b = _build(
        (_) async => _json({'error': 'invalid_credentials'}, 401),
      );
      await t.pumpWidget(_wrap(const EmailAuthScreen(), b: b));
      await t.pump();
      await t.enterText(find.byType(TextField).first, 'r@user.co');
      await t.enterText(passwordField(), 'mauvais');
      await t.pump();
      await t.tap(find.text('Se connecter'));
      await t.pumpAndSettle();

      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
      expect(await b.tokens.read(), isNull);
    });

    testWidgets('K — 409 password_not_set : message legacy + seam sans OTP', (
      t,
    ) async {
      final b = _build((_) async => _json({'error': 'password_not_set'}, 409));
      await t.pumpWidget(_wrap(const EmailAuthScreen(), b: b));
      await t.pump();
      await t.enterText(find.byType(TextField).first, 'legacy@user.co');
      await t.enterText(passwordField(), 'peu-importe');
      await t.pump();
      await t.tap(find.text('Se connecter'));
      await t.pumpAndSettle();

      expect(find.textContaining('aucun mot de passe'), findsOneWidget);
      expect(find.text('Définir mon mot de passe'), findsOneWidget);
      // le seam N'appelle PAS l'OTP
      await t.tap(find.text('Définir mon mot de passe'));
      await t.pump();
      expect(b.hitPaths.any((p) => p.contains('request-code')), isFalse);
    });

    testWidgets('C — champ mot de passe masqué par défaut', (t) async {
      final b = _build((_) async => _json({}, 404));
      await t.pumpWidget(_wrap(const EmailAuthScreen(), b: b));
      await t.pump();
      expect(passwordField(), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------------------
  // Non-régression : IntroGate + aucun stockage local du mot de passe
  // -----------------------------------------------------------------------
  test('R — IntroGate non régressé (décision inchangée)', () {
    expect(
      IntroGate.decide(onboardingCompleted: true, introVideoSeen: false),
      IntroStep.authRouting,
    );
    expect(
      IntroGate.decide(onboardingCompleted: false, introVideoSeen: false),
      IntroStep.video,
    );
    expect(
      IntroGate.decide(onboardingCompleted: false, introVideoSeen: true),
      IntroStep.onboarding,
    );
  });

  testWidgets('S — aucun mot de passe écrit en SharedPreferences', (t) async {
    SharedPreferences.setMockInitialValues({});
    final b = _build((req) async {
      if (req.url.path == '/api/app/auth/login') return _json({'token': 'tk'});
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'u', 'email': 'x@y.co'});
      }
      return _json({}, 404);
    });
    await t.pumpWidget(
      _wrap(const EmailAuthScreen(), b: b, state: _state(completed: true)),
    );
    await t.pump();
    await t.enterText(find.byType(TextField).first, 'x@y.co');
    await t.enterText(
      (find.byWidgetPredicate((w) => w is TextField && w.obscureText == true)),
      'SECRET-passphrase-123',
    );
    await t.pump();
    await t.tap(find.text('Se connecter'));
    await t.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      final v = prefs.get(k);
      expect(
        v.toString().contains('SECRET-passphrase-123'),
        isFalse,
        reason: 'clé $k ne doit pas contenir le mot de passe',
      );
    }
    // le token, lui, vit dans le TokenStore (chiffré OS), jamais en prefs
    expect(
      prefs.getKeys().any((k) => k.toLowerCase().contains('token')),
      isFalse,
    );
  });
}

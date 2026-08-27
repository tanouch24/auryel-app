import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/config/api_config.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/state/auth_controller.dart';

const _base = 'http://test.local';

/// Construit un AuthRepository dont le HTTP est piloté par [handler] et dont
/// le jeton vit en mémoire (jamais de vrai stockage).
({AuthRepository repo, InMemoryTokenStore tokens}) _build(
  Future<http.Response> Function(http.Request req) handler, {
  String? initialToken,
}) {
  final tokens = InMemoryTokenStore(initialToken);
  final repo = AuthRepository(
    api: AuthApi(ApiClient(httpClient: MockClient(handler), baseUrl: _base)),
    tokenStore: tokens,
  );
  return (repo: repo, tokens: tokens);
}

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  test('requestCode : POST /api/auth/request-code avec {email}, succès sans throw',
      () async {
    http.Request? seen;
    final b = _build((req) async {
      seen = req;
      return _json({'status': 'ok'});
    });

    await b.repo.requestCode('  Toi@Exemple.com ');

    expect(seen!.method, 'POST');
    expect(seen!.url.toString(), '$_base/api/auth/request-code');
    expect(jsonDecode(seen!.body), {'email': 'Toi@Exemple.com'});
  });

  // ---------------------------------------------------------------------------
  test('verifyCode : succès -> renvoie le token ET le stocke', () async {
    final b = _build((req) async {
      expect(req.url.path, '/api/auth/verify-code');
      expect(jsonDecode(req.body), {'email': 'a@b.co', 'code': '123456'});
      return _json({'token': 'sess-abc-123'});
    });

    final token = await b.repo.verifyCodeAndStore('a@b.co', '123456');

    expect(token, 'sess-abc-123');
    expect(await b.tokens.read(), 'sess-abc-123');
  });

  // ---------------------------------------------------------------------------
  test('verifyCode : mauvais code (401) -> throw, AUCUN token stocké', () async {
    final b = _build((req) async => _json({'error': 'invalid_code'}, 401));

    await expectLater(
      b.repo.verifyCodeAndStore('a@b.co', '000000'),
      throwsA(isA<ApiUnauthorizedException>()),
    );
    expect(await b.tokens.read(), isNull);
  });

  test('verifyCode : code expiré (400) -> throw ApiException, aucun token',
      () async {
    final b = _build((req) async => _json({'error': 'expired'}, 400));

    await expectLater(
      b.repo.verifyCodeAndStore('a@b.co', '111111'),
      throwsA(isA<ApiException>()),
    );
    expect(await b.tokens.read(), isNull);
  });

  // ---------------------------------------------------------------------------
  test('restoreSession : token présent + GET /api/account 200 -> valid + compte',
      () async {
    final b = _build(
      (req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/account');
        expect(req.headers['Authorization'], 'Bearer stored-tok');
        return _json({'user_id': 'uuid-1', 'email': 'a@b.co'});
      },
      initialToken: 'stored-tok',
    );

    final r = await b.repo.restoreSession();

    expect(r.outcome, RestoreOutcome.valid);
    expect(r.account!.userId, 'uuid-1');
    expect(r.account!.email, 'a@b.co');
    expect(await b.tokens.read(), 'stored-tok');
  });

  // ---------------------------------------------------------------------------
  test('restoreSession : token invalide (401) -> expired + PURGE du token',
      () async {
    final b = _build(
      (req) async => _json({'error': 'unauthorized'}, 401),
      initialToken: 'bad-tok',
    );

    final r = await b.repo.restoreSession();

    expect(r.outcome, RestoreOutcome.expired);
    expect(await b.tokens.read(), isNull);
  });

  // ---------------------------------------------------------------------------
  test('restoreSession : erreur réseau -> networkError, token CONSERVÉ',
      () async {
    final b = _build(
      (req) async => throw http.ClientException('connection refused'),
      initialToken: 'keep-tok',
    );

    final r = await b.repo.restoreSession();

    expect(r.outcome, RestoreOutcome.networkError);
    expect(await b.tokens.read(), 'keep-tok');
  });

  test('restoreSession : 5xx -> networkError, token CONSERVÉ', () async {
    final b = _build(
      (req) async => _json({'error': 'server'}, 503),
      initialToken: 'keep-tok',
    );

    final r = await b.repo.restoreSession();

    expect(r.outcome, RestoreOutcome.networkError);
    expect(await b.tokens.read(), 'keep-tok');
  });

  test('restoreSession : aucun token -> noToken', () async {
    final b = _build((req) async => _json({}));
    final r = await b.repo.restoreSession();
    expect(r.outcome, RestoreOutcome.noToken);
  });

  // ---------------------------------------------------------------------------
  test('logout : POST /api/auth/logout puis suppression locale du token',
      () async {
    var loggedOut = false;
    final b = _build(
      (req) async {
        if (req.url.path == '/api/auth/logout') {
          loggedOut = true;
          expect(req.headers['Authorization'], 'Bearer tok-x');
          return _json({'status': 'ok'});
        }
        return _json({}, 404);
      },
      initialToken: 'tok-x',
    );

    await b.repo.logout();

    expect(loggedOut, isTrue);
    expect(await b.tokens.read(), isNull);
  });

  test('logout : serveur injoignable -> token quand même supprimé localement',
      () async {
    final b = _build(
      (req) async => throw http.ClientException('down'),
      initialToken: 'tok-x',
    );

    await b.repo.logout();

    expect(await b.tokens.read(), isNull);
  });

  // ---------------------------------------------------------------------------
  test('AuthController.verifyCode : statut signedIn + compte exposé', () async {
    final b = _build((req) async {
      if (req.url.path == '/api/auth/verify-code') {
        return _json({'token': 'ctrl-tok'});
      }
      if (req.url.path == '/api/account') {
        return _json({'user_id': 'uuid-9', 'email': 'x@y.z'});
      }
      return _json({}, 404);
    });
    final c = AuthController(repository: b.repo);

    await c.verifyCode('x@y.z', '654321');

    expect(c.status, AuthStatus.signedIn);
    expect(c.account!.userId, 'uuid-9');
    expect(await b.tokens.read(), 'ctrl-tok');
  });

  test(
      'AuthController.verifyCode : token OK mais /account réseau KO -> networkError, '
      'token conservé, pas d’exception', () async {
    final b = _build((req) async {
      if (req.url.path == '/api/auth/verify-code') {
        return _json({'token': 'ctrl-tok'});
      }
      throw http.ClientException('offline'); // /api/account
    });
    final c = AuthController(repository: b.repo);

    await c.verifyCode('x@y.z', '654321'); // ne throw pas

    expect(c.status, AuthStatus.networkError);
    expect(c.isSignedIn, isTrue);
    expect(await b.tokens.read(), 'ctrl-tok');
  });

  // ---------------------------------------------------------------------------
  test('aucun token en clair dans SharedPreferences après une auth complète',
      () async {
    SharedPreferences.setMockInitialValues({});
    final b = _build((req) async {
      if (req.url.path == '/api/auth/verify-code') {
        return _json({'token': 'secret-token-value'});
      }
      return _json({'user_id': 'u', 'email': 'e@e.e'});
    });

    await b.repo.verifyCodeAndStore('e@e.e', '123456');
    await b.repo.fetchAccount();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    for (final k in prefs.getKeys()) {
      expect(prefs.get(k).toString().contains('secret-token-value'), isFalse);
    }
  });

  // ---------------------------------------------------------------------------
  test('ancien onboarding local (shared_preferences) non cassé par F1', () async {
    final legacy = OnboardingRecord(
      userId: 'temp_deadbeef',
      selectedAdvisor: 'Séléna',
      firstName: 'Nina',
      birthDate: DateTime(1994, 6, 3),
      portraitData: 'texte portrait',
      portraitFeedback: 'C’est assez juste',
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
    expect(loaded.userId, 'temp_deadbeef');
    expect(loaded.birthDate, DateTime(1994, 6, 3));
  });

  // ---------------------------------------------------------------------------
  group('ApiConfig — base URL debug/release', () {
    test('override fourni -> utilisé (slash final retiré), même en release', () {
      expect(
        ApiConfig.resolveBaseUrl(
          hasOverride: true,
          override: 'https://api.auryel.example/',
          isReleaseLike: true,
        ),
        'https://api.auryel.example',
      );
    });

    test('debug + absent -> repli http://10.0.2.2:8000', () {
      expect(
        ApiConfig.resolveBaseUrl(
          hasOverride: false,
          override: '',
          isReleaseLike: false,
        ),
        ApiConfig.debugFallbackBaseUrl,
      );
      expect(ApiConfig.debugFallbackBaseUrl, 'http://10.0.2.2:8000');
    });

    test('release + absent -> StateError (fail fast, aucun repli)', () {
      expect(
        () => ApiConfig.resolveBaseUrl(
          hasOverride: false,
          override: '',
          isReleaseLike: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('release + override vide/espaces -> StateError', () {
      expect(
        () => ApiConfig.resolveBaseUrl(
          hasOverride: true,
          override: '   ',
          isReleaseLike: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('debug + override vide -> repli (pas de throw en debug)', () {
      expect(
        ApiConfig.resolveBaseUrl(
          hasOverride: true,
          override: '   ',
          isReleaseLike: false,
        ),
        ApiConfig.debugFallbackBaseUrl,
      );
    });

    test('flutter test tourne en mode debug -> baseUrl = repli, HTTP en clair',
        () {
      // Aucun --dart-define ici : on doit obtenir le repli, pas une exception.
      expect(ApiConfig.baseUrl, 'http://10.0.2.2:8000');
      expect(ApiConfig.isCleartext, isTrue);
    });
  });
}

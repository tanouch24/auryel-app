import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/config/api_config.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/state/auth_controller.dart';

const _base = 'http://test.local';

/// Construit un AuthRepository dont le HTTP est piloté par [handler] et dont
/// le jeton vit en mémoire (jamais de vrai stockage).
typedef _Bundle = ({AuthRepository repo, InMemoryTokenStore tokens, ApiClient client});

_Bundle _build(
  Future<http.Response> Function(http.Request req) handler, {
  String? initialToken,
}) {
  final tokens = InMemoryTokenStore(initialToken);
  final client = ApiClient(httpClient: MockClient(handler), baseUrl: _base);
  final repo = AuthRepository(api: AuthApi(client), tokenStore: tokens);
  return (repo: repo, tokens: tokens, client: client);
}

AuthController _controller(_Bundle b) =>
    AuthController(
      repository: b.repo,
      profileApi: ProfileApi(b.client),
      consultationApi: ConsultationApi(b.client),
      tirageApi: TirageApi(b.client),
    );

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
    final c = _controller(b);

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
    final c = _controller(b);

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

    // --- Garde-fou release AUR-C02 : aucune URL locale/debug/non-HTTPS -------
    test('release refuse une URL locale / de dev / non-HTTPS', () {
      for (final bad in const [
        'http://10.0.2.2:8000',
        'http://localhost:8000',
        'https://localhost',
        'https://127.0.0.1',
        'https://127.0.0.1:8443',
        'https://10.1.2.3',
        'https://192.168.1.10',
        'https://172.16.0.5',
        'https://169.254.1.1',
        'http://api.auryel.example', // HTTP en clair
        'https://backend',           // hôte non qualifié
        'https://api.auryel.local',  // .local
        'ftp://api.auryel.example',  // schéma non-HTTPS
        'api.auryel.example',        // pas absolue
      ]) {
        expect(
          () => ApiConfig.resolveBaseUrl(
            hasOverride: true,
            override: bad,
            isReleaseLike: true,
          ),
          throwsA(isA<StateError>()),
          reason: 'devrait refuser "$bad" en release',
        );
        expect(ApiConfig.releaseUrlRejectionReason(bad), isNotNull,
            reason: '"$bad" devrait avoir une raison de rejet');
      }
    });

    test('release accepte une URL HTTPS publique valide (slash retiré)', () {
      for (final good in const [
        'https://api.auryel.example',
        'https://api.auryel.example/',
        'https://auryel-api.up.railway.app',
        'https://api.auryel.example:8443/v1',
      ]) {
        expect(ApiConfig.releaseUrlRejectionReason(good), isNull,
            reason: '"$good" devrait être accepté');
      }
      expect(
        ApiConfig.resolveBaseUrl(
          hasOverride: true,
          override: 'https://api.auryel.example/',
          isReleaseLike: true,
        ),
        'https://api.auryel.example',
      );
    });

    test('DEBUG reste permissif (10.0.2.2 / localhost / http autorisés)', () {
      for (final local in const [
        'http://10.0.2.2:8000',
        'http://localhost:3000',
        'http://192.168.1.50:8080',
      ]) {
        expect(
          ApiConfig.resolveBaseUrl(
            hasOverride: true,
            override: local,
            isReleaseLike: false,
          ),
          local,
          reason: 'debug ne doit pas toucher "$local"',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthController.syncProfile (B4.3)', () {
    _Bundle patchBundle(
      void Function(http.Request req) onPatch, {
      String? initialToken = 'tok',
      int status = 200,
      Object? throwOnPatch,
    }) {
      return _build(
        (req) async {
          if (req.url.path == '/api/app/profile' && req.method == 'PATCH') {
            onPatch(req);
            if (throwOnPatch != null) throw throwOnPatch;
            return _json({
              'user_id': 'uuid-1',
              'guide': jsonDecode(req.body)['guide'] ?? 'selena',
              'prenom': jsonDecode(req.body)['prenom'] ?? '',
              'date_naissance': jsonDecode(req.body)['date_naissance'],
              'chemin_de_vie': '6',
              'signe_zodiaque': 'Capricorne',
            }, status);
          }
          return _json({}, 404);
        },
        initialToken: initialToken,
      );
    }

    test('succès : PATCH {guide, prenom, date_naissance} exacts, AUCUN user_id, '
        'token inchangé', () async {
      Map<String, dynamic>? sent;
      String? auth;
      final b = patchBundle((req) {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        auth = req.headers['Authorization'];
      });
      final c = _controller(b);

      final out = await c.syncProfile(
        guide: 'maia', prenom: 'Nathanyel', dateNaissance: '1984-01-01');

      expect(out, ProfileSyncOutcome.ok);
      expect(sent, {
        'guide': 'maia',
        'prenom': 'Nathanyel',
        'date_naissance': '1984-01-01',
      });
      expect(sent!.containsKey('user_id'), isFalse);
      expect(auth, 'Bearer tok');
      expect(await b.tokens.read(), 'tok');
    });

    test('conseiller Maïa -> le corps porte "maia", jamais "Séléna"/"selena"',
        () async {
      Map<String, dynamic>? sent;
      final b = patchBundle((req) => sent = jsonDecode(req.body));
      await _controller(b).syncProfile(
        guide: 'maia', prenom: 'Zoe', dateNaissance: '1990-05-05');
      expect(sent!['guide'], 'maia');
      expect(sent!['prenom'], isNot(anyOf('Séléna', 'selena')));
    });

    test('401 pendant le PATCH -> unauthorized + PURGE token + sessionExpired',
        () async {
      final b = _build(
        (req) async => _json({'error': 'unauthorized'}, 401),
        initialToken: 'tok',
      );
      final c = _controller(b);

      final out = await c.syncProfile(
        guide: 'selena', prenom: 'A', dateNaissance: '2000-01-01');

      expect(out, ProfileSyncOutcome.unauthorized);
      expect(await b.tokens.read(), isNull);
      expect(c.status, AuthStatus.sessionExpired);
    });

    test('réseau KO -> retryable, token CONSERVÉ', () async {
      final b = patchBundle((_) {}, throwOnPatch: http.ClientException('offline'));
      final c = _controller(b);

      final out = await c.syncProfile(
        guide: 'selena', prenom: 'A', dateNaissance: '2000-01-01');

      expect(out, ProfileSyncOutcome.retryable);
      expect(await b.tokens.read(), 'tok');
    });

    test('5xx -> retryable, token CONSERVÉ', () async {
      final b = patchBundle((_) {}, status: 503);
      final c = _controller(b);
      final out = await c.syncProfile(
        guide: 'selena', prenom: 'A', dateNaissance: '2000-01-01');
      expect(out, ProfileSyncOutcome.retryable);
      expect(await b.tokens.read(), 'tok');
    });

    test('aucun token -> unauthorized', () async {
      final b = patchBundle((_) {}, initialToken: null);
      final out = await _controller(b).syncProfile(
        guide: 'selena', prenom: 'A', dateNaissance: '2000-01-01');
      expect(out, ProfileSyncOutcome.unauthorized);
    });

    test('retry après réseau KO : 2e appel OK, aucun nouvel appel verify-code',
        () async {
      var patchCalls = 0;
      var verifyCalls = 0;
      final tokens = InMemoryTokenStore('tok');
      final client = ApiClient(
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/auth/verify-code') {
            verifyCalls++;
            return _json({'token': 'tok'});
          }
          if (req.url.path == '/api/app/profile') {
            patchCalls++;
            if (patchCalls == 1) throw http.ClientException('offline');
            return _json({
              'user_id': 'u', 'guide': 'maia', 'prenom': 'N',
              'date_naissance': '1984-01-01', 'chemin_de_vie': '6',
              'signe_zodiaque': 'Capricorne',
            });
          }
          return _json({}, 404);
        }),
        baseUrl: _base,
      );
      final c = AuthController(
        repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
        profileApi: ProfileApi(client),
        consultationApi: ConsultationApi(client),
        tirageApi: TirageApi(client),
      );

      final first = await c.syncProfile(
        guide: 'maia', prenom: 'N', dateNaissance: '1984-01-01');
      expect(first, ProfileSyncOutcome.retryable);
      expect(await tokens.read(), 'tok'); // conservé

      final second = await c.syncProfile(
        guide: 'maia', prenom: 'N', dateNaissance: '1984-01-01');
      expect(second, ProfileSyncOutcome.ok);

      expect(patchCalls, 2);
      expect(verifyCalls, 0); // aucun OTP redemandé
    });
  });
}

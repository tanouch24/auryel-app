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
import 'package:auryel/data/app_profile.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/onboarding/email_auth_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/profile_restore.dart';
import 'package:auryel/state/session_profile_gate.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// PROFIL MULTI-APPAREIL / RESTAURATION PROFIL AU LOGIN
//   - AuthController.fetchServerProfile  (GET /api/app/profile)
//   - AuryelState.applyServerProfile      (serveur prime, partiel toléré)
//   - EmailAuthScreen : restauration au login + changement de compte
// ===========================================================================

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

/// Repo espion : capture le dernier instantané persisté + les `clear()`.
class _SpyRepo implements OnboardingRepository {
  _SpyRepo(this._current);
  OnboardingRecord? _current;
  int clears = 0;
  int saves = 0;
  OnboardingRecord? get last => _current;

  @override
  Future<OnboardingRecord?> load() async => _current;

  @override
  Future<void> save(OnboardingRecord record) async {
    saves++;
    _current = record;
  }

  @override
  Future<void> clear() async {
    clears++;
    _current = null;
  }
}

typedef _Bundle = ({
  AuthController auth,
  InMemoryTokenStore tokens,
  List<String> hits,
});

_Bundle _build(
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'tk',
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
  return (
    auth: AuthController(
      repository: repo,
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
    ),
    tokens: tokens,
    hits: hits,
  );
}

AuryelState _state({
  required OnboardingRepository repo,
  String? userId,
  String? firstName,
  String? advisor,
  DateTime? birthDate,
  bool completed = true,
}) => AuryelState(
  repository: repo,
  initial: OnboardingRecord(
    userId: userId,
    selectedAdvisor: advisor,
    firstName: firstName,
    birthDate: birthDate,
    portraitData: null,
    portraitFeedback: null,
    onboardingCompleted: completed,
  ),
);

Widget _wrap(Widget child, {required _Bundle b, required AuryelState state}) =>
    AuthScope(
      controller: b.auth,
      child: AuryelStateScope(
        state: state,
        child: MaterialApp(home: child),
      ),
    );

/// Réponse `/api/app/profile` (GET) — champs optionnels pour tester le partiel.
Map<String, dynamic> _profileJson({
  String userId = 'U',
  String? guide,
  String? prenom,
  String? dateNaissance,
}) => {
  'user_id': userId,
  'guide': ?guide,
  'prenom': ?prenom,
  'date_naissance': ?dateNaissance,
  'chemin_de_vie': '',
  'signe_zodiaque': '',
};

Future<void> _login(
  WidgetTester t, {
  required _Bundle b,
  required AuryelState state,
  String email = 'user@auryel.co',
}) async {
  await t.pumpWidget(_wrap(const EmailAuthScreen(), b: b, state: state));
  await t.pump();
  await t.enterText(find.byType(TextField).first, email);
  await t.enterText(
    find.byWidgetPredicate((w) => w is TextField && w.obscureText == true),
    'mon-mot-de-passe',
  );
  await t.pump();
  await t.tap(find.text('Se connecter'));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =======================================================================
  // 1. AuthController.fetchServerProfile
  // =======================================================================
  group('AuthController.fetchServerProfile', () {
    test('200 -> ok + AppProfile', () async {
      final b = _build(
        (req) async => req.url.path == '/api/app/profile'
            ? _json(_profileJson(userId: 'U1', guide: 'orion', prenom: 'Sarah'))
            : _json({}, 404),
      );
      final r = await b.auth.fetchServerProfile();
      expect(r.outcome, ProfileRestoreOutcome.ok);
      expect(r.profile!.userId, 'U1');
      expect(r.profile!.guide, 'orion');
      expect(r.profile!.prenom, 'Sarah');
      expect(b.hits, contains('GET /api/app/profile'));
    });

    test(
      '401 -> unauthorized + session purgée (politique auth unique)',
      () async {
        final b = _build((_) async => _json({'error': 'invalid_token'}, 401));
        final r = await b.auth.fetchServerProfile();
        expect(r.outcome, ProfileRestoreOutcome.unauthorized);
        expect(r.profile, isNull);
        expect(b.auth.status, AuthStatus.sessionExpired);
        expect(await b.tokens.read(), isNull);
      },
    );

    test('réseau KO -> retryable, session NON touchée', () async {
      final b = _build((_) async => throw http.ClientException('offline'));
      final r = await b.auth.fetchServerProfile();
      expect(r.outcome, ProfileRestoreOutcome.retryable);
      expect(b.auth.status, isNot(AuthStatus.sessionExpired));
      expect(await b.tokens.read(), 'tk');
    });

    test('5xx -> retryable, session NON touchée', () async {
      final b = _build((_) async => _json({'error': 'boom'}, 503));
      final r = await b.auth.fetchServerProfile();
      expect(r.outcome, ProfileRestoreOutcome.retryable);
      expect(await b.tokens.read(), 'tk');
    });

    test('404 -> retryable (pas de crash, session gardée)', () async {
      final b = _build((_) async => _json({'error': 'not_found'}, 404));
      final r = await b.auth.fetchServerProfile();
      expect(r.outcome, ProfileRestoreOutcome.retryable);
      expect(await b.tokens.read(), 'tk');
    });

    test('aucun jeton -> retryable, aucun appel HTTP', () async {
      final b = _build((_) async => _json({}), token: null);
      final r = await b.auth.fetchServerProfile();
      expect(r.outcome, ProfileRestoreOutcome.retryable);
      expect(b.hits, isEmpty);
    });
  });

  // =======================================================================
  // 1bis. SessionProfileGate — décisions pures du démarrage / login
  // =======================================================================
  group('SessionProfileGate', () {
    test('mustForgetLocalIdentity : autre compte réel -> true', () {
      expect(
        SessionProfileGate.mustForgetLocalIdentity(
          accountUserId: 'B',
          localUserId: 'A',
        ),
        isTrue,
      );
    });

    test('mustForgetLocalIdentity : même compte / temp_ / vide -> false', () {
      expect(
        SessionProfileGate.mustForgetLocalIdentity(
          accountUserId: 'A',
          localUserId: 'A',
        ),
        isFalse,
      );
      expect(
        SessionProfileGate.mustForgetLocalIdentity(
          accountUserId: 'A',
          localUserId: 'temp_abc',
        ),
        isFalse,
      );
      expect(
        SessionProfileGate.mustForgetLocalIdentity(
          accountUserId: 'A',
          localUserId: null,
        ),
        isFalse,
      );
    });

    test(
      'localProfileUsableAsIs : complet + même compte -> true (start rapide)',
      () {
        expect(
          SessionProfileGate.localProfileUsableAsIs(
            accountUserId: 'A',
            localUserId: 'A',
            firstName: 'Nina',
            birthDate: DateTime(1994, 1, 1),
            selectedAdvisor: 'Maïa',
          ),
          isTrue,
        );
      },
    );

    test('localProfileUsableAsIs : incomplet ou autre compte -> false', () {
      // conseiller manquant
      expect(
        SessionProfileGate.localProfileUsableAsIs(
          accountUserId: 'A',
          localUserId: 'A',
          firstName: 'Nina',
          birthDate: DateTime(1994, 1, 1),
          selectedAdvisor: null,
        ),
        isFalse,
      );
      // autre compte
      expect(
        SessionProfileGate.localProfileUsableAsIs(
          accountUserId: 'B',
          localUserId: 'A',
          firstName: 'Nina',
          birthDate: DateTime(1994, 1, 1),
          selectedAdvisor: 'Maïa',
        ),
        isFalse,
      );
    });
  });

  // =======================================================================
  // 2. AuryelState.applyServerProfile — serveur prime, partiel toléré
  // =======================================================================
  group('AuryelState.applyServerProfile', () {
    test(
      'profil complet : prénom + date + conseiller remplacent le local',
      () async {
        final repo = _SpyRepo(null);
        final s = _state(
          repo: repo,
          userId: 'U',
          firstName: 'Ancien',
          advisor: 'Séléna',
          birthDate: DateTime(1990, 1, 1),
        );
        await applyServerProfileToState(
          s,
          AppProfile.fromJson(
            _profileJson(
              userId: 'U',
              guide: 'luna',
              prenom: 'Sarah',
              dateNaissance: '1994-07-15',
            ),
          ),
        );
        expect(s.firstName, 'Sarah');
        expect(s.birthDate, DateTime(1994, 7, 15));
        expect(s.selectedAdvisor, 'Luna');
        expect(repo.last!.firstName, 'Sarah', reason: 'persistance instantané');
        expect(repo.saves, greaterThanOrEqualTo(1));
      },
    );

    test('profil partiel : un vide serveur ne remplace PAS le local', () async {
      final repo = _SpyRepo(null);
      final s = _state(
        repo: repo,
        userId: 'U',
        firstName: 'Nina',
        advisor: 'Maïa',
        birthDate: DateTime(1994, 1, 1),
      );
      // Serveur ne renvoie QUE le prénom.
      await applyServerProfileToState(
        s,
        AppProfile.fromJson(_profileJson(userId: 'U', prenom: 'Nina B.')),
      );
      expect(s.firstName, 'Nina B.');
      expect(
        s.birthDate,
        DateTime(1994, 1, 1),
        reason: 'date locale conservée',
      );
      expect(s.selectedAdvisor, 'Maïa', reason: 'conseiller local conservé');
    });

    test('profil entièrement vide : rien inventé, aucun crash', () async {
      final repo = _SpyRepo(null);
      final s = _state(repo: repo, userId: 'U');
      await applyServerProfileToState(
        s,
        AppProfile.fromJson(_profileJson(userId: 'U')),
      );
      expect(s.firstName, isNull);
      expect(s.birthDate, isNull);
      expect(s.selectedAdvisor, isNull, reason: 'jamais Séléna fabriquée');
    });

    test('guide inconnu -> conseiller inchangé, aucun crash', () async {
      final repo = _SpyRepo(null);
      final s = _state(repo: repo, userId: 'U');
      await applyServerProfileToState(
        s,
        AppProfile.fromJson(
          _profileJson(userId: 'U', guide: 'inconnu_x', prenom: 'Zoé'),
        ),
      );
      expect(s.firstName, 'Zoé');
      expect(s.selectedAdvisor, isNull);
    });

    test('mapping des 10 guides backend -> noms accentués', () async {
      const pairs = {
        'selena': 'Séléna',
        'luna': 'Luna',
        'maia': 'Maïa',
        'thea': 'Théa',
        'cassandre': 'Cassandre',
        'myriam': 'Myriam',
        'orion': 'Orion',
        'ezra': 'Ezra',
        'kael': 'Kaël',
        'raphael': 'Raphaël',
      };
      for (final e in pairs.entries) {
        final s = _state(repo: _SpyRepo(null), userId: 'U');
        await applyServerProfileToState(
          s,
          AppProfile.fromJson(_profileJson(userId: 'U', guide: e.key)),
        );
        expect(s.selectedAdvisor, e.value, reason: e.key);
      }
    });

    test('date ISO malformée -> ignorée sans crash', () async {
      final s = _state(repo: _SpyRepo(null), userId: 'U', birthDate: null);
      await applyServerProfileToState(
        s,
        AppProfile.fromJson(
          _profileJson(userId: 'U', dateNaissance: '15/07/1994'),
        ),
      );
      expect(s.birthDate, isNull);
    });
  });

  // =======================================================================
  // 3. EmailAuthScreen — restauration au login
  // =======================================================================
  group('EmailAuthScreen — restauration profil au login', () {
    _Bundle bundleWith({
      required String accountUserId,
      Map<String, dynamic>? profile,
      int profileStatus = 200,
      Object? profileThrows,
    }) {
      return _build((req) async {
        if (req.url.path == '/api/app/auth/login') {
          return _json({'token': 'tk'});
        }
        if (req.url.path == '/api/account') {
          return _json({'user_id': accountUserId, 'email': 'x@y.co'});
        }
        if (req.url.path == '/api/app/profile' && req.method == 'GET') {
          if (profileThrows != null) throw profileThrows;
          return _json(
            profile ?? _profileJson(userId: accountUserId),
            profileStatus,
          );
        }
        return _json({}, 404);
      });
    }

    testWidgets('1+2+3+4+5 — compte existant : GET profile, prénom/date/'
        'conseiller récupérés et persistés', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(
        accountUserId: 'U-existing',
        profile: _profileJson(
          userId: 'U-existing',
          guide: 'orion',
          prenom: 'Sarah',
          dateNaissance: '1994-07-15',
        ),
      );
      // Nouveau téléphone : aucune identité locale.
      final state = _state(repo: repo, userId: null);
      await _login(t, b: b, state: state);

      expect(b.hits, contains('GET /api/app/profile'));
      expect(state.firstName, 'Sarah');
      expect(state.birthDate, DateTime(1994, 7, 15));
      expect(state.selectedAdvisor, 'Orion');
      expect(state.userId, 'U-existing');
      expect(repo.last!.firstName, 'Sarah');
      expect(repo.last!.selectedAdvisor, 'Orion');
      expect(find.byType(MainNavShell), findsOneWidget);
    });

    testWidgets('6+7 — changement A -> B : aucune donnée de A, B reçoit son '
        'profil serveur', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(
        accountUserId: 'U-B',
        profile: _profileJson(
          userId: 'U-B',
          guide: 'luna',
          prenom: 'Sarah',
          dateNaissance: '2000-02-02',
        ),
      );
      // Identité locale = compte A (Nathanyel / Orion).
      final state = _state(
        repo: repo,
        userId: 'U-A',
        firstName: 'Nathanyel',
        advisor: 'Orion',
        birthDate: DateTime(1988, 3, 3),
      );
      await _login(t, b: b, state: state);

      expect(state.firstName, 'Sarah');
      expect(state.selectedAdvisor, 'Luna');
      expect(state.birthDate, DateTime(2000, 2, 2));
      expect(state.userId, 'U-B');
      expect(repo.clears, greaterThanOrEqualTo(1), reason: 'oubli identité A');
      expect(find.text('Nathanyel'), findsNothing);
      expect(find.text('Orion'), findsNothing);
    });

    testWidgets('8 — retour B -> A : A retrouve son profil serveur', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(
        accountUserId: 'U-A',
        profile: _profileJson(
          userId: 'U-A',
          guide: 'ezra',
          prenom: 'Nathanyel',
          dateNaissance: '1988-03-03',
        ),
      );
      // Identité locale = compte B, on se reconnecte en A.
      final state = _state(
        repo: repo,
        userId: 'U-B',
        firstName: 'Sarah',
        advisor: 'Luna',
        birthDate: DateTime(2000, 2, 2),
      );
      await _login(t, b: b, state: state);

      expect(state.firstName, 'Nathanyel');
      expect(state.selectedAdvisor, 'Ezra');
      expect(state.userId, 'U-A');
      expect(find.text('Sarah'), findsNothing);
    });

    testWidgets('9 — réseau KO sur profile : session RESTE connectée, '
        'MainNavShell, aucune donnée de l\'ancien compte', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(
        accountUserId: 'U-new',
        profileThrows: http.ClientException('offline'),
      );
      final state = _state(
        repo: repo,
        userId: 'U-old',
        firstName: 'Ancien',
        advisor: 'Orion',
        birthDate: DateTime(1980, 1, 1),
      );
      await _login(t, b: b, state: state);

      expect(find.byType(MainNavShell), findsOneWidget);
      expect(b.auth.status, AuthStatus.signedIn);
      expect(await b.tokens.read(), 'tk');
      // L'identité de l'ancien compte a été oubliée avant le fetch raté.
      expect(state.firstName, isNull);
      expect(state.selectedAdvisor, isNull);
      expect(find.text('Ancien'), findsNothing);
    });

    testWidgets('10 — 5xx sur profile : session reste connectée', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(accountUserId: 'U', profileStatus: 503);
      final state = _state(repo: repo, userId: null);
      await _login(t, b: b, state: state);
      expect(find.byType(MainNavShell), findsOneWidget);
      expect(b.auth.status, AuthStatus.signedIn);
      expect(await b.tokens.read(), 'tk');
    });

    testWidgets('11 — profil partiel (prénom seul) : pas de crash', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(
        accountUserId: 'U',
        profile: _profileJson(userId: 'U', prenom: 'Solo'),
      );
      final state = _state(repo: repo, userId: null);
      await _login(t, b: b, state: state);
      expect(find.byType(MainNavShell), findsOneWidget);
      expect(state.firstName, 'Solo');
      expect(state.birthDate, isNull);
      expect(state.selectedAdvisor, isNull);
    });

    testWidgets(
      '12 — guide serveur inconnu : pas de crash, conseiller non forcé',
      (t) async {
        final repo = _SpyRepo(null);
        final b = bundleWith(
          accountUserId: 'U',
          profile: _profileJson(userId: 'U', guide: 'guru_x', prenom: 'Ana'),
        );
        final state = _state(repo: repo, userId: null);
        await _login(t, b: b, state: state);
        expect(find.byType(MainNavShell), findsOneWidget);
        expect(state.firstName, 'Ana');
        expect(state.selectedAdvisor, isNull);
      },
    );

    testWidgets('13 — même compte avec profil local : pas de fuite, serveur '
        'aligne', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(
        accountUserId: 'U-same',
        profile: _profileJson(
          userId: 'U-same',
          guide: 'maia',
          prenom: 'Nina',
          dateNaissance: '1994-01-01',
        ),
      );
      final state = _state(
        repo: repo,
        userId: 'U-same',
        firstName: 'Nina',
        advisor: 'Maïa',
        birthDate: DateTime(1994, 1, 1),
      );
      await _login(t, b: b, state: state);
      expect(repo.clears, 0, reason: 'même compte : aucun oubli');
      expect(state.firstName, 'Nina');
      expect(state.selectedAdvisor, 'Maïa');
      expect(state.userId, 'U-same');
    });

    testWidgets('14 — 401 sur profile : suit la politique auth (retour '
        'EmailAuthScreen, session purgée)', (t) async {
      final repo = _SpyRepo(null);
      final b = bundleWith(accountUserId: 'U', profileStatus: 401);
      final state = _state(repo: repo, userId: null);
      await _login(t, b: b, state: state);

      expect(find.byType(MainNavShell), findsNothing);
      expect(find.byType(EmailAuthScreen), findsOneWidget);
      expect(b.auth.status, AuthStatus.sessionExpired);
      expect(await b.tokens.read(), isNull);
    });
  });
}

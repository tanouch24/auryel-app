import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/account_api.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/legal_link_launcher.dart';
import 'package:auryel/data/local_user_data.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/onboarding/email_auth_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';

// ===========================================================================
// LOT MON COMPTE / RGPD / SUPPRESSION — fermeture Flutter.
// ===========================================================================

const _onboardingKey = 'auryel_onboarding_v1';

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

class _SpyLauncher implements LegalLinkLauncher {
  _SpyLauncher({this.result = true});
  bool result;
  final List<String> opened = [];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return result;
  }
}

Map<String, dynamic> _record() => {
  'userId': 'u-1',
  'selectedAdvisor': 'Maïa',
  'firstName': 'Nina',
  'birthDate': '1994-01-01T00:00:00.000',
  'portraitData': 'texte du portrait',
  'portraitFeedback': 'ok',
  'onboardingCompleted': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // C — DONNÉES LOCALES PURGÉES
  // -------------------------------------------------------------------------
  group('LocalUserData.clearPersonal', () {
    test('17 — purge auryel_onboarding_v1 (identité) + autres perso, '
        'conserve la préférence appareil', () async {
      SharedPreferences.setMockInitialValues({
        _onboardingKey: jsonEncode(_record()),
        'auryel.daily_mission.tirage': '2026-09-06',
        'auryel.daily_share.days': ['2026-09-01'],
        'auryel.daily_like.message.days': ['2026-09-01'],
        'auryel.memory.games_completed': 3,
        'auryel.memory.best_ms.facile': 42000,
        'auryel.experience_intro_seen.v1': true,
        'auryel.intro_video_seen.v1': true,
        'auryel.shop_cart.v1': '{}',
        'auryel.consultation.audio_muted.v1': true, // CONSERVÉE
      });
      await LocalUserData().clearPersonal();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'auryel.consultation.audio_muted.v1'});
      expect(prefs.getString(_onboardingKey), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // AuryelState.clearForAccountDeletion
  // -------------------------------------------------------------------------
  test('AuryelState.clearForAccountDeletion — vide l\'identité mémoire + '
      'persistée + notifie', () async {
    SharedPreferences.setMockInitialValues({
      _onboardingKey: jsonEncode(_record()),
    });
    final repo = LocalOnboardingRepository();
    final loaded = await repo.load();
    final state = AuryelState(repository: repo, initial: loaded);
    expect(state.firstName, 'Nina');
    expect(state.selectedAdvisor, 'Maïa');

    var notified = 0;
    state.addListener(() => notified++);
    await state.clearForAccountDeletion();

    expect(state.firstName, isNull);
    expect(state.selectedAdvisor, isNull);
    expect(state.birthDate, isNull);
    expect(state.portraitData, isNull);
    expect(state.userId, isNull);
    expect(state.onboardingCompleted, isFalse);
    expect(notified, greaterThanOrEqualTo(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_onboardingKey), isNull);
  });

  // -------------------------------------------------------------------------
  // B/E — AuthController.deleteAccount : succès -> purge complète
  // -------------------------------------------------------------------------
  group('AuthController.deleteAccount', () {
    AuthController build(
      Future<http.Response> Function(http.Request) handler, {
      String? token = 'tok',
    }) {
      final client = ApiClient(
        httpClient: MockClient(handler),
        baseUrl: 'http://test.local',
      );
      return AuthController(
        repository: AuthRepository(
          api: AuthApi(client),
          tokenStore: InMemoryTokenStore(token),
        ),
        profileApi: ProfileApi(client),
        consultationApi: ConsultationApi(client),
        tirageApi: TirageApi(client),
        accountApi: AccountApi(client),
        localUserData: LocalUserData(),
      );
    }

    test('8/9/16 — succès serveur -> auryel_onboarding_v1 purgé + token purgé '
        '+ signedOut', () async {
      SharedPreferences.setMockInitialValues({
        _onboardingKey: jsonEncode(_record()),
        'auryel.daily_mission.tirage': '2026-09-06',
        'auryel.consultation.audio_muted.v1': true,
      });
      final c = build((req) async {
        expect(req.method, 'DELETE');
        expect(req.url.path, '/api/app/account');
        return _json({'status': 'deleted'});
      });
      final out = await c.deleteAccount();
      expect(out, AccountDeletionOutcome.ok);
      expect(await c.currentToken(), isNull);
      expect(c.status, AuthStatus.signedOut);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_onboardingKey), isNull);
      expect(prefs.getKeys(), {'auryel.consultation.audio_muted.v1'});
    });

    test(
      '11/12/13 — réseau KO -> retryable, RIEN purgé (identité conservée)',
      () async {
        SharedPreferences.setMockInitialValues({
          _onboardingKey: jsonEncode(_record()),
        });
        final c = build((_) async => throw http.ClientException('offline'));
        expect(await c.deleteAccount(), AccountDeletionOutcome.retryable);
        expect(await c.currentToken(), 'tok');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_onboardingKey), isNotNull);
      },
    );

    test('14 — 401 -> unauthorized, jeton mort purgé, sessionExpired, '
        'PAS de "compte supprimé"', () async {
      SharedPreferences.setMockInitialValues({
        _onboardingKey: jsonEncode(_record()),
      });
      final c = build((_) async => _json({'error': 'unauthorized'}, 401));
      expect(await c.deleteAccount(), AccountDeletionOutcome.unauthorized);
      expect(await c.currentToken(), isNull);
      expect(c.status, AuthStatus.sessionExpired);
      // L'identité locale n'est PAS purgée (le serveur n'a rien confirmé).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_onboardingKey), isNotNull);
    });

    for (final code in const [403, 404, 409, 422, 500]) {
      test('E — HTTP $code -> retryable, session conservée', () async {
        final c = build((_) async => _json({'error': 'x'}, code));
        expect(await c.deleteAccount(), AccountDeletionOutcome.retryable);
        expect(await c.currentToken(), 'tok');
      });
    }
  });

  // -------------------------------------------------------------------------
  // J/K — LegalLinkRow : null -> inerte ; URL -> launcher ; échec -> message
  // -------------------------------------------------------------------------
  group('LegalLinkRow', () {
    Future<void> pump(
      WidgetTester t,
      String? url, {
      required LegalLinkLauncher launcher,
    }) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LegalLinkRow(
            label: 'Politique de confidentialité',
            url: url,
            launcher: launcher,
          ),
        ),
      ),
    );

    testWidgets('18/21 — url null -> « Bientôt disponible », tap inerte, '
        'aucun launcher, aucun crash', (t) async {
      final spy = _SpyLauncher();
      await pump(t, null, launcher: spy);
      expect(find.text('Bientôt disponible'), findsOneWidget);
      // pas d'InkWell cliquable
      expect(find.byType(InkWell), findsNothing);
      expect(t.takeException(), isNull);
      expect(spy.opened, isEmpty);
    });

    testWidgets('19 — url réelle -> tap appelle launcher.open(url)', (t) async {
      final spy = _SpyLauncher(result: true);
      await pump(t, 'https://auryel.example/privacy', launcher: spy);
      expect(find.text('Bientôt disponible'), findsNothing);
      await t.tap(find.text('Politique de confidentialité'));
      await t.pumpAndSettle();
      expect(spy.opened, ['https://auryel.example/privacy']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('20 — échec d\'ouverture -> snackbar sobre', (t) async {
      final spy = _SpyLauncher(result: false);
      await pump(t, 'https://auryel.example/privacy', launcher: spy);
      await t.tap(find.text('Politique de confidentialité'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Impossible d’ouvrir la page'),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // K — implémentations LegalLinkLauncher
  // -------------------------------------------------------------------------
  group('LegalLinkLauncher', () {
    test('NoopLegalLinkLauncher -> false', () async {
      expect(
        await const NoopLegalLinkLauncher().open('https://x.example'),
        isFalse,
      );
    });
    test('UrlLauncher : refuse non-HTTPS / URL invalide', () async {
      const l = UrlLauncherLegalLinkLauncher();
      expect(await l.open('http://x.example'), isFalse); // pas https
      expect(await l.open('pas une url'), isFalse);
      expect(await l.open('https://'), isFalse); // host vide
      expect(await l.open('ftp://x.example'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // G/P — Dashboard : suppression complète -> identité mémoire vidée + sortie
  // -------------------------------------------------------------------------
  testWidgets('10/16 — flux complet : DELETE 200 -> AuryelState vidé + '
      'EmailAuthScreen, plus de Dashboard', (t) async {
    SharedPreferences.setMockInitialValues({
      _onboardingKey: jsonEncode(_record()),
      'auryel.consultation.audio_muted.v1': true,
    });
    var deleteCalls = 0;
    final client = ApiClient(
      httpClient: MockClient((req) async {
        if (req.method == 'DELETE' && req.url.path == '/api/app/account') {
          deleteCalls++;
          return _json({'status': 'deleted'});
        }
        return _json({}, 404);
      }),
      baseUrl: 'http://test.local',
    );
    final auth = AuthController(
      repository: AuthRepository(
        api: AuthApi(client),
        tokenStore: InMemoryTokenStore('tok'),
      ),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
      accountApi: AccountApi(client),
      localUserData: LocalUserData(),
    );
    addTearDown(auth.dispose);
    final state = AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u-1',
        selectedAdvisor: 'Maïa',
        firstName: 'Nina',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 'texte',
        portraitFeedback: 'ok',
        onboardingCompleted: true,
      ),
    );

    await t.pumpWidget(
      AuthScope(
        controller: auth,
        child: AuryelStateScope(
          state: state,
          child: MaterialApp(
            home: DashboardScreen(
              thoughtRepository: DailyThoughtRepository(
                seed: [
                  DailyThought(
                    id: 1,
                    publishDate: DateTime(2026, 9, 4),
                    phrase: 'x',
                    interpretation: 'y',
                    imageAsset:
                        'assets/pensees/publications/01_2026-09-04.webp',
                  ),
                ],
              ),
              showBackButton: false,
            ),
          ),
        ),
      ),
    );
    await t.pump();

    await t.ensureVisible(find.text('Supprimer mon compte'));
    await t.tap(find.text('Supprimer mon compte'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Supprimer mon compte'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'SUPPRIMER');
    await t.pump();
    await t.tap(find.text('Supprimer définitivement'));
    await t.pumpAndSettle();

    expect(deleteCalls, 1);
    expect(auth.status, AuthStatus.signedOut);
    expect(await auth.currentToken(), isNull);
    // Identité EN MÉMOIRE vidée.
    expect(state.firstName, isNull);
    expect(state.selectedAdvisor, isNull);
    expect(state.birthDate, isNull);
    // Sortie compte.
    expect(find.byType(EmailAuthScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
    // Snapshot persisté purgé.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_onboardingKey), isNull);
    expect(prefs.getKeys(), {'auryel.consultation.audio_muted.v1'});
  });

  // -------------------------------------------------------------------------
  // A/H/J — Dashboard : 3 liens juridiques null -> inertes, aucun launcher
  // -------------------------------------------------------------------------
  testWidgets('21/22 — Dashboard : liens juridiques null = « Bientôt '
      'disponible » ×3, aucun launcher, aucune donnée technique', (t) async {
    final spy = _SpyLauncher();
    await t.pumpWidget(
      AuryelStateScope(
        state: AuryelState(
          repository: LocalOnboardingRepository(),
          initial: OnboardingRecord(
            userId: 'uuid-technique-secret',
            selectedAdvisor: 'Séléna',
            firstName: 'Nina',
            birthDate: DateTime(1994, 1, 1),
            portraitData: 'x',
            portraitFeedback: 'y',
            onboardingCompleted: true,
          ),
        ),
        child: MaterialApp(
          home: DashboardScreen(
            thoughtRepository: DailyThoughtRepository(
              seed: [
                DailyThought(
                  id: 1,
                  publishDate: DateTime(2026, 9, 4),
                  phrase: 'x',
                  interpretation: 'y',
                  imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
                ),
              ],
            ),
            showBackButton: false,
            legalLinkLauncher: spy,
          ),
        ),
      ),
    );
    await t.pump();
    await t.ensureVisible(find.text('INFORMATIONS & CONFIDENTIALITÉ'));

    expect(find.text('Bientôt disponible'), findsNWidgets(3));
    expect(spy.opened, isEmpty);
    // aucune donnée technique
    expect(find.textContaining('uuid-technique-secret'), findsNothing);
    expect(find.textContaining('Bearer'), findsNothing);
    expect(find.textContaining('/api/'), findsNothing);
  });
}

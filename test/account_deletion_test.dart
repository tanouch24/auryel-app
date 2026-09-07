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
import 'package:auryel/data/local_user_data.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/onboarding/email_auth_screen.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';

// ===========================================================================
// PARTIE K — SUPPRESSION RÉELLE DE COMPTE
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

class _Rig {
  _Rig({int deleteStatus = 200, bool deleteThrows = false}) {
    final client = ApiClient(
      httpClient: MockClient((req) async {
        if (req.method == 'DELETE' && req.url.path == '/api/app/account') {
          deleteCalls++;
          if (deleteThrows) throw http.ClientException('offline');
          if (deleteStatus >= 300) return _json({'error': 'x'}, deleteStatus);
          return _json({'status': 'deleted'});
        }
        return _json({}, 404);
      }),
      baseUrl: 'http://test.local',
    );
    tokens = InMemoryTokenStore('tok');
    auth = AuthController(
      repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
      accountApi: AccountApi(client),
      localUserData: LocalUserData(),
    );
  }

  late final AuthController auth;
  late final InMemoryTokenStore tokens;
  int deleteCalls = 0;
}

DailyThoughtRepository _thoughts() => DailyThoughtRepository(
  seed: [
    DailyThought(
      id: 1,
      publishDate: DateTime(2026, 9, 4),
      phrase: 'x',
      interpretation: 'y',
      imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
    ),
  ],
);

AuryelState _state() => AuryelState(
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

Future<void> _pump(WidgetTester t, _Rig rig) => t.pumpWidget(
  AuthScope(
    controller: rig.auth,
    child: AuryelStateScope(
      state: _state(),
      child: MaterialApp(
        home: DashboardScreen(
          thoughtRepository: _thoughts(),
          showBackButton: false,
        ),
      ),
    ),
  ),
);

Future<void> _openStep1(WidgetTester t) async {
  await t.ensureVisible(find.text('Supprimer mon compte'));
  await t.tap(find.text('Supprimer mon compte'));
  await t.pumpAndSettle();
}

Future<void> _confirmFully(WidgetTester t) async {
  await _openStep1(t);
  await t.tap(find.widgetWithText(TextButton, 'Supprimer mon compte'));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField).last, 'SUPPRIMER');
  await t.pump();
  await t.tap(find.text('Supprimer définitivement'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('K11 — l\'entrée « Supprimer mon compte » est visible', (
    t,
  ) async {
    final rig = _Rig();
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await t.pump();
    expect(find.text('Supprimer mon compte'), findsOneWidget);
  });

  testWidgets(
    'K12/K13 — 1re confirmation obligatoire ; annuler = aucun appel',
    (t) async {
      final rig = _Rig();
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _openStep1(t);

      expect(find.text('Supprimer mon compte ?'), findsOneWidget);
      expect(find.textContaining('irréversible'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();

      expect(rig.deleteCalls, 0);
      expect(await rig.tokens.read(), 'tok');
    },
  );

  testWidgets(
    'K12b — 2e confirmation : « Supprimer définitivement » verrouillé '
    'tant que « SUPPRIMER » n\'est pas saisi',
    (t) async {
      final rig = _Rig();
      addTearDown(rig.auth.dispose);
      await _pump(t, rig);
      await _openStep1(t);
      await t.tap(find.widgetWithText(TextButton, 'Supprimer mon compte'));
      await t.pumpAndSettle();

      expect(find.text('Confirmer la suppression'), findsOneWidget);
      final btn = t.widget<TextButton>(
        find.widgetWithText(TextButton, 'Supprimer définitivement'),
      );
      expect(btn.onPressed, isNull); // désactivé

      await t.enterText(find.byType(TextField).last, 'SUPPRIMER');
      await t.pump();
      final btn2 = t.widget<TextButton>(
        find.widgetWithText(TextButton, 'Supprimer définitivement'),
      );
      expect(btn2.onPressed, isNotNull);
    },
  );

  testWidgets('K14/K15/K16 — confirmation complète -> DELETE -> token purgé -> '
      'retour EmailAuthScreen', (t) async {
    final rig = _Rig();
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _confirmFully(t);

    expect(rig.deleteCalls, 1);
    expect(await rig.tokens.read(), isNull);
    expect(rig.auth.status, AuthStatus.signedOut);
    expect(find.byType(EmailAuthScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('K17/K18/K19 — échec réseau : token/session CONSERVÉS, message '
      'd\'erreur, AUCUNE purge locale', (t) async {
    SharedPreferences.setMockInitialValues({
      'auryel.daily_mission.tirage': '2026-09-06',
    });
    final rig = _Rig(deleteThrows: true);
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _confirmFully(t);

    expect(rig.deleteCalls, 1);
    expect(await rig.tokens.read(), 'tok'); // session conservée
    expect(rig.auth.status, isNot(AuthStatus.signedOut));
    expect(find.byType(DashboardScreen), findsOneWidget); // pas de navigation
    expect(
      find.textContaining('Impossible de supprimer ton compte'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), contains('auryel.daily_mission.tirage'));
  });

  testWidgets('K18b — échec 5xx : même comportement (session conservée)', (
    t,
  ) async {
    final rig = _Rig(deleteStatus: 500);
    addTearDown(rig.auth.dispose);
    await _pump(t, rig);
    await _confirmFully(t);

    expect(await rig.tokens.read(), 'tok');
    expect(
      find.textContaining('Impossible de supprimer ton compte'),
      findsOneWidget,
    );
  });
}

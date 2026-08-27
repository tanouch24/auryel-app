import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/main.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';

/// AuthController de test : jeton initial optionnel + réponse HTTP contrôlée.
AuthController _auth({
  String? token,
  http.Response Function(http.Request req)? respond,
  bool throwNetwork = false,
}) {
  final client = MockClient((req) async {
    if (throwNetwork) throw http.ClientException('offline');
    return respond?.call(req) ?? http.Response('{}', 200);
  });
  return AuthController(
    repository: AuthRepository(
      api: AuthApi(ApiClient(httpClient: client, baseUrl: 'http://test.local')),
      tokenStore: InMemoryTokenStore(token),
    ),
  );
}

AuryelState _completedOnboardingState({String userId = 'temp_deadbeef'}) {
  return AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: userId,
      selectedAdvisor: 'Séléna',
      firstName: 'Nina',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'texte',
      portraitFeedback: 'ok',
      onboardingCompleted: true,
    ),
  );
}

Future<void> _bootSplash(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2100)); // délai mini du splash
  await tester.pumpAndSettle();
}

const _emailScreenMarker = 'Ton adresse email';
const _homeMarker = 'Découvrir le message du jour';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Splash : nouvel utilisateur -> parcours onboarding', (tester) async {
    final state = AuryelState(repository: LocalOnboardingRepository());

    await tester.pumpWidget(AuryelApp(state: state, auth: _auth()));
    expect(find.text('AURYEL'), findsOneWidget);

    await _bootSplash(tester);

    expect(find.text('Choisis ton conseiller'), findsOneWidget);
  });

  testWidgets(
      'Splash : onboarding terminé + AUCUN token -> EmailAuthScreen (pas l’app)',
      (tester) async {
    await tester.pumpWidget(
      AuryelApp(state: _completedOnboardingState(), auth: _auth(token: null)),
    );
    await _bootSplash(tester);

    expect(find.text(_emailScreenMarker), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
  });

  testWidgets(
      'Splash : onboarding terminé + ancien userId temp_xxx + AUCUN token '
      '-> EmailAuthScreen', (tester) async {
    await tester.pumpWidget(
      AuryelApp(
        state: _completedOnboardingState(userId: 'temp_0011aabb'),
        auth: _auth(token: null),
      ),
    );
    await _bootSplash(tester);

    expect(find.text(_emailScreenMarker), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
  });

  testWidgets('Splash : token valide (GET /account 200) -> MainNavShell',
      (tester) async {
    await tester.pumpWidget(
      AuryelApp(
        state: _completedOnboardingState(),
        auth: _auth(
          token: 'good-tok',
          respond: (_) => http.Response(
            '{"user_id":"uuid-1","email":"a@b.co"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    await _bootSplash(tester);

    expect(find.text(_homeMarker), findsOneWidget);
    expect(find.text(_emailScreenMarker), findsNothing);
  });

  testWidgets(
      'Splash : token présent + erreur réseau -> token conservé + MainNavShell '
      '(mode dégradé)', (tester) async {
    final auth = _auth(token: 'keep-tok', throwNetwork: true);

    await tester.pumpWidget(
      AuryelApp(state: _completedOnboardingState(), auth: auth),
    );
    await _bootSplash(tester);

    expect(find.text(_homeMarker), findsOneWidget);
    expect(auth.status, AuthStatus.networkError);
  });

  testWidgets('Splash : token rejeté (401) -> purge + EmailAuthScreen',
      (tester) async {
    final tokens = InMemoryTokenStore('bad-tok');
    final auth = AuthController(
      repository: AuthRepository(
        api: AuthApi(ApiClient(
          httpClient: MockClient((_) async => http.Response(
                '{"error":"unauthorized"}',
                401,
                headers: {'content-type': 'application/json'},
              )),
          baseUrl: 'http://test.local',
        )),
        tokenStore: tokens,
      ),
    );

    await tester.pumpWidget(
      AuryelApp(state: _completedOnboardingState(), auth: auth),
    );
    await _bootSplash(tester);

    expect(find.text(_emailScreenMarker), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
    expect(await tokens.read(), isNull); // purgé
    expect(auth.status, AuthStatus.sessionExpired);
  });
}

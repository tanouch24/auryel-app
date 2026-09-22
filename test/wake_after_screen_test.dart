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
import 'package:auryel/data/advisor_audio.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/advisor_selector_screen.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/wake_after_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';

// ===========================================================================
// GROS LOT « feed méditation + réveil vocal » — écran « Belle journée » :
// le CTA « Parler à mon conseiller » réutilise le mécanisme EXISTANT
// (sélecteur -> fil existant ou `openAdvisor`), EXACTEMENT comme
// `TirageScreen._talkAboutTirage` (J6-F2 §13) — jamais un conseiller
// parallèle propre au réveil.
// ===========================================================================

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

class _FakeAudio implements AdvisorAudio {
  @override
  Future<void> play(
    String assetPath, {
    Duration fadeIn = Duration.zero,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

typedef _Env = ({
  AuthController auth,
  ConsultationController controller,
  List<String> posts,
  List<Map<String, dynamic>> openBodies,
});

_Env _env({List<Map<String, dynamic>> threads = const []}) {
  final posts = <String>[];
  final openBodies = <Map<String, dynamic>>[];
  final current = List<Map<String, dynamic>>.from(threads);
  final client = ApiClient(
    httpClient: MockClient((req) async {
      posts.add('${req.method} ${req.url.path}');
      final p = req.url.path;
      if (p == '/api/consultation/list') {
        return _json({'consultations': current});
      }
      if (p == '/api/consultation/open') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        openBodies.add(body);
        final adv = body['advisor_id'] as String;
        return _json({
          'consultation': {
            'id': 'c-open-$adv',
            'advisor_id': adv,
            'started_at': '2026-09-01T10:00:00Z',
            'expires_at': '2026-09-01T12:00:00Z',
            'credit_source': 'time',
            'opened_now': true,
          },
        });
      }
      if (p == '/api/consultation/messages') {
        return _json({
          'consultation_id': req.url.queryParameters['consultation_id'],
          'messages': <dynamic>[],
        });
      }
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  final capi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: capi,
    tirageApi: TirageApi(client),
  );
  final controller = ConsultationController(api: capi, auth: auth);
  return (
    auth: auth,
    controller: controller,
    posts: posts,
    openBodies: openBodies,
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Env e, {
  String? pendingContext,
}) async {
  addTearDown(e.controller.dispose);
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
  await tester.pumpWidget(
    AuthScope(
      controller: e.auth,
      child: AuryelStateScope(
        state: state,
        child: ConsultationScope(
          controller: e.controller,
          child: MaterialApp(
            home: WakeAfterScreen(
              selectorAudioOverride: _FakeAudio(),
              pendingContext: pendingContext,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'le retour du test depuis onboarding revient sur l\'étape Réveil',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: const RouteSettings(
                        name: WakeAfterScreen.onboardingRouteName,
                      ),
                      builder: (_) => const Text('Étape Réveil onboarding'),
                    ),
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const WakeAfterScreen(returnToOnboarding: true),
                    ),
                  );
                },
                child: const Text('ouvrir réveil'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir réveil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer ma journée'));
      await tester.pumpAndSettle();

      expect(find.text('Étape Réveil onboarding'), findsOneWidget);
      expect(find.byType(WakeAfterScreen), findsNothing);
    },
  );

  testWidgets('affiche « Belle journée » + les deux CTA attendus', (
    tester,
  ) async {
    await _pump(tester, _env());
    expect(find.text('Belle journée'), findsOneWidget);
    expect(find.text('Parler à mon conseiller'), findsOneWidget);
    expect(find.text('Continuer ma journée'), findsOneWidget);
  });

  testWidgets(
    '« Continuer ma journée » ramène à l\'Accueil (retour système bloqué '
    'idem : même effet)',
    (tester) async {
      await _pump(tester, _env());
      await tester.tap(find.text('Continuer ma journée'));
      // MainNavShell monte aussi (IndexedStack) le feed Méditation, qui
      // instancie de VRAIS lecteurs audio/vidéo (aucun canal plateforme en
      // test) : `pumpAndSettle` n'a jamais de raison de « se stabiliser »
      // avec ces contrôleurs réels en jeu -> quelques `pump` bornés suffisent
      // pour observer la navigation, sans attendre un impossible repos total.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WakeAfterScreen), findsNothing);
    },
  );

  testWidgets('le contexte réveil devient un brouillon unique du chat', (
    tester,
  ) async {
    final e = _env();
    await _pump(
      tester,
      e,
      pendingContext: 'Je viens de terminer mon réveil Auryel.',
    );

    await tester.tap(find.text('Parler à mon conseiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parler avec Séléna'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.initialMessage, 'Je viens de terminer mon réveil Auryel.');
  });

  testWidgets(
    '« Parler à mon conseiller » ouvre le SÉLECTEUR (jamais un conseiller '
    'imposé) puis, sans fil existant, `openAdvisor` -> ChatScreen',
    (tester) async {
      final e = _env();
      await _pump(tester, e);

      await tester.tap(find.text('Parler à mon conseiller'));
      await tester.pumpAndSettle();
      expect(find.byType(AdvisorSelectorScreen), findsOneWidget);

      await tester.tap(find.text('Parler avec Séléna'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(e.openBodies.single, {'advisor_id': 'selena'});
      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chat.consultationId, 'c-open-selena');
      expect(chat.advisor.name, 'Séléna');
    },
  );

  testWidgets('un fil existant pour ce conseiller est REPRIS (jamais de 2e '
      '`POST /open`)', (tester) async {
    final e = _env(
      threads: [
        {
          'id': 'c-selena-existing',
          'advisor_id': 'selena',
          'started_at': '2026-09-01T10:00:00Z',
          'window_active': false,
          'preview': 'salut',
        },
      ],
    );
    await _pump(tester, e);

    await tester.tap(find.text('Parler à mon conseiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre avec Séléna'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-selena-existing');
    expect(e.posts.where((p) => p == 'POST /api/consultation/open'), isEmpty);
  });

  testWidgets(
    'annuler le sélecteur -> reste sur « Belle journée », aucun appel réseau '
    'de consultation',
    (tester) async {
      final e = _env();
      await _pump(tester, e);

      await tester.tap(find.text('Parler à mon conseiller'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      expect(find.byType(WakeAfterScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(
        e.posts.where(
          (p) =>
              p.contains('consultation/open') ||
              p.contains('consultation/message'),
        ),
        isEmpty,
      );
    },
  );
}

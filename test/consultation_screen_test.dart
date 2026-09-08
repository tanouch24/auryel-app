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
import 'package:auryel/data/advisor_audio.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/advisor_selector_screen.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/consultation_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// J6-F2 — onglet CONSULTATION = LISTE « Consultations en cours ».
// Il N'Y A PAS de conseiller référent : aucun fil n'est choisi via
// selectedAdvisor, aucun repli kAdvisors.first, aucun changeAdvisor.
// ===========================================================================

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

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _summary({
  required String id,
  required String advisorId,
  bool windowActive = false,
  Object? preview = 'dernier message',
}) => {
  'id': id,
  'advisor_id': advisorId,
  'started_at': '2026-09-01T10:00:00Z',
  'last_activity_at': '2026-09-01T10:05:00Z',
  'window_active': windowActive,
  'preview': ?preview,
};

Map<String, dynamic> _openBody({
  required String id,
  required String advisorId,
}) => {
  'consultation': {
    'id': id,
    'advisor_id': advisorId,
    'started_at': '2026-09-01T10:00:00Z',
    'expires_at': '2026-09-01T12:00:00Z',
    'credit_source': 'time',
    'opened_now': true,
  },
};

typedef _Rig = ({
  ConsultationController controller,
  AuthController auth,
  List<String> hits,
  List<Map<String, dynamic>> openBodies,
  List<Uri> messageGets,
});

_Rig _rig({List<Map<String, dynamic>> list = const [], String? token = 'tok'}) {
  final hits = <String>[];
  final openBodies = <Map<String, dynamic>>[];
  final messageGets = <Uri>[];
  var current = List<Map<String, dynamic>>.from(list);

  final client = ApiClient(
    httpClient: MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      final path = req.url.path;
      if (path == '/api/consultation/list') {
        return _json({'consultations': current});
      }
      if (path == '/api/consultation/open') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        openBodies.add(body);
        final advisorId = body['advisor_id'] as String;
        final id = 'c-new-$advisorId';
        current = [
          ...current,
          _summary(id: id, advisorId: advisorId, preview: null),
        ];
        return _json(_openBody(id: id, advisorId: advisorId));
      }
      if (path == '/api/consultation/messages') {
        messageGets.add(req.url);
        final wanted = req.url.queryParameters['consultation_id'];
        return _json({'consultation_id': wanted, 'messages': <dynamic>[]});
      }
      if (path == '/api/consultation/state') {
        return _json({'consultation': null, 'quota': null});
      }
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  final capi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(client),
    consultationApi: capi,
    tirageApi: TirageApi(client),
  );
  final controller = ConsultationController(api: capi, auth: auth);
  addTearDown(controller.dispose);
  return (
    controller: controller,
    auth: auth,
    hits: hits,
    openBodies: openBodies,
    messageGets: messageGets,
  );
}

AuryelState _state() => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u',
    selectedAdvisor: 'Séléna', // ne doit JAMAIS servir à reprendre un fil
    firstName: 'N',
    birthDate: DateTime(1994, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: true,
  ),
);

Future<void> _pump(
  WidgetTester t,
  _Rig rig, {
  int currentIndex = kTabConsultation,
  List<int>? tabTaps,
}) {
  return t.pumpWidget(
    AuthScope(
      controller: rig.auth,
      child: ConsultationScope(
        controller: rig.controller,
        child: AuryelStateScope(
          state: _state(),
          child: MaterialApp(
            home: MainNavScope(
              goToTab: tabTaps?.add ?? (_) {},
              currentIndex: currentIndex,
              child: Scaffold(
                body: ConsultationScreen(audioOverride: _FakeAudio()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1 titre « Consultations en cours » + refresh au chargement', (
    t,
  ) async {
    final rig = _rig();
    await _pump(t, rig);
    await t.pumpAndSettle();
    expect(find.text('Consultations en cours'), findsOneWidget);
    expect(rig.hits, contains('GET /api/consultation/list'));
  });

  testWidgets('2/3 liste vide propre + CTA « Choisir un conseiller »', (
    t,
  ) async {
    final rig = _rig(list: const []);
    await _pump(t, rig);
    await t.pumpAndSettle();
    expect(
      find.text('Tu n’as pas encore de consultation en cours.'),
      findsOneWidget,
    );
    expect(find.text('Choisir un conseiller'), findsOneWidget);
    expect(find.text('Demander un autre avis'), findsNothing);
  });

  testWidgets('4/5/6 plusieurs consultations : Ezra + Séléna séparés, bon '
      'aperçu par fil', (t) async {
    final rig = _rig(
      list: [
        _summary(id: 'c-ezra', advisorId: 'ezra', preview: 'aperçu Ezra'),
        _summary(
          id: 'c-selena',
          advisorId: 'selena',
          preview: 'aperçu Séléna',
          windowActive: true,
        ),
      ],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();

    expect(find.text('Ezra'), findsOneWidget);
    expect(find.text('Séléna'), findsOneWidget);
    // aperçu rattaché au bon fil.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Ezra'),
          matching: find.byType(InkWell),
        ),
        matching: find.text('aperçu Ezra'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Séléna'),
          matching: find.byType(InkWell),
        ),
        matching: find.text('aperçu Séléna'),
      ),
      findsOneWidget,
    );
    // statut léger « En cours » sur le fil windowActive.
    expect(find.text('En cours'), findsOneWidget);
    // CTA permanent.
    expect(find.text('Demander un autre avis'), findsOneWidget);
  });

  testWidgets('7/8/9/10 tap Ezra -> ChatScreen(id Ezra, advisor Ezra) ; tap '
      'Séléna -> ChatScreen(id Séléna) ; selectedAdvisor non utilisé', (
    t,
  ) async {
    final rig = _rig(
      list: [
        _summary(id: 'c-ezra', advisorId: 'ezra'),
        _summary(id: 'c-selena', advisorId: 'selena'),
      ],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();

    await t.tap(find.text('Ezra'));
    await t.pumpAndSettle();
    var chat = t.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-ezra');
    expect(chat.advisor.guideKey, 'ezra'); // pas « selena » (selectedAdvisor)
    // historique ciblé par consultation_id.
    expect(rig.messageGets.last.queryParameters['consultation_id'], 'c-ezra');

    await t.tap(find.byIcon(Icons.arrow_back_ios_new));
    await t.pumpAndSettle();

    await t.tap(find.text('Séléna'));
    await t.pumpAndSettle();
    chat = t.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-selena');
    expect(chat.advisor.guideKey, 'selena');
  });

  testWidgets('11 advisor inconnu -> erreur contrôlée, aucun ChatScreen', (
    t,
  ) async {
    final rig = _rig(
      list: [_summary(id: 'c-x', advisorId: 'inconnu_xyz')],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();

    await t.tap(find.text('Conseiller')); // nom de repli de la carte
    await t.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(
      find.text('Cette consultation est momentanément indisponible.'),
      findsOneWidget,
    );
  });

  testWidgets('12/13 « Demander un autre avis » -> conseiller déjà existant '
      'rouvre le fil existant (pas de POST /open)', (t) async {
    final rig = _rig(
      list: [_summary(id: 'c-ezra', advisorId: 'ezra')],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();

    await t.tap(find.text('Demander un autre avis'));
    await t.pumpAndSettle();
    expect(find.byType(AdvisorSelectorScreen), findsOneWidget);

    // Ezra = kAdvisors[7] : on fait défiler le feed vertical jusqu'à sa page.
    for (var i = 0; i < 7; i++) {
      await t.fling(find.byType(PageView), const Offset(0, -500), 1400);
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Reprendre avec Ezra'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();

    final chat = t.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-ezra'); // le fil EXISTANT
    expect(chat.advisor.guideKey, 'ezra');
    expect(rig.hits.where((h) => h == 'POST /api/consultation/open'), isEmpty);
  });

  testWidgets('14/15 nouveau conseiller -> openAdvisor(guideKey) puis '
      'ChatScreen sur le fil renvoyé ; aucun PATCH profil', (t) async {
    final rig = _rig(
      list: [_summary(id: 'c-ezra', advisorId: 'ezra')],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();

    await t.tap(find.text('Demander un autre avis'));
    await t.pumpAndSettle();
    // Séléna = kAdvisors[0], page visible d'emblée ; pas de fil -> « Demander
    // un avis ».
    await t.tap(find.text('Demander un avis avec Séléna'));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();

    expect(rig.openBodies.single, {'advisor_id': 'selena'});
    final chat = t.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-new-selena');
    expect(chat.advisor.guideKey, 'selena');
    expect(rig.hits.any((h) => h.contains('profile')), isFalse);
  });

  testWidgets('16/28 retour du chat -> LISTE, refresh, aucun fil rouvert '
      'automatiquement', (t) async {
    final rig = _rig(
      list: [_summary(id: 'c-ezra', advisorId: 'ezra')],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();

    await t.tap(find.text('Ezra'));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    final listGetsBefore = rig.hits
        .where((h) => h == 'GET /api/consultation/list')
        .length;

    await t.tap(find.byIcon(Icons.arrow_back_ios_new));
    await t.pumpAndSettle();

    // De retour sur la liste.
    expect(find.text('Consultations en cours'), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
    // refresh au retour.
    expect(
      rig.hits.where((h) => h == 'GET /api/consultation/list').length,
      greaterThan(listGetsBefore),
    );
  });

  testWidgets('29 wallet / temps disponible affiché', (t) async {
    final rig = _rig(
      list: [_summary(id: 'c-ezra', advisorId: 'ezra')],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();
    expect(find.textContaining('Temps disponible'), findsOneWidget);
  });

  testWidgets('30 aucun ancien CTA « Reprendre » (nu) dans l\'onglet', (
    t,
  ) async {
    final rig = _rig(
      list: [_summary(id: 'c-ezra', advisorId: 'ezra')],
    );
    await _pump(t, rig);
    await t.pumpAndSettle();
    expect(find.text('Reprendre'), findsNothing);
    expect(find.text('Reprendre ma consultation'), findsNothing);
  });

  for (final w in const [360.0, 384.0, 430.0]) {
    testWidgets('17 aucun overflow à ${w.toInt()} dp', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 820);
      addTearDown(t.view.reset);
      final rig = _rig(
        list: [
          _summary(id: 'c-ezra', advisorId: 'ezra'),
          _summary(id: 'c-selena', advisorId: 'selena', windowActive: true),
        ],
      );
      await _pump(t, rig);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}

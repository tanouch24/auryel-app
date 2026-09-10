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
import 'package:auryel/data/tarot_deck.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/advisor_selector_screen.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';

/// Interprétation SERVEUR volontairement différente du texte local
/// (`tarot_deck.dart`) — sert à prouver que l'UI affiche le texte du backend.
String _serverInterp(String key) => 'SERVEUR · interprétation de $key';
const _serverCombined = 'LECTURE SERVEUR — assemblage renvoyé par le backend.';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _tirageBody(List<String> keys) => {
  'tirage_id': 'tir-abc-123',
  'card_keys': keys,
  'cards': [
    for (final k in keys)
      {'key': k, 'name': 'NOM-$k', 'interpretation': _serverInterp(k)},
  ],
  'combined_interpretation': _serverCombined,
  'advisor_id': 'maia',
  'created_at': '2026-08-31T10:00:00Z',
};

typedef _Env = ({
  AuthController auth,
  List<String> posts,
  List<List<String>> keysSent,
});

typedef _MultiEnv = ({
  AuthController auth,
  ConsultationController controller,
  List<String> posts,
  List<Map<String, dynamic>> openBodies,
  List<Map<String, dynamic>> msgBodies,
});

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

_Env _env(
  Future<http.Response> Function(http.Request req, List<String> cardKeys)
  onPost, {
  String? token = 'tok',
}) {
  final posts = <String>[];
  final keysSent = <List<String>>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      posts.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/tirages' && req.method == 'POST') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final keys = (body['card_keys'] as List).cast<String>();
        keysSent.add(keys);
        return onPost(req, keys);
      }
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  return (auth: auth, posts: posts, keysSent: keysSent);
}

Widget _wrap(AuthController auth, {String? selectedAdvisor = 'Maïa'}) {
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u-1',
      selectedAdvisor: selectedAdvisor,
      firstName: 'Nina',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'texte',
      portraitFeedback: 'ok',
      onboardingCompleted: true,
    ),
  );
  return AuthScope(
    controller: auth,
    child: AuryelStateScope(
      state: state,
      child: const MaterialApp(home: TirageScreen()),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AuthController auth, {
  String? selectedAdvisor = 'Maïa',
}) async {
  await tester.pumpWidget(_wrap(auth, selectedAdvisor: selectedAdvisor));
  await tester.pumpAndSettle();
}

Finder _back(int i) => find.byKey(ValueKey('tarot-back-$i'));

dynamic _st(WidgetTester tester) => tester.state(find.byType(TirageScreen));

Future<void> _tap(WidgetTester tester, int i) async {
  await tester.tap(_back(i));
  await tester.pumpAndSettle();
}

Future<void> _selectThree(
  WidgetTester tester, {
  List<int> indexes = const [0, 1, 2],
}) async {
  for (final i in indexes) {
    await _tap(tester, i);
  }
}

Future<void> _reveal(WidgetTester tester) async {
  await tester.tap(find.text('Révéler mon tirage'));
  await tester.pumpAndSettle();
}

/// B8.2 — l'écran Tirage a désormais un fond « tapis » (assets/images/tarot_table_blank.png,
/// 1 Image d'ambiance). Ce finder ne compte QUE les FACES de cartes
/// (`assets/images/tarot/<slug>.png`), pour garder l'intention des tests.
final _cardFaceImages = find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName.contains('images/tarot/'),
);

void main() {
  // -------------------------------------------------------------------------
  // A. choix des 3 cartes — comportement T2 inchangé
  // -------------------------------------------------------------------------
  testWidgets('A. choix 3 cartes : compteur, ordre, pas de 4e, aucune image', (
    tester,
  ) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await _pump(tester, e.auth);

    expect(find.text('Ton tirage'), findsOneWidget);
    expect(find.text('Choisis trois cartes.'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
    expect(_cardFaceImages, findsNothing);
    expect(find.text('Révéler mon tirage'), findsNothing);
    // B8.2 §E — le « tapis » de fond réutilisé des publications est bien posé.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/tarot_table_blank.png',
      ),
      findsOneWidget,
    );

    final deck = List<String>.from(_st(tester).debugDeckKeys);
    await _tap(tester, 4);
    expect(find.text('1 / 3'), findsOneWidget);
    await _tap(tester, 1);
    await _tap(tester, 7);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Révéler mon tirage'), findsOneWidget);

    await _tap(tester, 9); // 4e tap ignoré
    expect(_st(tester).debugSelectionKeys, [deck[4], deck[1], deck[7]]);
    expect(e.posts, isEmpty); // aucun appel réseau avant "Révéler"
  });

  // -------------------------------------------------------------------------
  // B. « Révéler » -> POST /api/tirages avec les 3 clés dans l'ordre de tap
  // -------------------------------------------------------------------------
  testWidgets('B. Révéler -> POST /api/tirages { card_keys } dans l\'ordre', (
    tester,
  ) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await _pump(tester, e.auth);
    final deck = List<String>.from(_st(tester).debugDeckKeys);

    await _selectThree(tester, indexes: [5, 2, 8]);
    // D. avant réponse : aucun CTA chat encore
    expect(find.textContaining('En parler avec'), findsNothing);

    await _reveal(tester);

    expect(e.posts, ['POST /api/tirages']);
    expect(e.keysSent.single, [deck[5], deck[2], deck[8]]);
  });

  // -------------------------------------------------------------------------
  // E/F/G. révélation = données SERVEUR (texte différent du local)
  // -------------------------------------------------------------------------
  testWidgets(
    'E/F/G. reveal affiche 3 images + noms/interp + lecture SERVEUR',
    (tester) async {
      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      await _pump(tester, e.auth);
      final deck = List<String>.from(_st(tester).debugDeckKeys);
      await _selectThree(tester, indexes: [0, 1, 2]);
      await _reveal(tester);

      expect(_cardFaceImages, findsNWidgets(3));
      expect(find.byKey(const ValueKey('tarot-reveal-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('tarot-reveal-2')), findsOneWidget);

      for (final k in [deck[0], deck[1], deck[2]]) {
        // texte SERVEUR affiché
        expect(find.text('NOM-$k'), findsOneWidget);
        expect(find.text(_serverInterp(k)), findsOneWidget);
        // le texte LOCAL de tarot_deck NE doit PAS être affiché
        final local = tarotArcanaByKey(k)!;
        expect(find.text(local.interpretation), findsNothing);
      }
      expect(find.text('Ce que dit l’ensemble'), findsOneWidget);
      // Plus de DOUBLE LECTURE : la synthèse relie les cartes par position
      // et NE recopie PAS `combined_interpretation` (assemblage des interps).
      expect(find.textContaining('pose le décor'), findsOneWidget);
      expect(find.text(_serverCombined), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // J6-F2 §13 — TIRAGE « EN PARLER » : l'utilisateur CHOISIT le conseiller.
  // Plus de `selectedAdvisor` automatique, plus de popup de confirmation :
  //   A. fil existant pour ce conseiller -> on rouvre CE fil (tirage en attente)
  //   B. aucun fil -> `openAdvisor()` puis ChatScreen sur le fil renvoyé
  // Le `tirage_id` reste envoyé uniquement avec le 1er message (ChatScreen).
  // -------------------------------------------------------------------------
  _MultiEnv multiEnv({List<Map<String, dynamic>> threads = const []}) {
    final posts = <String>[];
    final openBodies = <Map<String, dynamic>>[];
    final msgBodies = <Map<String, dynamic>>[];
    final current = List<Map<String, dynamic>>.from(threads);
    final client = ApiClient(
      httpClient: MockClient((req) async {
        posts.add('${req.method} ${req.url.path}');
        final p = req.url.path;
        if (p == '/api/tirages' && req.method == 'POST') {
          final keys = (jsonDecode(req.body)['card_keys'] as List)
              .cast<String>();
          return _json(_tirageBody(keys), 201);
        }
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
        if (p == '/api/consultation/message' && req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          msgBodies.add(body);
          return _json({
            'consultation_id': body['consultation_id'] ?? 'c-open-selena',
            'messages': [
              {'role': 'user', 'content': body['message']},
              {'role': 'assistant', 'content': 'Je vois tes trois cartes.'},
            ],
            'quota': {'is_premium': true, 'monthly_remaining': 3},
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
    addTearDown(controller.dispose);
    return (
      auth: auth,
      controller: controller,
      posts: posts,
      openBodies: openBodies,
      msgBodies: msgBodies,
    );
  }

  Future<void> pumpToTalk(WidgetTester tester, _MultiEnv e) async {
    final state = AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u-1',
        selectedAdvisor: 'Maïa', // ne détermine PLUS le fil
        firstName: 'Nina',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 't',
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
              home: TirageScreen(selectorAudioOverride: _FakeAudio()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectThree(tester);
    await _reveal(tester);
    await tester.ensureVisible(find.text('En parler à mon conseiller'));
    await tester.pumpAndSettle();
  }

  testWidgets('H-A/§24. « En parler » demande le conseiller (sélecteur)', (
    tester,
  ) async {
    final e = multiEnv();
    await pumpToTalk(tester, e);
    expect(find.text('En parler à mon conseiller'), findsOneWidget);

    await tester.tap(find.text('En parler à mon conseiller'));
    await tester.pumpAndSettle();
    expect(find.byType(AdvisorSelectorScreen), findsOneWidget);
    expect(find.text('Avec qui veux-tu en parler ?'), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('H-B/§26/§19. nouveau conseiller -> openAdvisor puis '
      'ChatScreen(bon id + tirage préservé), aucun POST message', (
    tester,
  ) async {
    final e = multiEnv(); // aucun fil
    await pumpToTalk(tester, e);

    await tester.tap(find.text('En parler à mon conseiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parler avec Séléna'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(e.openBodies.single, {'advisor_id': 'selena'});
    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-open-selena');
    expect(chat.advisor.name, 'Séléna');
    expect(chat.tirageId, 'tir-abc-123');
    expect(
      (tester.state(find.byType(ChatScreen)) as dynamic).debugPendingTirageId,
      'tir-abc-123',
    );
    expect(
      e.posts.where((p) => p.contains('POST /api/consultation/message')),
      isEmpty,
    );
  });

  testWidgets('H-B bis/§2. PREUVE bout-en-bout : « En parler à mon conseiller » '
      '-> le tirage_id part RÉELLEMENT avec le 1er message (le conseiller '
      'reçoit le contexte du tirage sans qu\'on le lui redemande)', (
    tester,
  ) async {
    final e = multiEnv();
    await pumpToTalk(tester, e);

    await tester.tap(find.text('En parler à mon conseiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parler avec Séléna'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'et cette carte du milieu ?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    if (find.text('Commencer').evaluate().isNotEmpty) {
      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();
    }

    expect(e.msgBodies, isNotEmpty);
    expect(e.msgBodies.first['tirage_id'], 'tir-abc-123');
    expect(e.msgBodies.first['message'], 'et cette carte du milieu ?');

    await tester.enterText(find.byType(TextField), 'ok merci');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(e.msgBodies.length, 2);
    expect(e.msgBodies[1].containsKey('tirage_id'), isFalse);
  });

  testWidgets('H-C/§25. conseiller avec fil existant -> rouvre CE fil, aucun '
      'POST /open', (tester) async {
    final e = multiEnv(
      threads: [
        {
          'id': 'c-ezra-existing',
          'advisor_id': 'ezra',
          'started_at': '2026-09-01T10:00:00Z',
          'window_active': false,
          'preview': 'salut',
        },
      ],
    );
    await pumpToTalk(tester, e);

    await tester.tap(find.text('En parler à mon conseiller'));
    await tester.pumpAndSettle();
    // Ezra = kAdvisors[7] : défiler le feed vertical jusqu'à sa page.
    for (var i = 0; i < 7; i++) {
      await tester.fling(find.byType(PageView), const Offset(0, -500), 1400);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Reprendre avec Ezra'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.consultationId, 'c-ezra-existing');
    expect(chat.advisor.name, 'Ezra');
    expect(chat.tirageId, 'tir-abc-123');
    expect(e.posts.where((p) => p == 'POST /api/consultation/open'), isEmpty);
  });

  testWidgets('H-D. annulation du sélecteur -> reste sur le tirage, aucun '
      'ChatScreen, aucun POST', (tester) async {
    final e = multiEnv();
    await pumpToTalk(tester, e);

    await tester.tap(find.text('En parler à mon conseiller'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(TirageScreen), findsOneWidget);
    expect(find.text('Ce que dit l’ensemble'), findsOneWidget);
    expect(
      e.posts.where(
        (p) =>
            p.contains('consultation/open') ||
            p.contains('consultation/message'),
      ),
      isEmpty,
    );
  });

  // -------------------------------------------------------------------------
  // I/J. réseau KO -> reste 3/3, pas de reveal, « Réessayer » ; retry -> reveal
  // -------------------------------------------------------------------------
  testWidgets(
    'I/J. échec réseau -> Réessayer (3/3 conservé) ; retry -> reveal',
    (tester) async {
      var attempt = 0;
      final e = _env((req, keys) async {
        attempt++;
        if (attempt == 1) throw http.ClientException('boom');
        return _json(_tirageBody(keys), 201);
      });
      await _pump(tester, e.auth);
      await _selectThree(tester);
      await _reveal(tester);

      // pas de révélation, sélection intacte, bouton Réessayer
      expect(find.text('Ce que dit l’ensemble'), findsNothing);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(
        find.text("Impossible d'enregistrer ton tirage pour le moment."),
        findsOneWidget,
      );
      expect((_st(tester).debugSelectionKeys as List).length, 3);

      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Ce que dit l’ensemble'), findsOneWidget);
      // Plus de DOUBLE LECTURE : la synthèse relie les cartes par position
      // et NE recopie PAS `combined_interpretation` (assemblage des interps).
      expect(find.textContaining('pose le décor'), findsOneWidget);
      expect(find.text(_serverCombined), findsNothing);
    },
  );

  testWidgets('I bis. 5xx -> Réessayer (récupérable)', (tester) async {
    final e = _env((_, keys) async => _json({}, 503));
    await _pump(tester, e.auth);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Ce que dit l’ensemble'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // K. Recommencer -> phase initiale
  // -------------------------------------------------------------------------
  testWidgets('K. Recommencer : retour à la phase de choix', (tester) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await _pump(tester, e.auth);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.text('Ce que dit l’ensemble'), findsOneWidget);

    await tester.ensureVisible(find.text('Recommencer le tirage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recommencer le tirage'));
    await tester.pumpAndSettle();

    expect(find.text('Choisis trois cartes.'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
    expect(_cardFaceImages, findsNothing);
    expect((_st(tester).debugSelectionKeys as List), isEmpty);
  });

  // -------------------------------------------------------------------------
  // L. pas de token -> état « reconnecte-toi », aucune révélation
  // -------------------------------------------------------------------------
  testWidgets('L. token absent -> message auth, aucune révélation', (
    tester,
  ) async {
    final e = _env(
      (_, keys) async => _json(_tirageBody(keys), 201),
      token: null,
    );
    await _pump(tester, e.auth);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.text('Ce que dit l’ensemble'), findsNothing);
    expect(
      find.text('Reconnecte-toi pour enregistrer ton tirage.'),
      findsOneWidget,
    );
    expect(e.posts, isEmpty);
  });

  // -------------------------------------------------------------------------
  // M. J6-F2 §13 — le CTA « En parler » ne dépend PLUS de selectedAdvisor :
  // il est toujours présent (le conseiller est choisi ensuite).
  // -------------------------------------------------------------------------
  testWidgets('M. CTA « En parler à mon conseiller » présent même si '
      'selectedAdvisor null', (tester) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await _pump(tester, e.auth, selectedAdvisor: null);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.text('En parler à mon conseiller'), findsOneWidget);
    expect(find.text('Recommencer le tirage'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // N. flèche retour de l'écran résultat (après un tirage).
  // -------------------------------------------------------------------------
  group('Retour — écran résultat', () {
    testWidgets(
      'flèche retour absente en phase de choix, présente après la révélation',
      (tester) async {
        final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
        await _pump(tester, e.auth);

        expect(find.byTooltip('Retour'), findsNothing);

        await _selectThree(tester);
        await _reveal(tester);

        expect(find.byTooltip('Retour'), findsOneWidget);
      },
    );

    testWidgets('la flèche retour ferme l\'écran résultat (Navigator.pop)', (
      tester,
    ) async {
      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
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
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TirageScreen()),
                      ),
                      child: const Text('ouvrir-tirage'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ouvrir-tirage'));
      await tester.pumpAndSettle();
      expect(find.byType(TirageScreen), findsOneWidget);

      await _selectThree(tester);
      await _reveal(tester);
      expect(find.text('Ce que dit l’ensemble'), findsOneWidget);

      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      // L'écran résultat est fermé : retour à l'écran précédent.
      expect(find.byType(TirageScreen), findsNothing);
      expect(find.text('ouvrir-tirage'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // UX-LOT §6-7 — cartes remontées à la révélation + indice de scroll.
  // -------------------------------------------------------------------------
  group('UX-LOT — Tirage révélé', () {
    /// Centre vertical du slot de la 1re carte retournée (en test, l'asset face
    /// n'a pas de dimensions -> le widget clé se réduit au centre du slot).
    double cardCenter(WidgetTester t) =>
        t.getTopLeft(find.byKey(const ValueKey('tarot-reveal-0'))).dy;

    testWidgets('A/C — 3 cartes révélées EN PLACE (pas de duplication) et '
        'remontées : centre du groupe au-dessus du milieu de l\'écran', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(384, 850); // Galaxy A07 ~ 384 dp
      addTearDown(tester.view.reset);

      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      await _pump(tester, e.auth);
      await _selectThree(tester);
      await _reveal(tester);
      await tester.pumpAndSettle();

      // exactement 3 faces révélées, une par slot (aucune 2e rangée)
      expect(find.byKey(const ValueKey('tarot-reveal-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('tarot-reveal-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tarot-reveal-2')), findsOneWidget);
      expect(_cardFaceImages, findsNWidgets(3));

      // Avant ce lot : centre à ~0.545 de la hauteur (≈ 463 dp). Objectif :
      // nettement remonté, au-dessus du milieu.
      expect(
        cardCenter(tester),
        lessThan(850 * 0.46),
        reason: 'centre carte à ${cardCenter(tester).toStringAsFixed(0)} dp',
      );
    });

    testWidgets('D/E — indice « Voir la suite » quand la lecture déborde, '
        'puis disparaît une fois scrollé en bas', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(384, 720); // volontairement court
      addTearDown(tester.view.reset);

      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      await _pump(tester, e.auth);
      await _selectThree(tester);
      await _reveal(tester);
      await tester.pumpAndSettle();

      expect(find.text('Voir la suite'), findsOneWidget);

      // scroll jusqu'en bas du panneau de lecture
      await tester.scrollUntilVisible(
        find.text('Recommencer le tirage'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Voir la suite'), findsNothing);
    });

    for (final w in const [360.0, 384.0, 430.0]) {
      testWidgets('F/G — aucun overflow + CTA conseiller atteignable à '
          '${w.toInt()} dp', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(w, 780);
        addTearDown(tester.view.reset);

        final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
        await _pump(tester, e.auth);
        await _selectThree(tester);
        await _reveal(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '${w.toInt()} dp');

        // le CTA conseiller reste accessible via scroll (jamais masqué)
        await tester.ensureVisible(find.text('En parler à mon conseiller'));
        await tester.pumpAndSettle();
        expect(find.text('En parler à mon conseiller'), findsOneWidget);
      });
    }
  });
}

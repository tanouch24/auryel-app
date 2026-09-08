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
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/tarot_deck.dart';
import 'package:auryel/data/token_store.dart';
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
      expect(find.text('Lecture de ton tirage'), findsOneWidget);
      expect(find.text(_serverCombined), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // T3-C.1 — confirmation avant l'entrée en consultation
  // -------------------------------------------------------------------------
  Future<void> revealed(
    WidgetTester tester,
    _Env e, {
    String? advisor = 'Maïa',
  }) async {
    await _pump(tester, e.auth, selectedAdvisor: advisor);
    await _selectThree(tester);
    await _reveal(tester);
    if (advisor != null) {
      await tester.ensureVisible(find.text('En parler avec $advisor'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('H-A. conseiller Séléna -> « En parler avec Séléna »', (
    tester,
  ) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await revealed(tester, e, advisor: 'Séléna');
    expect(find.text('En parler avec Séléna'), findsOneWidget);
    expect(find.text('En parler avec Ezra'), findsNothing);
  });

  testWidgets(
    'H-B. conseiller Ezra -> « En parler avec Ezra » (pas hardcodé)',
    (tester) async {
      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      await revealed(tester, e, advisor: 'Ezra');
      expect(find.text('En parler avec Ezra'), findsOneWidget);
      expect(find.text('En parler avec Séléna'), findsNothing);
    },
  );

  testWidgets('H-C. clic CTA -> popup visible, ChatScreen PAS ouvert', (
    tester,
  ) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await revealed(tester, e);
    await tester.tap(find.text('En parler avec Maïa'));
    await tester.pumpAndSettle();

    expect(find.text('Démarrer une consultation avec Maïa ?'), findsOneWidget);
    expect(find.textContaining('sera transmis à Maïa'), findsOneWidget);
    expect(find.textContaining('premier message'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets(
    'H-D. Annuler -> popup fermée, reste sur TirageScreen, aucun POST',
    (tester) async {
      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      await revealed(tester, e);
      await tester.tap(find.text('En parler avec Maïa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.text('Démarrer une consultation avec Maïa ?'), findsNothing);
      expect(find.byType(TirageScreen), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(
        find.text('Lecture de ton tirage'),
        findsOneWidget,
      ); // reste sur le résultat
      expect(
        e.posts.where((p) => p.contains('POST /api/consultation/message')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'H-E/F/G. Commencer -> ChatScreen(advisor, tirageId), aucun POST',
    (tester) async {
      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      await revealed(tester, e);
      await tester.tap(find.text('En parler avec Maïa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      // aucun POST /api/consultation/message au simple clic
      expect(
        e.posts.where((p) => p.contains('POST /api/consultation/message')),
        isEmpty,
      );
      final chat = tester.state(find.byType(ChatScreen));
      expect((chat as dynamic).debugPendingTirageId, 'tir-abc-123');
      final chatWidget = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chatWidget.advisor.name, 'Maïa');
    },
  );

  testWidgets(
    'H-H. session active avec CE conseiller -> wording « Continuer »',
    (tester) async {
      final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
      // consultation déjà active avec « maia » (= guideKey de Maïa)
      final ctrl = ConsultationController(
        api: ConsultationApi(
          ApiClient(
            httpClient: MockClient((_) async => _json({}, 200)),
            baseUrl: 'http://test.local',
          ),
        ),
        auth: e.auth,
      );
      addTearDown(ctrl.dispose);
      final future = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String();
      ctrl.updateFromMessageResponse(
        ConsultationMessageResponse.fromJson({
          'reply': 'x',
          'consultation': {
            'id': 'c-live',
            'advisor_id': 'maia',
            'started_at': DateTime.now().toUtc().toIso8601String(),
            'expires_at': future,
            'seconds_remaining': 7000,
            'credit_source': 'monthly',
          },
          'quota': {
            'is_premium': true,
            'monthly_limit': 4,
            'monthly_used': 1,
            'monthly_remaining': 3,
            'earned_available': 0,
          },
        }),
      );

      final state = AuryelState(
        repository: LocalOnboardingRepository(),
        initial: OnboardingRecord(
          userId: 'u-1',
          selectedAdvisor: 'Maïa',
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
              controller: ctrl,
              child: const MaterialApp(home: TirageScreen()),
            ),
          ),
        ),
      );
      // Pas de pumpAndSettle : un ticker 1 s tourne. Pumps explicites.
      await tester.pump(const Duration(seconds: 1));
      for (final i in [0, 1, 2]) {
        await tester.tap(_back(i));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Révéler mon tirage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 700));

      await tester.ensureVisible(find.text('En parler avec Maïa'));
      await tester.tap(find.text('En parler avec Maïa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Continuer avec Maïa ?'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
      expect(
        find.textContaining('ajouté à ta conversation en cours'),
        findsOneWidget,
      );
      expect(find.byType(ChatScreen), findsNothing);
      // simple clic « Continuer » : aucun POST message, aucun nouveau crédit
      expect(
        e.posts.where((p) => p.contains('POST /api/consultation/message')),
        isEmpty,
      );

      await tester.tap(find.text('Continuer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatScreen), findsOneWidget);
      final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
      expect(chat.advisor.name, 'Maïa');
      expect(chat.tirageId, 'tir-abc-123');
      expect(
        e.posts.where((p) => p.contains('POST /api/consultation/message')),
        isEmpty,
      );

      ctrl.dispose(); // stoppe le ticker 1 s avant la vérif des timers
    },
  );

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
      expect(find.text('Lecture de ton tirage'), findsNothing);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(
        find.text("Impossible d'enregistrer ton tirage pour le moment."),
        findsOneWidget,
      );
      expect((_st(tester).debugSelectionKeys as List).length, 3);

      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Lecture de ton tirage'), findsOneWidget);
      expect(find.text(_serverCombined), findsOneWidget);
    },
  );

  testWidgets('I bis. 5xx -> Réessayer (récupérable)', (tester) async {
    final e = _env((_, keys) async => _json({}, 503));
    await _pump(tester, e.auth);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text('Lecture de ton tirage'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // K. Recommencer -> phase initiale
  // -------------------------------------------------------------------------
  testWidgets('K. Recommencer : retour à la phase de choix', (tester) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await _pump(tester, e.auth);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.text('Lecture de ton tirage'), findsOneWidget);

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
    expect(find.text('Lecture de ton tirage'), findsNothing);
    expect(
      find.text('Reconnecte-toi pour enregistrer ton tirage.'),
      findsOneWidget,
    );
    expect(e.posts, isEmpty);
  });

  // -------------------------------------------------------------------------
  // M. CTA absent si aucun conseiller résolu
  // -------------------------------------------------------------------------
  testWidgets('M. CTA conseiller absent si selectedAdvisor null', (
    tester,
  ) async {
    final e = _env((_, keys) async => _json(_tirageBody(keys), 201));
    await _pump(tester, e.auth, selectedAdvisor: null);
    await _selectThree(tester);
    await _reveal(tester);
    expect(find.textContaining('En parler avec'), findsNothing);
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
      expect(find.text('Lecture de ton tirage'), findsOneWidget);

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
        await tester.ensureVisible(find.text('En parler avec Maïa'));
        await tester.pumpAndSettle();
        expect(find.text('En parler avec Maïa'), findsOneWidget);
      });
    }
  });
}

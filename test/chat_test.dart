import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/billing_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/iap_gateway.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/screens/premium_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/state/purchase_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';

/// Gateway IAP inerte pour les tests d'UI qui n'exercent pas l'achat.
class _NullGateway implements IapGateway {
  final _ctrl = StreamController<List<PurchaseDetails>>.broadcast();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: ids.toList(),
      );
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _ctrl.stream;
  @override
  Future<bool> buyNonConsumable(ProductDetails p) async => false;
  @override
  Future<void> completePurchase(PurchaseDetails p) async {}
  @override
  Future<void> restorePurchases() async {}
}

PurchaseController _stubPurchase(AuthController auth) {
  final client = ApiClient(
    httpClient: MockClient((_) async => http.Response('{}', 200)),
    baseUrl: 'http://test.local',
  );
  final consultation = ConsultationController(
    api: ConsultationApi(client),
    auth: auth,
  );
  final c = PurchaseController(
    billing: BillingApi(client),
    gateway: _NullGateway(),
    auth: auth,
    consultation: consultation,
  );
  addTearDown(() {
    c.dispose();
    consultation.dispose();
  });
  return c;
}

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _time({
  int firstFree = 0,
  int premium = 6500,
  int purchased = 0,
  bool windowActive = true,
}) => {
  'first_free_remaining_seconds': firstFree,
  'premium_remaining_seconds': premium,
  'purchased_remaining_seconds': purchased,
  'total_remaining_seconds': firstFree + premium + purchased,
  'window_active': windowActive,
  'window_expires_at': windowActive ? '2999-01-01T00:05:00Z' : null,
};

Map<String, dynamic> _okBody({
  String reply = 'Je te vois clairement.',
  String advisorId = 'maia',
  bool openedNow = true,
  int secondsRemaining = 6500,
}) => {
  'reply': reply,
  'consultation': {
    'id': 'c-1',
    'advisor_id': advisorId,
    'started_at': '2026-08-27T10:00:00Z',
    'expires_at': '2026-08-27T12:00:00Z',
    'seconds_remaining': secondsRemaining,
    'credit_source': 'time',
    'opened_now': openedNow,
  },
  'time': _time(premium: secondsRemaining),
  'quota': {
    'is_premium': true,
    'monthly_limit': 8,
    'monthly_used': 1,
    'monthly_remaining': 7,
    'earned_available': 0,
    'first_free_available': false,
    'period_start': '2026-08-01T00:00:00Z',
    'period_end': '2026-09-01T00:00:00Z',
  },
};

const _noCreditBody = {
  'error': 'time_exhausted',
  'consultation': null,
  'time': {
    'first_free_remaining_seconds': 0,
    'premium_remaining_seconds': 0,
    'purchased_remaining_seconds': 0,
    'total_remaining_seconds': 0,
    'window_active': false,
    'window_expires_at': null,
  },
  'quota': {
    'is_premium': true,
    'monthly_limit': 8,
    'monthly_used': 8,
    'monthly_remaining': 0,
    'earned_available': 0,
    'first_free_available': false,
    'period_start': '2026-08-01T00:00:00Z',
    'period_end': '2026-09-01T00:00:00Z',
  },
};

typedef _Env = ({
  AuthController auth,
  InMemoryTokenStore tokens,
  List<int> posts,
});

_Env _env(
  Future<http.Response> Function(http.Request req) handler, {
  String? token = 'tok',
}) {
  final posts = <int>[];
  final tokens = InMemoryTokenStore(token);
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/consultation/message') posts.add(1);
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  return (auth: auth, tokens: tokens, posts: posts);
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required AuthController auth,
  String advisorName = 'Séléna',
  PurchaseController? purchase,
}) {
  final state = AuryelState(
    repository: LocalOnboardingRepository(),
    initial: OnboardingRecord(
      userId: 'u',
      selectedAdvisor: advisorName,
      firstName: 'N',
      birthDate: DateTime(1994, 1, 1),
      portraitData: 'x',
      portraitFeedback: 'y',
      onboardingCompleted: true,
    ),
  );
  Widget tree = MaterialApp(
    home: ChatScreen(advisor: advisorByNameOrNull(advisorName)!),
  );
  if (purchase != null) {
    tree = PurchaseScope(controller: purchase, child: tree);
  }
  return tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: AuryelStateScope(state: state, child: tree),
    ),
  );
}

Future<void> _type(WidgetTester tester, String msg) async {
  await tester.enterText(find.byType(TextField), msg);
  await tester.pump();
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();
}

const _confirmText =
    'Ce premier message ouvre ta consultation. Le temps se décompte '
    'ensuite de ton temps disponible.';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // DTO parsing
  // =========================================================================
  test('ConsultationMessageResponse.fromJson : parsing complet', () {
    final r = ConsultationMessageResponse.fromJson(_okBody());
    expect(r.reply, 'Je te vois clairement.');
    expect(r.consultation, isNotNull);
    expect(r.consultation!.id, 'c-1');
    expect(r.consultation!.advisorId, 'maia');
    expect(r.consultation!.secondsRemaining, 6500);
    expect(r.consultation!.creditSource, 'time');
    expect(r.consultation!.openedNow, isTrue);
    expect(r.consultation!.startedAt, isA<DateTime>());
    expect(r.consultation!.expiresAt, isA<DateTime>());
    // TIMER-D.1 — bloc `time` parsé, source de vérité.
    expect(r.time, isNotNull);
    expect(r.time!.totalRemainingSeconds, 6500);
    expect(r.time!.premiumRemainingSeconds, 6500);
    expect(r.time!.windowActive, isTrue);
    expect(r.quota.isPremium, isTrue);
    expect(r.quota.monthlyLimit, 8);
    expect(r.quota.monthlyUsed, 1);
    expect(r.quota.monthlyRemaining, 7);
    expect(r.quota.earnedAvailable, 0);
    expect(r.quota.periodStart, isA<DateTime>());
  });

  test('parsing robuste : seconds_remaining string, opened_now absent, dates nulles', () {
    final r = ConsultationMessageResponse.fromJson({
      'reply': 'x',
      'consultation': {
        'id': 'c',
        'advisor_id': 'selena',
        'seconds_remaining': '5400',
        'credit_source': 'referral',
      },
      'quota': {'is_premium': false, 'monthly_limit': 0},
    });
    expect(r.consultation!.secondsRemaining, 5400);
    expect(r.consultation!.openedNow, isFalse);
    expect(r.consultation!.startedAt, isNull);
    expect(r.consultation!.expiresAt, isNull);
    expect(r.quota.isPremium, isFalse);
    expect(r.quota.monthlyUsed, 0);
  });

  test('formatRemaining : portefeuille de temps / épuisé', () {
    expect(_ChatScreenStateFormat.f(6500), '1 h 48 min disponibles');
    expect(_ChatScreenStateFormat.f(600), '10 min disponibles');
    expect(_ChatScreenStateFormat.f(0), 'Temps de consultation épuisé');
  });

  // =========================================================================
  // ConsultationApi
  // =========================================================================
  test(
    'sendMessage : POST /api/consultation/message body {message} + Bearer',
    () async {
      http.Request? seen;
      final client = ApiClient(
        httpClient: MockClient((req) async {
          seen = req;
          return _json(_okBody());
        }),
        baseUrl: 'http://test.local',
      );
      final res = await ConsultationApi(client)
          .sendMessage(bearer: 'tk', message: '  salut  ');

      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/consultation/message');
      expect(seen!.headers['Authorization'], 'Bearer tk');
      expect(jsonDecode(seen!.body), {'message': '  salut  '});
      expect(res.reply, 'Je te vois clairement.');
      expect(res.consultation!.advisorId, 'maia');
    },
  );

  test('sendMessage : 402 -> ApiNoCreditException portant quota', () async {
    final client = ApiClient(
      httpClient: MockClient((_) async => _json(_noCreditBody, 402)),
      baseUrl: 'http://test.local',
    );
    await expectLater(
      ConsultationApi(client).sendMessage(bearer: 'tk', message: 'x'),
      throwsA(isA<ApiNoCreditException>()),
    );
  });

  // =========================================================================
  // ChatScreen — widget
  // =========================================================================
  testWidgets('écran neuf : aucun faux historique, invite de départ', (
    t,
  ) async {
    final e = _env((_) async => _json(_okBody()));
    await _pumpChat(t, auth: e.auth);
    await t.pumpAndSettle();

    expect(
      find.text('Écris ton premier message pour commencer.'),
      findsOneWidget,
    );
    expect(find.byType(ListView), findsNothing); // pas de liste => pas de bulle
  });

  testWidgets('1er message : confirmation affichée', (t) async {
    final e = _env((_) async => _json(_okBody()));
    await _pumpChat(t, auth: e.auth);
    await _type(t, 'bonjour');
    await _tapSend(t);

    expect(find.text(_confirmText), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
  });

  testWidgets('confirmation annulée -> aucun POST, texte conservé', (t) async {
    final e = _env((_) async => _json(_okBody()));
    await _pumpChat(t, auth: e.auth);
    await _type(t, 'bonjour');
    await _tapSend(t);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();

    expect(e.posts, isEmpty);
    expect(find.text('bonjour'), findsOneWidget); // toujours dans le champ
    expect(find.text(_confirmText), findsNothing);
  });

  testWidgets('confirmation validée -> POST + bulles user & assistant', (
    t,
  ) async {
    final e = _env((_) async => _json(_okBody(reply: 'Réponse conseiller')));
    await _pumpChat(t, auth: e.auth);
    await _type(t, 'bonjour');
    await _tapSend(t);
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();

    expect(e.posts.length, 1);
    expect(find.text('bonjour'), findsOneWidget);
    expect(find.text('Réponse conseiller'), findsOneWidget);
  });

  testWidgets('advisor_id backend "maia" -> header passe à Maïa', (t) async {
    final e = _env((_) async => _json(_okBody(advisorId: 'maia')));
    await _pumpChat(t, auth: e.auth, advisorName: 'Séléna');

    expect(find.text('Séléna'), findsOneWidget); // header initial

    await _type(t, 'salut');
    await _tapSend(t);
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();

    expect(find.text('Maïa'), findsOneWidget);
    expect(find.text('Séléna'), findsNothing);
  });

  testWidgets('2e message même session : pas de nouvelle confirmation', (
    t,
  ) async {
    final e = _env((_) async => _json(_okBody()));
    await _pumpChat(t, auth: e.auth);
    await _type(t, 'un');
    await _tapSend(t);
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();

    await _type(t, 'deux');
    await _tapSend(t);

    expect(find.text(_confirmText), findsNothing);
    expect(e.posts.length, 2);
    expect(find.text('deux'), findsOneWidget);
  });

  testWidgets('402 time_exhausted (Premium) -> mur sobre, pas d\'upsell prix', (
    t,
  ) async {
    final e = _env((_) async => _json(_noCreditBody, 402)); // is_premium: true
    await _pumpChat(t, auth: e.auth);
    await _type(t, 'coucou');
    await _tapSend(t);
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();

    // TIMER-D.2 — Premium : titre « disponible épuisé » + sous-texte
    // « renouvellement », AUCUN prix, AUCUN « Découvrir Premium ».
    expect(
      find.text('Ton temps de consultation disponible est épuisé.'),
      findsOneWidget,
    );
    expect(find.textContaining('à la prochaine période'), findsOneWidget);
    expect(find.text('Premium — 7,99 €/mois'), findsNothing);
    expect(find.text('Découvrir Premium'), findsNothing);
    expect(find.textContaining('consultations de 2 h'), findsNothing);
    expect(find.textContaining('4 consultations'), findsNothing);
    expect(find.text('coucou'), findsNothing); // pas de bulle user
    expect(find.byType(TextField), findsNothing); // input remplacé
  });

  testWidgets(
    '402 time_exhausted (non Premium) -> upsell 8 h/mois + Découvrir Premium',
    (t) async {
      const body = {
        'error': 'time_exhausted',
        'consultation': null,
        'time': {
          'first_free_remaining_seconds': 0,
          'premium_remaining_seconds': 0,
          'purchased_remaining_seconds': 0,
          'total_remaining_seconds': 0,
          'window_active': false,
          'window_expires_at': null,
        },
        'quota': {'is_premium': false, 'monthly_limit': 8, 'monthly_used': 8},
      };
      final e = _env((_) async => _json(body, 402));
      await _pumpChat(t, auth: e.auth);
      await _type(t, 'coucou');
      await _tapSend(t);
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      expect(
        find.text('Ton temps de consultation est épuisé.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('8 h de consultation par mois'),
        findsOneWidget,
      );
      expect(find.text('Premium — 7,99 €/mois'), findsOneWidget);
      expect(find.text('Découvrir Premium'), findsOneWidget);
      expect(find.textContaining('4 consultations'), findsNothing);
      expect(find.textContaining('consultations de 2 h'), findsNothing);
    },
  );

  testWidgets(
    'M — 402 ANCIEN "no_credit" (sans bloc time) : mur affiché, pas de crash',
    (t) async {
      const legacyBody = {
        'error': 'no_credit',
        'consultation': null,
        'quota': {
          'is_premium': false,
          'monthly_limit': 4,
          'monthly_used': 4,
          'monthly_remaining': 0,
          'earned_available': 0,
        },
      };
      final e = _env((_) async => _json(legacyBody, 402));
      await _pumpChat(t, auth: e.auth);
      await _type(t, 'coucou');
      await _tapSend(t);
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      // fallback : variante non-Premium du texte V1.
      expect(
        find.text('Ton temps de consultation est épuisé.'),
        findsOneWidget,
      );
      expect(find.text('coucou'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'I — "Découvrir Premium" ouvre PremiumScreen (plus de snackbar)',
    (t) async {
      // non-Premium : le CTA « Découvrir Premium » est présent.
      const body = {
        'error': 'time_exhausted',
        'consultation': null,
        'quota': {'is_premium': false, 'monthly_limit': 8, 'monthly_used': 8},
      };
      final e = _env((_) async => _json(body, 402));
      await _pumpChat(t, auth: e.auth, purchase: _stubPurchase(e.auth));
      await _type(t, 'coucou');
      await _tapSend(t);
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      await t.tap(find.text('Découvrir Premium'));
      await t.pumpAndSettle();

      expect(find.byType(PremiumScreen), findsOneWidget);
      expect(find.text('Auryel Premium'), findsOneWidget);
      expect(find.text('Premium arrive bientôt.'), findsNothing);
    },
  );

  testWidgets('401 -> session purgée + retour EmailAuthScreen', (t) async {
    final e = _env((_) async => _json({'error': 'unauthorized'}, 401));
    await _pumpChat(t, auth: e.auth);
    await _type(t, 'hello');
    await _tapSend(t);
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();

    expect(find.text('Bon retour'), findsOneWidget);
    expect(await e.tokens.read(), isNull);
    expect(e.auth.status, AuthStatus.sessionExpired);
  });

  testWidgets(
    'réseau KO -> Réessayer dispo, texte conservé, pas de duplication',
    (t) async {
      var call = 0;
      final e = _env((_) async {
        call++;
        if (call == 1) throw http.ClientException('offline');
        return _json(_okBody(reply: 'enfin'));
      });
      await _pumpChat(t, auth: e.auth);
      await _type(t, 'mon message');
      await _tapSend(t);
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      // Échec : bulle "pending" visible une seule fois, bouton Réessayer présent.
      expect(find.text('mon message'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(e.posts.length, 1);

      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();

      expect(e.posts.length, 2);
      expect(find.text('mon message'), findsOneWidget); // pas dédoublé
      expect(find.text('enfin'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    },
  );

  testWidgets('CTA Accueil -> ouvre ChatScreen', (t) async {
    final e = _env((_) async => _json(_okBody()));
    final state = AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u',
        selectedAdvisor: 'Maïa',
        firstName: 'N',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    );
    await t.pumpWidget(
      AuthScope(
        controller: e.auth,
        child: AuryelStateScope(
          state: state,
          child: const MaterialApp(home: HomeScreen()),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Consulter'));
    await t.tap(find.text('Consulter'));
    await t.pumpAndSettle();

    expect(
      find.text('Écris ton message…'),
      findsOneWidget,
    ); // hint du ChatScreen
  });
}

/// Petit proxy pour tester la fonction statique de formatage sans exposer
/// l'état privé du widget.
class _ChatScreenStateFormat {
  static String f(int s) => ChatScreen.debugFormatRemaining(s);
}

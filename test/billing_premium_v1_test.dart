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
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/iap_gateway.dart';
import 'package:auryel/data/purchase.dart';
import 'package:auryel/data/subscription_manager.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/premium_screen.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/state/purchase_controller.dart';

// ===========================================================================
// LOT PREMIUM / BILLING E2E V1 — nouveautés UI (déjà-Premium, gestion abo,
// disclosure) + garde-fous produit. Le pipeline d'achat lui-même est couvert
// par purchase_controller_test.dart / billing_api_test.dart / premium_screen_test.dart.
// ===========================================================================

class _FakeGateway implements IapGateway {
  bool available = true;
  List<ProductDetails> products = <ProductDetails>[];
  List<String> notFoundIDs = <String>[];
  final List<Set<String>> queriedIds = <Set<String>>[];
  int buyCalls = 0;
  int restoreCalls = 0;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  final _ctrl = StreamController<List<PurchaseDetails>>.broadcast();

  void emit(List<PurchaseDetails> l) => _ctrl.add(l);
  Future<void> close() => _ctrl.close();

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queriedIds.add(ids);
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: notFoundIDs,
    );
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _ctrl.stream;
  @override
  Future<bool> buyNonConsumable(ProductDetails p) async {
    buyCalls++;
    return true;
  }

  @override
  Future<bool> buyConsumable(ProductDetails p) async {
    buyCalls++;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails p) async => completed.add(p);
  @override
  Future<void> restorePurchases() async => restoreCalls++;
}

class _FakeSubscriptionManager implements SubscriptionManager {
  _FakeSubscriptionManager({this.result = true});
  bool result;
  int openCalls = 0;
  String? lastProductId;

  @override
  Future<bool> openManagement({String? productId}) async {
    openCalls++;
    lastProductId = productId;
    return result;
  }
}

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _quota({required bool premium}) => {
  'is_premium': premium,
  'monthly_limit': premium ? 8 : 0,
  'monthly_used': 0,
  'monthly_remaining': premium ? 8 : 0,
  'earned_available': 0,
  'first_free_available': false,
  'period_start': '2026-09-01T00:00:00Z',
  'period_end': '2026-10-01T00:00:00Z',
};

Map<String, dynamic> _stateBody({required bool premium, int premiumSec = 0}) =>
    {
      'consultation': null,
      'quota': _quota(premium: premium),
      'time': {
        'first_free_remaining_seconds': 0,
        'premium_remaining_seconds': premiumSec,
        'purchased_remaining_seconds': 0,
        'total_remaining_seconds': premiumSec,
        'window_active': false,
        'window_expires_at': null,
      },
    };

Map<String, dynamic> _verifyOk() => {
  'subscription': {
    'store': 'google_play',
    'product_id': kPremiumMonthlyProductId,
    'status': 'active',
    'entitled': true,
    'expires_at': '2026-10-01T00:00:00Z',
  },
  'quota': _quota(premium: true),
};

ProductDetails _product({String price = '4,99 €'}) => ProductDetails(
  id: kPremiumMonthlyProductId,
  title: 'Auryel Premium',
  description: 'desc',
  price: price,
  rawPrice: 4.99,
  currencyCode: 'EUR',
  currencySymbol: '€',
);

PurchaseDetails _pd({String server = 'gpa-tok'}) {
  final pd = PurchaseDetails(
    purchaseID: 'pid',
    productID: kPremiumMonthlyProductId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'l',
      serverVerificationData: server,
      source: 'test',
    ),
    transactionDate: '1700000000000',
    status: PurchaseStatus.purchased,
  );
  pd.pendingCompletePurchase = true;
  return pd;
}

typedef _Rig = ({
  PurchaseController controller,
  ConsultationController consultation,
  _FakeGateway gateway,
  List<String> hits,
});

_Rig _rig({
  required Future<http.Response> Function(http.Request) handler,
  String token = 'tok',
}) {
  final hits = <String>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      hits.add(req.url.path);
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  final consultationApi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore(token),
    ),
    profileApi: ProfileApi(client),
    consultationApi: consultationApi,
    tirageApi: TirageApi(client),
  );
  final consultation = ConsultationController(api: consultationApi, auth: auth);
  final gateway = _FakeGateway();
  final controller = PurchaseController(
    billing: BillingApi(client),
    gateway: gateway,
    auth: auth,
    consultation: consultation,
    platformOverride: TargetPlatform.android,
  );
  addTearDown(() async {
    controller.dispose();
    consultation.dispose();
    await gateway.close();
  });
  return (
    controller: controller,
    consultation: consultation,
    gateway: gateway,
    hits: hits,
  );
}

Future<void> _pumpPremium(
  WidgetTester t,
  _Rig rig, {
  required SubscriptionManager manager,
}) => t.pumpWidget(
  PurchaseScope(
    controller: rig.controller,
    child: ConsultationScope(
      controller: rig.consultation,
      child: MaterialApp(home: PremiumScreen(subscriptionManager: manager)),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // SubscriptionManager (unitaire)
  // -------------------------------------------------------------------------
  group('SubscriptionManager', () {
    test('URL Google Play officielle : package + sku', () {
      final u = playSubscriptionsUri();
      expect(u.host, 'play.google.com');
      expect(u.path, '/store/account/subscriptions');
      expect(u.queryParameters['package'], 'com.auryel.auryel');
      expect(u.queryParameters['sku'], 'auryel_premium_monthly');
    });

    test('URL App Store officielle', () {
      expect(
        appleSubscriptionsUri().toString(),
        'https://apps.apple.com/account/subscriptions',
      );
    });

    test('NoopSubscriptionManager -> false, jamais de faux succès', () async {
      expect(await const NoopSubscriptionManager().openManagement(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // PARTIE Q — 26 : loadProducts demande auryel_premium_monthly +
  // auryel_extra_hour (consommable « +1 h »), et JAMAIS l'ancien
  // auryel_consultation_extra (produit 2,90 € abandonné).
  // -------------------------------------------------------------------------
  test('26 — loadProducts demande premium + extra_hour, jamais '
      'auryel_consultation_extra', () async {
    final rig = _rig(handler: (_) async => _json({}, 404));
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    expect(rig.gateway.queriedIds, isNotEmpty);
    for (final ids in rig.gateway.queriedIds) {
      expect(ids, {'auryel_premium_monthly', 'auryel_extra_hour'});
      expect(ids.contains('auryel_consultation_extra'), isFalse);
    }
  });

  // -------------------------------------------------------------------------
  // PARTIE Q — 30 : refresh consultation UNE seule fois après verify 200
  // -------------------------------------------------------------------------
  test('30 — verify 200 -> exactement UN GET /api/consultation/state, '
      'aucun crédit local', () async {
    final rig = _rig(
      handler: (r) async {
        if (r.url.path == '/api/billing/verify') return _json(_verifyOk());
        if (r.url.path == '/api/consultation/state') {
          return _json(_stateBody(premium: true, premiumSec: 28800));
        }
        return _json({}, 404);
      },
    );
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    rig.gateway.emit([_pd()]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(rig.controller.state, PurchaseState.active);
    expect(
      rig.hits.where((p) => p == '/api/consultation/state').length,
      1,
      reason: 'un seul refresh après validation réussie',
    );
    expect(
      rig.gateway.completed,
      hasLength(1),
    ); // completePurchase après verify
    // Le temps vient du serveur (bucket premium), jamais d'un += local.
    expect(rig.consultation.time?.premiumRemainingSeconds, 28800);
  });

  // -------------------------------------------------------------------------
  // PARTIE J / Q20-Q21 — état déjà-Premium vs non-Premium sur PremiumScreen
  // -------------------------------------------------------------------------
  group('PremiumScreen — état abonnement', () {
    testWidgets(
      '21 — NON Premium -> CTA « S’abonner », pas de « Premium actif »',
      (t) async {
        final rig = _rig(
          handler: (r) async {
            if (r.url.path == '/api/consultation/state') {
              return _json(_stateBody(premium: false));
            }
            return _json({}, 404);
          },
        );
        rig.gateway.products = [_product()];
        await rig.controller.initialize();
        await rig.consultation.refresh();
        await _pumpPremium(t, rig, manager: _FakeSubscriptionManager());
        await t.pump();

        expect(find.text('S’abonner'), findsOneWidget);
        expect(find.text('Premium actif'), findsNothing);
        expect(find.text('Gérer mon abonnement'), findsNothing);
        // disclosure obligatoire présente
        expect(
          find.textContaining('renouvellement automatique'),
          findsOneWidget,
        );
        expect(find.textContaining('Google Play'), findsWidgets);
      },
    );

    testWidgets('20/J — DÉJÀ Premium -> « Premium actif » + temps serveur + '
        '« Gérer mon abonnement », AUCUN « S’abonner »', (t) async {
      final rig = _rig(
        handler: (r) async {
          if (r.url.path == '/api/consultation/state') {
            return _json(_stateBody(premium: true, premiumSec: 28800));
          }
          return _json({}, 404);
        },
      );
      rig.gateway.products = [_product()];
      await rig.controller.initialize();
      await rig.consultation.refresh();
      await _pumpPremium(t, rig, manager: _FakeSubscriptionManager());
      await t.pump();

      expect(find.text('Premium actif'), findsOneWidget);
      expect(find.text('Gérer mon abonnement'), findsOneWidget);
      expect(find.text('S’abonner'), findsNothing);
      expect(find.text('Temps disponible'), findsOneWidget);
      // pas de bouton « Annuler » / « Résilier » fake (Partie L)
      expect(find.widgetWithText(TextButton, 'Annuler'), findsNothing);
      expect(find.textContaining('Résilier mon abonnement'), findsNothing);
    });

    testWidgets('K — « Gérer mon abonnement » ouvre la gestion store '
        '(abstraction), succès -> aucun snackbar', (t) async {
      final rig = _rig(
        handler: (r) async => r.url.path == '/api/consultation/state'
            ? _json(_stateBody(premium: true, premiumSec: 3600))
            : _json({}, 404),
      );
      rig.gateway.products = [_product()];
      await rig.controller.initialize();
      await rig.consultation.refresh();
      final mgr = _FakeSubscriptionManager(result: true);
      await _pumpPremium(t, rig, manager: mgr);
      await t.pump();

      await t.tap(find.text('Gérer mon abonnement'));
      await t.pumpAndSettle();
      expect(mgr.openCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('K — échec ouverture store -> message de repli, '
        'JAMAIS « abonnement résilié »', (t) async {
      final rig = _rig(
        handler: (r) async => r.url.path == '/api/consultation/state'
            ? _json(_stateBody(premium: true, premiumSec: 3600))
            : _json({}, 404),
      );
      rig.gateway.products = [_product()];
      await rig.controller.initialize();
      await rig.consultation.refresh();
      final mgr = _FakeSubscriptionManager(result: false);
      await _pumpPremium(t, rig, manager: mgr);
      await t.pump();

      await t.tap(find.text('Gérer mon abonnement'));
      await t.pumpAndSettle();
      expect(mgr.openCalls, 1);
      expect(find.textContaining('Ouvre l’app Google Play'), findsOneWidget);
      expect(find.textContaining('résilié'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 27 — aucun Stripe / paiement web dans le tunnel PremiumScreen
  // -------------------------------------------------------------------------
  testWidgets('27 — PremiumScreen ne mentionne ni Stripe ni paiement web', (
    t,
  ) async {
    final rig = _rig(handler: (_) async => _json({}, 404));
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await _pumpPremium(t, rig, manager: _FakeSubscriptionManager());
    await t.pump();
    expect(find.textContaining('Stripe'), findsNothing);
    expect(find.textContaining('carte bancaire'), findsNothing);
    expect(find.textContaining('http'), findsNothing);
  });
}

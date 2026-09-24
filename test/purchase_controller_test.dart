import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/billing_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/iap_gateway.dart';
import 'package:auryel/data/purchase.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/state/purchase_controller.dart';

// ===========================================================================
// Faux IapGateway — aucun canal de plateforme, aucun store réel.
// ===========================================================================
class FakeIapGateway implements IapGateway {
  FakeIapGateway({List<String>? log}) : log = log ?? <String>[];

  final List<String> log;

  bool available = true;
  List<ProductDetails> products = <ProductDetails>[];
  List<String> notFoundIDs = <String>[];
  Object? queryError;
  Object? buyError;
  Object? completeError;

  int buyCalls = 0;
  int restoreCalls = 0;
  int streamAccesses = 0;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  final StreamController<List<PurchaseDetails>> _ctrl =
      StreamController<List<PurchaseDetails>>.broadcast();

  void emit(List<PurchaseDetails> list) => _ctrl.add(list);
  Future<void> close() => _ctrl.close();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    if (queryError != null) throw queryError!;
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: notFoundIDs,
    );
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    streamAccesses++;
    return _ctrl.stream;
  }

  @override
  Future<bool> buyNonConsumable(ProductDetails product) async {
    buyCalls++;
    log.add('buy');
    if (buyError != null) throw buyError!;
    return true;
  }

  int buyConsumableCalls = 0;

  @override
  Future<bool> buyConsumable(ProductDetails product) async {
    buyConsumableCalls++;
    log.add('buyConsumable');
    if (buyError != null) throw buyError!;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (completeError != null) throw completeError!;
    log.add('complete');
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
    log.add('restore');
  }
}

// ===========================================================================
// Fixtures
// ===========================================================================
http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _stateBody({bool isPremium = true, int limit = 4}) => {
  'consultation': null,
  'quota': {
    'is_premium': isPremium,
    'monthly_limit': limit,
    'monthly_used': 0,
    'monthly_remaining': limit,
    'earned_available': 0,
    'period_start': '2026-09-01T00:00:00Z',
    'period_end': '2026-10-01T00:00:00Z',
  },
};

Map<String, dynamic> _verifyOk({bool entitled = true}) => {
  'subscription': {
    'store': 'google_play',
    'product_id': kPremiumMonthlyProductId,
    'status': 'active',
    'entitled': entitled,
    'expires_at': '2026-10-01T00:00:00Z',
  },
  'quota': _stateBody(isPremium: entitled)['quota'],
};

ProductDetails _product() => ProductDetails(
  id: kPremiumMonthlyProductId,
  title: 'Auryel Premium',
  description: '4 consultations / mois',
  price: '4,99 €',
  rawPrice: 4.99,
  currencyCode: 'EUR',
  currencySymbol: '€',
);

PurchaseDetails _pd({
  String? purchaseID = 'pid-1',
  String productID = kPremiumMonthlyProductId,
  String serverData = 'gpa-token-abc',
  PurchaseStatus status = PurchaseStatus.purchased,
  bool pendingComplete = true,
  IAPError? error,
}) {
  final pd = PurchaseDetails(
    purchaseID: purchaseID,
    productID: productID,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: serverData,
      source: 'test',
    ),
    transactionDate: '1700000000000',
    status: status,
  );
  pd.pendingCompletePurchase = pendingComplete;
  pd.error = error;
  return pd;
}

typedef _Rig = ({
  PurchaseController controller,
  FakeIapGateway gateway,
  InMemoryTokenStore tokens,
  AuthController auth,
  ConsultationController consultation,
  List<String> log,
});

_Rig _rig({
  String? token = 'tok',
  TargetPlatform platform = TargetPlatform.android,
  required Future<http.Response> Function(http.Request req) handler,
}) {
  final log = <String>[];
  final tokens = InMemoryTokenStore(token);
  final client = ApiClient(
    httpClient: MockClient((req) async {
      log.add('${req.method} ${req.url.path}');
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  final consultationApi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
    profileApi: ProfileApi(client),
    consultationApi: consultationApi,
    tirageApi: TirageApi(client),
  );
  final consultation = ConsultationController(api: consultationApi, auth: auth);
  final gateway = FakeIapGateway(log: log);
  final controller = PurchaseController(
    billing: BillingApi(client),
    gateway: gateway,
    auth: auth,
    consultation: consultation,
    platformOverride: platform,
  );
  addTearDown(() async {
    controller.dispose();
    consultation.dispose();
    await gateway.close();
  });
  return (
    controller: controller,
    gateway: gateway,
    tokens: tokens,
    auth: auth,
    consultation: consultation,
    log: log,
  );
}

/// Handler « tout va bien » : verify 200 + state 200.
Future<http.Response> _happy(http.Request req) async {
  if (req.url.path == '/api/billing/verify') return _json(_verifyOk());
  if (req.url.path == '/api/consultation/state') return _json(_stateBody());
  return _json({}, 404);
}

void main() {
  // -------------------------------------------------------------------------
  // A / B / C — chargement produit
  // -------------------------------------------------------------------------
  test('A produit disponible -> premiumProduct exposé, état idle', () async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    expect(rig.controller.premiumProduct?.id, kPremiumMonthlyProductId);
    expect(rig.controller.state, PurchaseState.idle);
    expect(rig.controller.canBuy, isTrue);
  });

  test(
    'B produit indisponible (notFoundIDs) -> productsUnavailable, pas de crash',
    () async {
      final rig = _rig(handler: _happy);
      rig.gateway.products = [];
      rig.gateway.notFoundIDs = [kPremiumMonthlyProductId];
      await rig.controller.initialize();
      expect(rig.controller.state, PurchaseState.productsUnavailable);
      expect(rig.controller.premiumProduct, isNull);
      expect(rig.controller.canBuy, isFalse);
    },
  );

  test('C store indisponible -> storeUnavailable', () async {
    final rig = _rig(handler: _happy);
    rig.gateway.available = false;
    await rig.controller.initialize();
    expect(rig.controller.state, PurchaseState.storeUnavailable);
  });

  // -------------------------------------------------------------------------
  // D / E / F — statuts store
  // -------------------------------------------------------------------------
  test(
    'D achat pending -> pendingStore, aucun verify, aucun complete',
    () async {
      final rig = _rig(handler: _happy);
      await rig.controller.initialize();
      rig.gateway.emit([_pd(status: PurchaseStatus.pending)]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.pendingStore);
      expect(rig.log.contains('POST /api/billing/verify'), isFalse);
      expect(rig.gateway.completed, isEmpty);
    },
  );

  test('E achat canceled -> canceled, aucun verify', () async {
    final rig = _rig(handler: _happy);
    await rig.controller.initialize();
    rig.gateway.emit([_pd(status: PurchaseStatus.canceled)]);
    await pumpEventQueue();
    expect(rig.controller.state, PurchaseState.canceled);
    expect(rig.log.contains('POST /api/billing/verify'), isFalse);
  });

  test(
    'F erreur store -> storeError, aucun entitlement, aucun complete',
    () async {
      final rig = _rig(handler: _happy);
      await rig.controller.initialize();
      rig.gateway.emit([
        _pd(
          status: PurchaseStatus.error,
          error: IAPError(source: 'test', code: 'store_boom', message: 'boom'),
        ),
      ]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.storeError);
      expect(rig.controller.errorCode, 'store_boom');
      expect(rig.gateway.completed, isEmpty);
    },
  );

  // -------------------------------------------------------------------------
  // G / H / I — preuve store selon plateforme
  // -------------------------------------------------------------------------
  test(
    'G Android purchased -> serverVerificationData envoyé comme purchase_token',
    () async {
      Map<String, dynamic>? sent;
      final rig = _rig(
        platform: TargetPlatform.android,
        handler: (req) async {
          if (req.url.path == '/api/billing/verify') {
            sent = jsonDecode(req.body) as Map<String, dynamic>;
            return _json(_verifyOk());
          }
          return _json(_stateBody());
        },
      );
      await rig.controller.initialize();
      rig.gateway.emit([
        _pd(serverData: 'THE-GOOGLE-TOKEN', purchaseID: 'pid-x'),
      ]);
      await pumpEventQueue();
      expect(sent, {
        'store': 'google_play',
        'product_id': 'auryel_premium_monthly',
        'purchase_token': 'THE-GOOGLE-TOKEN',
      });
    },
  );

  test('H iOS purchased -> purchaseID envoyé comme transaction_id', () async {
    Map<String, dynamic>? sent;
    final rig = _rig(
      platform: TargetPlatform.iOS,
      handler: (req) async {
        if (req.url.path == '/api/billing/verify') {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return _json(_verifyOk());
        }
        return _json(_stateBody());
      },
    );
    await rig.controller.initialize();
    rig.gateway.emit([
      _pd(purchaseID: 'APPLE-TXN-1', serverData: 'ignored-jws'),
    ]);
    await pumpEventQueue();
    expect(sent, {
      'store': 'app_store',
      'product_id': 'auryel_premium_monthly',
      'transaction_id': 'APPLE-TXN-1',
    });
  });

  test(
    'I iOS purchaseID null/vide -> aucun verify, verifyFatal, aucun complete',
    () async {
      final rig = _rig(platform: TargetPlatform.iOS, handler: _happy);
      await rig.controller.initialize();
      rig.gateway.emit([_pd(purchaseID: null)]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.verifyFatal);
      expect(rig.controller.errorCode, 'missing_transaction_id');
      expect(rig.log.contains('POST /api/billing/verify'), isFalse);
      expect(rig.gateway.completed, isEmpty);
      expect(rig.controller.hasPendingRetry, isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // J — ordre strict verify -> refresh -> complete
  // -------------------------------------------------------------------------
  test('J backend 200 -> verify puis refresh puis complete (ordre)', () async {
    final rig = _rig(handler: _happy);
    await rig.controller.initialize();
    rig.log.clear();
    rig.gateway.emit([_pd()]);
    await pumpEventQueue();

    expect(rig.log, [
      'POST /api/billing/verify',
      'GET /api/consultation/state',
      'complete',
    ]);
    expect(rig.controller.state, PurchaseState.active);
    expect(rig.consultation.quota?.isPremium, isTrue);
    expect(rig.gateway.completed, hasLength(1));
  });

  // -------------------------------------------------------------------------
  // K / L / M / N / O / P — erreurs backend
  // -------------------------------------------------------------------------
  test(
    'K backend 401 -> requiresAuthentication, aucun complete, retry armé',
    () async {
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/verify') {
            return _json({'error': 'unauthorized'}, 401);
          }
          return _json(_stateBody());
        },
      );
      await rig.controller.initialize();
      rig.gateway.emit([_pd()]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.requiresAuthentication);
      expect(rig.gateway.completed, isEmpty);
      expect(rig.controller.hasPendingRetry, isTrue);
      expect(await rig.tokens.read(), isNull); // session invalidée
    },
  );

  test('L backend 409 -> verifyFatal, aucun complete, pas de retry', () async {
    final rig = _rig(
      handler: (req) async {
        if (req.url.path == '/api/billing/verify') {
          return _json({'error': 'account_mismatch'}, 409);
        }
        return _json(_stateBody());
      },
    );
    await rig.controller.initialize();
    rig.gateway.emit([_pd()]);
    await pumpEventQueue();
    expect(rig.controller.state, PurchaseState.verifyFatal);
    expect(rig.controller.errorCode, 'account_mismatch');
    expect(rig.gateway.completed, isEmpty);
    expect(rig.controller.hasPendingRetry, isFalse);
  });

  test('M backend 422 -> verifyFatal, aucun complete', () async {
    final rig = _rig(
      handler: (req) async {
        if (req.url.path == '/api/billing/verify') {
          return _json({'error': 'invalid_store_receipt'}, 422);
        }
        return _json(_stateBody());
      },
    );
    await rig.controller.initialize();
    rig.gateway.emit([_pd()]);
    await pumpEventQueue();
    expect(rig.controller.state, PurchaseState.verifyFatal);
    expect(rig.gateway.completed, isEmpty);
    expect(rig.controller.hasPendingRetry, isFalse);
  });

  test(
    'N backend 503 -> verifyRetryable, aucun complete, retry armé',
    () async {
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/verify') {
            return _json({'error': 'verification_not_configured'}, 503);
          }
          return _json(_stateBody());
        },
      );
      await rig.controller.initialize();
      rig.gateway.emit([_pd()]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.verifyRetryable);
      expect(rig.controller.errorCode, 'verification_not_configured');
      expect(rig.gateway.completed, isEmpty);
      expect(rig.controller.hasPendingRetry, isTrue);
    },
  );

  test('O réseau -> verifyRetryable, retry armé', () async {
    final rig = _rig(
      handler: (req) async {
        if (req.url.path == '/api/billing/verify') {
          throw http.ClientException('offline');
        }
        return _json(_stateBody());
      },
    );
    await rig.controller.initialize();
    rig.gateway.emit([_pd()]);
    await pumpEventQueue();
    expect(rig.controller.state, PurchaseState.verifyRetryable);
    expect(rig.controller.errorCode, 'network');
    expect(rig.controller.hasPendingRetry, isTrue);
  });

  test('P backend 500 -> verifyRetryable', () async {
    final rig = _rig(
      handler: (req) async {
        if (req.url.path == '/api/billing/verify') {
          return _json({'error': 'internal_error'}, 500);
        }
        return _json(_stateBody());
      },
    );
    await rig.controller.initialize();
    rig.gateway.emit([_pd()]);
    await pumpEventQueue();
    expect(rig.controller.state, PurchaseState.verifyRetryable);
    expect(rig.gateway.completed, isEmpty);
    expect(rig.controller.hasPendingRetry, isTrue);
  });

  // -------------------------------------------------------------------------
  // Q — retryVerification
  // -------------------------------------------------------------------------
  test(
    'Q retryVerification -> réutilise l’achat en attente, 200 -> complete',
    () async {
      var verifyCalls = 0;
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/verify') {
            verifyCalls++;
            if (verifyCalls == 1) {
              return _json({'error': 'verification_not_configured'}, 503);
            }
            return _json(_verifyOk());
          }
          return _json(_stateBody());
        },
      );
      await rig.controller.initialize();
      rig.gateway.emit([_pd(serverData: 'same-token')]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.verifyRetryable);

      await rig.controller.retryVerification();
      await pumpEventQueue();

      expect(verifyCalls, 2);
      expect(rig.controller.state, PurchaseState.active);
      expect(rig.gateway.completed, hasLength(1));
      expect(rig.controller.hasPendingRetry, isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // R — restore passe par le même pipeline
  // -------------------------------------------------------------------------
  test('R restored -> verify serveur -> refresh -> complete', () async {
    final rig = _rig(handler: _happy);
    await rig.controller.initialize();
    rig.log.clear();
    rig.gateway.emit([_pd(status: PurchaseStatus.restored)]);
    await pumpEventQueue();
    expect(rig.log, [
      'POST /api/billing/verify',
      'GET /api/consultation/state',
      'complete',
    ]);
    expect(rig.controller.state, PurchaseState.active);
  });

  test('R2 restorePurchases() appelle le gateway', () async {
    final rig = _rig(handler: _happy);
    await rig.controller.initialize();
    await rig.controller.restorePurchases();
    expect(rig.gateway.restoreCalls, 1);
  });

  // -------------------------------------------------------------------------
  // S — double événement simultané -> un seul verify en vol
  // -------------------------------------------------------------------------
  test('S deux events identiques simultanés -> 1 seul verify', () async {
    var verifyCalls = 0;
    final rig = _rig(
      handler: (req) async {
        if (req.url.path == '/api/billing/verify') {
          verifyCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return _json(_verifyOk());
        }
        return _json(_stateBody());
      },
    );
    await rig.controller.initialize();
    final a = _pd(serverData: 'dup-token', purchaseID: 'p');
    final b = _pd(serverData: 'dup-token', purchaseID: 'p');
    rig.gateway.emit([a]);
    rig.gateway.emit([b]);
    await pumpEventQueue();
    expect(verifyCalls, 1);
  });

  // -------------------------------------------------------------------------
  // T — après verify terminé, une future restauration peut re-vérifier
  // -------------------------------------------------------------------------
  test(
    'T après succès, la déduplication ne bloque pas une re-vérification',
    () async {
      var verifyCalls = 0;
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/verify') {
            verifyCalls++;
            return _json(_verifyOk());
          }
          return _json(_stateBody());
        },
      );
      await rig.controller.initialize();
      rig.gateway.emit([_pd(serverData: 'tok-1', purchaseID: 'p1')]);
      await pumpEventQueue();
      expect(verifyCalls, 1);
      expect(rig.controller.state, PurchaseState.active);

      // restore plus tard : même abonnement re-livré -> re-vérifié.
      rig.gateway.emit([
        _pd(
          serverData: 'tok-1',
          purchaseID: 'p1',
          status: PurchaseStatus.restored,
        ),
      ]);
      await pumpEventQueue();
      expect(verifyCalls, 2);
    },
  );

  // -------------------------------------------------------------------------
  // U — dispose annule la souscription
  // -------------------------------------------------------------------------
  test('U dispose -> plus aucun traitement des events', () async {
    final rig = _rig(handler: _happy);
    await rig.controller.initialize();
    rig.controller.dispose();
    rig.log.clear();
    rig.gateway.emit([_pd()]);
    await pumpEventQueue();
    expect(rig.log, isEmpty);
    expect(rig.gateway.completed, isEmpty);
  });

  // -------------------------------------------------------------------------
  // V — initialize() 2x -> pas de double listener
  // -------------------------------------------------------------------------
  test('V initialize() idempotent -> une seule souscription', () async {
    final rig = _rig(handler: _happy);
    await rig.controller.initialize();
    await rig.controller.initialize();
    expect(rig.gateway.streamAccesses, 1);
  });

  // -------------------------------------------------------------------------
  // W — aucun Premium accordé sur la seule foi de PurchaseStatus.purchased
  // -------------------------------------------------------------------------
  test(
    'W purchased mais verify jamais 200 -> jamais active, jamais complete',
    () async {
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/verify') {
            return _json({'error': 'verification_not_configured'}, 503);
          }
          return _json(_stateBody(isPremium: false));
        },
      );
      await rig.controller.initialize();
      rig.gateway.emit([_pd()]);
      await pumpEventQueue();
      expect(rig.controller.state, isNot(PurchaseState.active));
      expect(rig.gateway.completed, isEmpty);
      expect(rig.consultation.quota?.isPremium ?? false, isFalse);
    },
  );

  // -------------------------------------------------------------------------
  // Bearer absent au moment du verify
  // -------------------------------------------------------------------------
  test(
    'pas de Bearer -> requiresAuthentication, aucun verify, aucun complete',
    () async {
      final rig = _rig(token: null, handler: _happy);
      await rig.controller.initialize();
      rig.gateway.emit([_pd()]);
      await pumpEventQueue();
      expect(rig.controller.state, PurchaseState.requiresAuthentication);
      expect(rig.log.contains('POST /api/billing/verify'), isFalse);
      expect(rig.gateway.completed, isEmpty);
      expect(rig.controller.hasPendingRetry, isTrue);
    },
  );

  // -------------------------------------------------------------------------
  // buyPremium -> délègue au gateway
  // -------------------------------------------------------------------------
  test('buyPremium -> gateway.buyNonConsumable, état purchasing', () async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await rig.controller.buyPremium();
    expect(rig.gateway.buyCalls, 1);
    expect(rig.controller.state, PurchaseState.purchasing);
  });

  test('buyPremium sans produit chargé -> no-op', () async {
    final rig = _rig(handler: _happy);
    rig.gateway.notFoundIDs = [kPremiumMonthlyProductId];
    await rig.controller.initialize();
    await rig.controller.buyPremium();
    expect(rig.gateway.buyCalls, 0);
  });

  // =========================================================================
  // « 1 heure supplémentaire » (auryel_extra_hour) — consommable, répétable
  // =========================================================================
  group('extra hour', () {
    ProductDetails extraProduct() => ProductDetails(
      id: kExtraHourProductId,
      title: '1 heure supplémentaire',
      description: '1 heure de consultation',
      price: '1,99 €',
      rawPrice: 1.99,
      currencyCode: 'EUR',
      currencySymbol: '€',
    );

    PurchaseDetails pdExtra({
      String serverData = 'gpa-extra-token',
      PurchaseStatus status = PurchaseStatus.purchased,
      bool pendingComplete = true,
    }) {
      final pd = PurchaseDetails(
        purchaseID: 'extra-pid-1',
        productID: kExtraHourProductId,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'local',
          serverVerificationData: serverData,
          source: 'test',
        ),
        transactionDate: '1700000000000',
        status: status,
      );
      pd.pendingCompletePurchase = pendingComplete;
      return pd;
    }

    Map<String, dynamic> purchaseOk({bool already = false}) => {
      'purchase': {
        'store': 'google_play',
        'product_id': kExtraHourProductId,
        'credited_seconds': already ? 0 : 3600,
        'already_credited': already,
      },
      'quota': _stateBody(isPremium: false)['quota'],
    };

    Map<String, dynamic> applePurchaseOk({bool already = false}) => {
      'purchase': {
        'store': 'app_store',
        'product_id': kExtraHourProductId,
        'credited_seconds': already ? 0 : 3600,
        'already_credited': already,
      },
      'quota': _stateBody(isPremium: false)['quota'],
    };

    Future<http.Response> happyExtra(http.Request req) async {
      if (req.url.path == '/api/billing/purchase') return _json(purchaseOk());
      if (req.url.path == '/api/consultation/state') {
        return _json(_stateBody());
      }
      return _json({}, 404);
    }

    test(
      'loadProducts : extra_hour chargé indépendamment de Premium',
      () async {
        final rig = _rig(handler: happyExtra);
        rig.gateway.products = [_product(), extraProduct()];
        await rig.controller.initialize();
        expect(rig.controller.extraHourProduct?.id, kExtraHourProductId);
        expect(rig.controller.extraHourState, ExtraHourPurchaseState.idle);
        expect(rig.controller.canBuyExtraHour, isTrue);
        expect(rig.controller.premiumProduct?.id, kPremiumMonthlyProductId);
        expect(rig.controller.state, PurchaseState.idle);
      },
    );

    test('extra_hour absent -> unavailable, Premium inchangé', () async {
      final rig = _rig(handler: happyExtra);
      rig.gateway.products = [_product()];
      rig.gateway.notFoundIDs = [kExtraHourProductId];
      await rig.controller.initialize();
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.unavailable);
      expect(rig.controller.extraHourProduct, isNull);
      expect(rig.controller.canBuyExtraHour, isFalse);
      expect(rig.controller.state, PurchaseState.idle);
      expect(rig.controller.premiumProduct, isNotNull);
    });

    test('buyExtraHour -> gateway.buyConsumable, état purchasing', () async {
      final rig = _rig(handler: happyExtra);
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      await rig.controller.buyExtraHour();
      expect(rig.gateway.buyConsumableCalls, 1);
      expect(rig.gateway.buyCalls, 0);
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.purchasing);
    });

    test('purchased -> POST /api/billing/purchase, refresh, complete (ordre), '
        'état credited', () async {
      final rig = _rig(handler: happyExtra);
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.log.clear();
      rig.gateway.emit([pdExtra()]);
      await pumpEventQueue();
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.credited);
      final purchaseIdx = rig.log.indexOf('POST /api/billing/purchase');
      final stateIdx = rig.log.indexOf('GET /api/consultation/state');
      final completeIdx = rig.log.indexOf('complete');
      expect(purchaseIdx, greaterThanOrEqualTo(0));
      expect(purchaseIdx < stateIdx, isTrue);
      expect(stateIdx < completeIdx, isTrue);
      expect(rig.gateway.completed.single.productID, kExtraHourProductId);
      // Premium jamais touché.
      expect(rig.controller.state, PurchaseState.idle);
    });

    test('already_credited -> état alreadyCredited, complete quand même, '
        'aucun double crédit', () async {
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/purchase') {
            return _json(purchaseOk(already: true));
          }
          if (req.url.path == '/api/consultation/state') {
            return _json(_stateBody());
          }
          return _json({}, 404);
        },
      );
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.gateway.emit([pdExtra()]);
      await pumpEventQueue();
      expect(
        rig.controller.extraHourState,
        ExtraHourPurchaseState.alreadyCredited,
      );
      expect(rig.gateway.completed, hasLength(1));
    });

    test('pending -> pendingStore, aucun POST', () async {
      final rig = _rig(handler: happyExtra);
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.log.clear();
      rig.gateway.emit([pdExtra(status: PurchaseStatus.pending)]);
      await pumpEventQueue();
      expect(
        rig.controller.extraHourState,
        ExtraHourPurchaseState.pendingStore,
      );
      expect(rig.log.contains('POST /api/billing/purchase'), isFalse);
    });

    test('canceled -> canceled, aucun POST', () async {
      final rig = _rig(handler: happyExtra);
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.gateway.emit([pdExtra(status: PurchaseStatus.canceled)]);
      await pumpEventQueue();
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.canceled);
      expect(rig.gateway.completed, isEmpty);
    });

    test('503 -> verifyRetryable + pending retry; retry re-poste', () async {
      var calls = 0;
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/purchase') {
            calls++;
            if (calls == 1) return _json({'error': 'x'}, 503);
            return _json(purchaseOk());
          }
          if (req.url.path == '/api/consultation/state') {
            return _json(_stateBody());
          }
          return _json({}, 404);
        },
      );
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.gateway.emit([pdExtra()]);
      await pumpEventQueue();
      expect(
        rig.controller.extraHourState,
        ExtraHourPurchaseState.verifyRetryable,
      );
      expect(rig.controller.hasExtraHourPendingRetry, isTrue);
      expect(rig.gateway.completed, isEmpty);

      await rig.controller.retryExtraHourVerification();
      await pumpEventQueue();
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.credited);
      expect(rig.gateway.completed, hasLength(1));
      expect(rig.controller.hasExtraHourPendingRetry, isFalse);
    });

    test('422 -> verifyFatal, aucun complete, pas de retry', () async {
      final rig = _rig(
        handler: (req) async {
          if (req.url.path == '/api/billing/purchase') {
            return _json({'error': 'invalid_store_receipt'}, 422);
          }
          if (req.url.path == '/api/consultation/state') {
            return _json(_stateBody());
          }
          return _json({}, 404);
        },
      );
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.gateway.emit([pdExtra()]);
      await pumpEventQueue();
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.verifyFatal);
      expect(rig.gateway.completed, isEmpty);
      expect(rig.controller.hasExtraHourPendingRetry, isFalse);
    });

    test(
      'sans session -> requiresAuthentication, aucun POST, retry armé',
      () async {
        final rig = _rig(token: null, handler: happyExtra);
        rig.gateway.products = [_product(), extraProduct()];
        await rig.controller.initialize();
        rig.log.clear();
        rig.gateway.emit([pdExtra()]);
        await pumpEventQueue();
        expect(
          rig.controller.extraHourState,
          ExtraHourPurchaseState.requiresAuthentication,
        );
        expect(rig.log.contains('POST /api/billing/purchase'), isFalse);
        expect(rig.gateway.completed, isEmpty);
        expect(rig.controller.hasExtraHourPendingRetry, isTrue);
      },
    );

    test('iOS purchased -> validation App Store, +1h, complete', () async {
      final rig = _rig(
        platform: TargetPlatform.iOS,
        handler: (req) async {
          if (req.url.path == '/api/billing/purchase') {
            return _json(applePurchaseOk());
          }
          if (req.url.path == '/api/consultation/state') {
            return _json(_stateBody());
          }
          return _json({}, 404);
        },
      );
      rig.gateway.products = [_product(), extraProduct()];
      await rig.controller.initialize();
      rig.log.clear();
      rig.gateway.emit([pdExtra()]);
      await pumpEventQueue();
      expect(rig.controller.extraHourState, ExtraHourPurchaseState.credited);
      expect(rig.log.contains('POST /api/billing/purchase'), isTrue);
      expect(rig.gateway.completed, hasLength(1));
    });

    test(
      'iOS restored consommable -> jamais de validation ni de crédit',
      () async {
        final rig = _rig(platform: TargetPlatform.iOS, handler: happyExtra);
        rig.gateway.products = [_product(), extraProduct()];
        await rig.controller.initialize();
        rig.log.clear();
        rig.gateway.emit([pdExtra(status: PurchaseStatus.restored)]);
        await pumpEventQueue();
        expect(
          rig.controller.extraHourState,
          ExtraHourPurchaseState.verifyFatal,
        );
        expect(rig.controller.extraHourError, 'consumable_not_restorable');
        expect(rig.log.contains('POST /api/billing/purchase'), isFalse);
        expect(rig.gateway.completed, isEmpty);
      },
    );

    test(
      'achat Premium reste intact quand le contrôleur gère aussi +1 h',
      () async {
        final rig = _rig(
          handler: (req) async {
            if (req.url.path == '/api/billing/verify') {
              return _json(_verifyOk());
            }
            if (req.url.path == '/api/billing/purchase') {
              return _json(purchaseOk());
            }
            if (req.url.path == '/api/consultation/state') {
              return _json(_stateBody());
            }
            return _json({}, 404);
          },
        );
        rig.gateway.products = [_product(), extraProduct()];
        await rig.controller.initialize();
        rig.gateway.emit([_pd()]);
        await pumpEventQueue();
        expect(rig.controller.state, PurchaseState.active);
        expect(rig.controller.extraHourState, ExtraHourPurchaseState.idle);
      },
    );
  });
}

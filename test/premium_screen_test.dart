import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:auryel/screens/legal_document_screen.dart';
import 'package:auryel/screens/premium_screen.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/state/purchase_controller.dart';

// --- fake IapGateway minimal (aucun canal plateforme) ----------------------
class _FakeGateway implements IapGateway {
  bool available = true;
  List<ProductDetails> products = <ProductDetails>[];
  List<String> notFoundIDs = <String>[];
  int buyCalls = 0;
  int restoreCalls = 0;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  final _ctrl = StreamController<List<PurchaseDetails>>.broadcast();

  void emit(List<PurchaseDetails> l) => _ctrl.add(l);
  Future<void> close() => _ctrl.close();

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: products,
        notFoundIDs: notFoundIDs,
      );
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

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _stateBody() => {
  'consultation': null,
  'quota': {
    'is_premium': true,
    'monthly_limit': 4,
    'monthly_used': 0,
    'monthly_remaining': 4,
    'earned_available': 0,
    'first_free_available': false,
    'period_start': '2026-09-01T00:00:00Z',
    'period_end': '2026-10-01T00:00:00Z',
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
  'quota': _stateBody()['quota'],
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

PurchaseDetails _pd({
  PurchaseStatus status = PurchaseStatus.purchased,
  String server = 'gpa-tok',
}) {
  final pd = PurchaseDetails(
    purchaseID: 'pid',
    productID: kPremiumMonthlyProductId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'l',
      serverVerificationData: server,
      source: 'test',
    ),
    transactionDate: '1700000000000',
    status: status,
  );
  pd.pendingCompletePurchase = true;
  return pd;
}

typedef _Rig = ({
  PurchaseController controller,
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
  return (controller: controller, gateway: gateway, hits: hits);
}

Future<void> _pump(WidgetTester t, PurchaseController c) => t.pumpWidget(
  PurchaseScope(
    controller: c,
    child: const MaterialApp(home: PremiumScreen()),
  ),
);

Future<http.Response> _happy(http.Request r) async {
  if (r.url.path == '/api/billing/verify') return _json(_verifyOk());
  if (r.url.path == '/api/consultation/state') return _json(_stateBody());
  return _json({}, 404);
}

void main() {
  testWidgets('A/B produit dispo -> titre + prix store affichés', (t) async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product(price: '4,99 €')];
    await rig.controller.initialize();
    await _pump(t, rig.controller);
    await t.pump();

    expect(find.text('Auryel Premium'), findsOneWidget);
    expect(find.text('Ton cadeau de bienvenue'), findsOneWidget);
    expect(find.text('20 minutes de consultation offertes'), findsOneWidget);
    expect(find.text('Auryel Gratuit'), findsOneWidget);
    expect(find.text('0 €'), findsOneWidget);
    expect(find.text('4 h de consultation par mois'), findsOneWidget);
    expect(find.text('Sans publicité'), findsOneWidget);
    expect(find.text('4,99 €/mois'), findsOneWidget);
    expect(find.text('S’abonner'), findsOneWidget);
    expect(find.text('Restaurer mes achats'), findsOneWidget);
  });

  testWidgets('offre gratuite et cadeau commun visibles sans abonnement', (
    t,
  ) async {
    final rig = _rig(handler: _happy);
    rig.gateway.available = false;
    await rig.controller.initialize();
    await _pump(t, rig.controller);
    await t.pump();

    expect(find.byKey(const Key('premium-welcome-gift')), findsOneWidget);
    expect(find.byKey(const Key('premium-free-plan')), findsOneWidget);
    expect(find.text('Continuer gratuitement'), findsOneWidget);
    expect(find.text('4 h de consultation par mois'), findsOneWidget);
    expect(find.text('4,99 €/mois'), findsOneWidget);
  });

  testWidgets(
    'produit non chargé -> "Abonnement mensuel", pas de prix inventé',
    (t) async {
      final rig = _rig(handler: _happy);
      rig.gateway.notFoundIDs = [kPremiumMonthlyProductId];
      await rig.controller.initialize();
      await _pump(t, rig.controller);
      await t.pump();

      expect(find.text('4,99 €/mois'), findsOneWidget);
      expect(
        find.text('L’abonnement n’est pas encore disponible.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('C bouton S’abonner -> buyPremium (aucun InAppPurchase direct)', (
    t,
  ) async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await _pump(t, rig.controller);
    await t.pump();

    await t.ensureVisible(find.text('S’abonner'));
    await t.tap(find.text('S’abonner'));
    await t.pump();
    expect(rig.gateway.buyCalls, 1);
  });

  testWidgets('D "Restaurer mes achats" -> restorePurchases', (t) async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await _pump(t, rig.controller);
    await t.pump();

    await t.ensureVisible(find.text('Restaurer mes achats'));
    await t.tap(find.text('Restaurer mes achats'));
    await t.pump();
    expect(rig.gateway.restoreCalls, 1);
  });

  testWidgets('E store indisponible -> message contrôlé', (t) async {
    final rig = _rig(handler: _happy);
    rig.gateway.available = false;
    await rig.controller.initialize();
    await _pump(t, rig.controller);
    await t.pump();
    expect(
      find.text('Le service d’achat est temporairement indisponible.'),
      findsOneWidget,
    );
  });

  testWidgets('F verifyRetryable -> message + bouton "Réessayer" -> retry', (
    t,
  ) async {
    var verifyCalls = 0;
    final rig = _rig(
      handler: (r) async {
        if (r.url.path == '/api/billing/verify') {
          verifyCalls++;
          if (verifyCalls == 1) {
            return _json({'error': 'verification_not_configured'}, 503);
          }
          return _json(_verifyOk());
        }
        return _json(_stateBody());
      },
    );
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await _pump(t, rig.controller);

    rig.gateway.emit([_pd()]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(rig.controller.state, PurchaseState.verifyRetryable);
    expect(find.text('Réessayer'), findsOneWidget);

    await t.ensureVisible(find.text('Réessayer'));
    await t.tap(find.text('Réessayer'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(verifyCalls, 2);
    expect(rig.controller.state, PurchaseState.active);
  });

  testWidgets('G succès -> "Premium est activé."', (t) async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await _pump(t, rig.controller);

    rig.gateway.emit([_pd()]);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(rig.controller.state, PurchaseState.active);
    await t.pump();
    expect(find.text('Premium est activé.'), findsOneWidget);
    // bouton principal masqué en succès
    expect(find.text('S’abonner'), findsNothing);
  });

  testWidgets('canceled -> aucun message alarmant', (t) async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product()];
    await rig.controller.initialize();
    await _pump(t, rig.controller);

    rig.gateway.emit([_pd(status: PurchaseStatus.canceled)]);
    await t.pump();

    expect(rig.controller.state, PurchaseState.canceled);
    expect(find.textContaining('erreur'), findsNothing);
    expect(find.text('S’abonner'), findsOneWidget);
  });

  testWidgets('J3 — accès aux textes juridiques + infos essentielles, sans '
      'déclencher d\'achat', (t) async {
    final rig = _rig(handler: _happy);
    rig.gateway.products = [_product(price: '4,99 €')];
    await rig.controller.initialize();
    await _pump(t, rig.controller);
    await t.pump();

    // Rappel juridique essentiel présent sur l'écran d'achat.
    expect(find.text('4,99 €/mois'), findsOneWidget);
    expect(
      find.textContaining('renouvellement automatique via Google Play'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Résiliation à tout moment depuis le Store'),
      findsOneWidget,
    );

    // Liens vers les textes, dans l'app.
    expect(find.text('Conditions Premium'), findsOneWidget);
    expect(find.text('Politique de confidentialité'), findsOneWidget);

    final buyBefore = rig.gateway.buyCalls;
    await t.ensureVisible(find.text('Conditions Premium'));
    await t.tap(find.text('Conditions Premium'));
    await t.pumpAndSettle();

    // Écran de lecture in-app, AUCUN achat déclenché par la navigation.
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(
      find.textContaining('4 heures de consultation par mois'),
      findsWidgets,
    );
    expect(rig.gateway.buyCalls, buyBefore);
  });
}

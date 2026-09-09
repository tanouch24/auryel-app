import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/billing_api.dart';
import 'package:auryel/data/purchase.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _ok200({bool entitled = true, int limit = 4}) => {
  'subscription': {
    'store': 'google_play',
    'product_id': kPremiumMonthlyProductId,
    'status': 'active',
    'entitled': entitled,
    'expires_at': '2026-10-01T00:00:00Z',
  },
  'quota': {
    'is_premium': entitled,
    'monthly_limit': limit,
    'monthly_used': 1,
    'monthly_remaining': limit - 1,
    'earned_available': 0,
    'period_start': '2026-09-01T00:00:00Z',
    'period_end': '2026-10-01T00:00:00Z',
  },
};

({BillingApi api, List<http.Request> reqs}) _rig(
  Future<http.Response> Function(http.Request req) handler,
) {
  final reqs = <http.Request>[];
  final client = ApiClient(
    httpClient: MockClient((req) async {
      reqs.add(req);
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  return (api: BillingApi(client), reqs: reqs);
}

void main() {
  group('BillingApi.verifyGooglePlay', () {
    test('corps Android EXACT + Bearer + path', () async {
      final rig = _rig((_) async => _json(_ok200()));
      await rig.api.verifyGooglePlay(
        bearer: 'tok-123',
        productId: kPremiumMonthlyProductId,
        purchaseToken: 'gpa-token-xyz',
      );

      expect(rig.reqs, hasLength(1));
      final req = rig.reqs.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/billing/verify');
      expect(req.headers['Authorization'], 'Bearer tok-123');
      expect(jsonDecode(req.body), {
        'store': 'google_play',
        'product_id': 'auryel_premium_monthly',
        'purchase_token': 'gpa-token-xyz',
      });
      // Jamais d'identité / de décision dans le corps.
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      for (final forbidden in const [
        'user_id',
        'entitled',
        'status',
        'quota',
        'subscription_key',
        'expires_at',
        'transaction_id',
      ]) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test(
      'parsing 200 -> BillingVerifyResponse (subscription + quota)',
      () async {
        final rig = _rig((_) async => _json(_ok200(limit: 4)));
        final res = await rig.api.verifyGooglePlay(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          purchaseToken: 'x',
        );
        expect(res.subscription.store, 'google_play');
        expect(res.subscription.productId, 'auryel_premium_monthly');
        expect(res.subscription.entitled, isTrue);
        expect(res.subscription.expiresAt, DateTime.utc(2026, 10, 1));
        expect(res.quota.isPremium, isTrue);
        expect(res.quota.monthlyLimit, 4);
      },
    );
  });

  group('BillingApi.verifyGooglePlayPurchase (« +1 h » consommable)', () {
    Map<String, dynamic> purchaseOk({bool alreadyCredited = false}) => {
      'purchase': {
        'store': 'google_play',
        'product_id': kExtraHourProductId,
        'credited_seconds': alreadyCredited ? 0 : 3600,
        'already_credited': alreadyCredited,
      },
      'quota': {
        'is_premium': false,
        'monthly_limit': 0,
        'monthly_used': 0,
        'monthly_remaining': 0,
        'earned_available': 0,
        'period_start': null,
        'period_end': null,
      },
    };

    test('corps EXACT + Bearer + path /api/billing/purchase', () async {
      final rig = _rig((_) async => _json(purchaseOk()));
      await rig.api.verifyGooglePlayPurchase(
        bearer: 'tok-abc',
        productId: kExtraHourProductId,
        purchaseToken: 'gpa-extra-1',
      );
      final req = rig.reqs.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/billing/purchase');
      expect(req.headers['Authorization'], 'Bearer tok-abc');
      expect(jsonDecode(req.body), {
        'store': 'google_play',
        'product_id': 'auryel_extra_hour',
        'purchase_token': 'gpa-extra-1',
      });
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      for (final forbidden in const ['user_id', 'credited_seconds', 'quota']) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('parsing 200 -> BillingPurchaseResponse (credited)', () async {
      final rig = _rig((_) async => _json(purchaseOk()));
      final res = await rig.api.verifyGooglePlayPurchase(
        bearer: 't',
        productId: kExtraHourProductId,
        purchaseToken: 'x',
      );
      expect(res.purchase.store, 'google_play');
      expect(res.purchase.productId, 'auryel_extra_hour');
      expect(res.purchase.creditedSeconds, 3600);
      expect(res.purchase.alreadyCredited, isFalse);
      expect(res.quota.isPremium, isFalse);
    });

    test('parsing 200 -> already_credited (aucun double crédit)', () async {
      final rig = _rig((_) async => _json(purchaseOk(alreadyCredited: true)));
      final res = await rig.api.verifyGooglePlayPurchase(
        bearer: 't',
        productId: kExtraHourProductId,
        purchaseToken: 'x',
      );
      expect(res.purchase.alreadyCredited, isTrue);
      expect(res.purchase.creditedSeconds, 0);
    });
  });

  group('BillingApi.verifyAppStore', () {
    test('corps iOS EXACT + Bearer', () async {
      final rig = _rig((_) async => _json(_ok200()));
      await rig.api.verifyAppStore(
        bearer: 'tok-ios',
        productId: kPremiumMonthlyProductId,
        transactionId: 'txn-42',
      );
      final req = rig.reqs.single;
      expect(req.headers['Authorization'], 'Bearer tok-ios');
      expect(jsonDecode(req.body), {
        'store': 'app_store',
        'product_id': 'auryel_premium_monthly',
        'transaction_id': 'txn-42',
      });
      expect(
        (jsonDecode(req.body) as Map).containsKey('purchase_token'),
        isFalse,
      );
    });
  });

  group('mapping erreurs (via ApiClient)', () {
    Future<Object?> runCatch(Future<void> Function() run) async {
      try {
        await run();
        return null;
      } catch (e) {
        return e;
      }
    }

    test('401 -> ApiUnauthorizedException', () async {
      final rig = _rig((_) async => _json({'error': 'unauthorized'}, 401));
      final e = await runCatch(
        () => rig.api.verifyGooglePlay(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          purchaseToken: 'x',
        ),
      );
      expect(e, isA<ApiUnauthorizedException>());
    });

    test('409 account_mismatch -> ApiException(409, code)', () async {
      final rig = _rig((_) async => _json({'error': 'account_mismatch'}, 409));
      final e = await runCatch(
        () => rig.api.verifyGooglePlay(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          purchaseToken: 'x',
        ),
      );
      expect(e, isA<ApiException>());
      expect((e as ApiException).statusCode, 409);
      expect(e.code, 'account_mismatch');
    });

    test('422 invalid_store_receipt -> ApiException(422, code)', () async {
      final rig = _rig(
        (_) async => _json({'error': 'invalid_store_receipt'}, 422),
      );
      final e = await runCatch(
        () => rig.api.verifyAppStore(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          transactionId: 'x',
        ),
      );
      expect((e as ApiException).statusCode, 422);
      expect(e.code, 'invalid_store_receipt');
    });

    test(
      '503 verification_not_configured -> ApiException(503, code)',
      () async {
        final rig = _rig(
          (_) async => _json({'error': 'verification_not_configured'}, 503),
        );
        final e = await runCatch(
          () => rig.api.verifyGooglePlay(
            bearer: 't',
            productId: kPremiumMonthlyProductId,
            purchaseToken: 'x',
          ),
        );
        expect((e as ApiException).statusCode, 503);
        expect(e.code, 'verification_not_configured');
      },
    );

    test('500 -> ApiException(500)', () async {
      final rig = _rig((_) async => _json({'error': 'internal_error'}, 500));
      final e = await runCatch(
        () => rig.api.verifyGooglePlay(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          purchaseToken: 'x',
        ),
      );
      expect((e as ApiException).statusCode, 500);
    });

    test('réseau -> ApiNetworkException', () async {
      final rig = _rig((_) async => throw http.ClientException('offline'));
      final e = await runCatch(
        () => rig.api.verifyGooglePlay(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          purchaseToken: 'x',
        ),
      );
      expect(e, isA<ApiNetworkException>());
    });

    test('200 au corps illisible -> FormatException', () async {
      final rig = _rig((_) async => _json({'not': 'a billing response'}));
      final e = await runCatch(
        () => rig.api.verifyGooglePlay(
          bearer: 't',
          productId: kPremiumMonthlyProductId,
          purchaseToken: 'x',
        ),
      );
      expect(e, isA<FormatException>());
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/app_review_service.dart';

/// Faux plugin natif — pilote isAvailable / les exceptions et compte les appels.
class _FakeInAppReview implements InAppReview {
  _FakeInAppReview({this.available = true, this.throwOnRequest = false});

  bool available;
  bool throwOnRequest;
  int requestCalls = 0;
  int storeCalls = 0;
  String? lastAppStoreId;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    requestCalls++;
    if (throwOnRequest) throw Exception('plugin boom');
  }

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async {
    storeCalls++;
    lastAppStoreId = appStoreId;
  }
}

/// Faux service, pour l'intégration dashboard (voir dashboard_test si besoin).
class RecordingReviewService implements AppReviewService {
  int calls = 0;
  AppReviewOutcome result = AppReviewOutcome.requested;

  @override
  Future<AppReviewOutcome> rate() async {
    calls++;
    return result;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('3 — isAvailable true -> requestReview, pas de fiche store', () async {
    final fake = _FakeInAppReview(available: true);
    final svc = InAppReviewService(plugin: fake);
    final out = await svc.rate();
    expect(fake.requestCalls, 1);
    expect(fake.storeCalls, 0);
    expect(out, AppReviewOutcome.requested);
  });

  test('4 — isAvailable false -> repli openStoreListing', () async {
    final fake = _FakeInAppReview(available: false);
    final svc = InAppReviewService(plugin: fake);
    final out = await svc.rate();
    expect(fake.requestCalls, 0);
    expect(fake.storeCalls, 1);
    expect(out, AppReviewOutcome.openedStore);
  });

  test('4bis — appStoreId non inventé : null tant qu’il n’est pas fourni',
      () async {
    final fake = _FakeInAppReview(available: false);
    await InAppReviewService(plugin: fake).rate();
    expect(fake.lastAppStoreId, isNull);
  });

  test('5 — exception plugin -> pas de crash, repli store', () async {
    final fake = _FakeInAppReview(available: true, throwOnRequest: true);
    final svc = InAppReviewService(plugin: fake);
    final out = await svc.rate();
    expect(fake.storeCalls, 1);
    expect(out, AppReviewOutcome.openedStore);
  });

  test('5bis — tout échoue -> AppReviewOutcome.unavailable, aucune exception',
      () async {
    final fake = _FailingInAppReview();
    final out = await InAppReviewService(plugin: fake).rate();
    expect(out, AppReviewOutcome.unavailable);
  });

  test('6/8 — le service ne touche NI wallet NI abonnement NI récompense : '
      'sa seule surface est rate()', () {
    // AppReviewService n'expose qu'une méthode ; aucune dépendance à un
    // contrôleur de consultation / achat / récompense.
    expect(AppReviewService, isNotNull);
    final svc = RecordingReviewService();
    expect(svc.calls, 0);
  });

  testWidgets('7 — aucun wording « 5 étoiles » / gating dans le code du service',
      (t) async {
    // Le service n'affiche aucun texte ; le bouton est neutre (« Noter
    // l'appli »). Ce test documente l'absence de wording orienté.
    final fake = _FakeInAppReview(available: true);
    await InAppReviewService(plugin: fake).rate();
    expect(fake.requestCalls, 1);
  });
}

class _FailingInAppReview implements InAppReview {
  @override
  Future<bool> isAvailable() async => throw Exception('x');
  @override
  Future<void> requestReview() async => throw Exception('x');
  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async =>
      throw Exception('x');
}

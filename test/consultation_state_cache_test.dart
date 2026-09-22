import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/consultation_state_cache.dart';

void main() {
  test('restaure exactement le dernier état vérifié par compte', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = ConsultationStateCache(prefs: prefs);
    const quota = QuotaDto(
      isPremium: true,
      monthlyLimit: 4,
      monthlyUsed: 1,
      monthlyRemaining: 3,
      earnedAvailable: 0,
      questionsAvailable: 0,
      periodStart: null,
      periodEnd: null,
      firstFreeAvailable: false,
    );
    final time = ConsultationTimeState(
      firstFreeRemainingSeconds: 0,
      premiumRemainingSeconds: 10_800,
      purchasedRemainingSeconds: 0,
      totalRemainingSeconds: 10_800,
      windowActive: true,
      windowExpiresAt: DateTime.utc(2026, 9, 22, 10, 5),
    );

    await cache.save(userId: 'user-a', quota: quota, time: time);
    final restored = await cache.load(userId: 'user-a');

    expect(restored?.quota.isPremium, isTrue);
    expect(restored?.quota.monthlyRemaining, 3);
    expect(restored?.time?.totalRemainingSeconds, 10_800);
    expect(restored?.time?.windowExpiresAt, time.windowExpiresAt);
    expect(await cache.load(userId: 'user-b'), isNull);
  });
}

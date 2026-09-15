import 'package:flutter_test/flutter_test.dart';
import 'package:auryel/ads/ad_service.dart';

void main() {
  test('prépare uniquement des identifiants SSV non sensibles', () {
    final options = rewardedSsvOptions(
      userId: 'user-uuid',
      customData: 'session-uuid',
    );
    expect(options.userId, 'user-uuid');
    expect(options.customData, 'session-uuid');
  });

  test('la configuration publique utilise le nouveau compte Rewarded', () {
    expect(
      AuryelAds.instance.productionRewardedUnitId,
      'ca-app-pub-9787163762873138/6173561021',
    );
    expect(
      AuryelAds.instance.productionBannerUnitId,
      'ca-app-pub-9787163762873138/9130449740',
    );
    expect(
      AuryelAds.instance.rewardedUnitId,
      'ca-app-pub-3940256099942544/5224354917',
    );
  });
}

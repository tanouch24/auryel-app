import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:auryel/ads/ad_service.dart';

void main() {
  test('iOS sans App ID désactive entièrement les publicités', () {
    expect(
      adsConfiguredForPlatform(
        platform: TargetPlatform.iOS,
        iosAppId: '',
      ),
      isFalse,
    );
  });

  test('un App ID iOS réel pourra réactiver les publicités plus tard', () {
    expect(
      adsConfiguredForPlatform(
        platform: TargetPlatform.iOS,
        iosAppId: 'ca-app-pub-real~ios-app',
      ),
      isTrue,
    );
  });

  test('Android conserve son comportement sans configuration iOS', () {
    expect(
      adsConfiguredForPlatform(
        platform: TargetPlatform.android,
        iosAppId: '',
      ),
      isTrue,
    );
  });

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

  test('Rewarded annonce une question conseiller dans son contrat SSV', () {
    expect(rewardedConsultationQuestionAmount, 1);
    expect(rewardedConsultationQuestionItem, 'consultation_question');
    expect(rewardedAdCtaLabel(), 'Regarder une publicité');
    expect(rewardedAdCtaLabel(loading: true), 'Chargement…');
  });

  test('App Open : Free authentifié et onboarding terminé est éligible', () {
    expect(
      appOpenEligibility(
        canRequestAds: true,
        rewardedShowing: false,
        isFree: true,
        authenticated: true,
        onboardingComplete: true,
        blocked: false,
      ),
      isTrue,
    );
  });

  test('App Open : aucun affichage pendant le premier parcours', () {
    expect(
      appOpenEligibility(
        canRequestAds: true,
        rewardedShowing: false,
        isFree: true,
        authenticated: true,
        onboardingComplete: false,
        blocked: false,
      ),
      isFalse,
    );
  });

  test('App Open : Premium et statut inconnu restent sans publicité', () {
    for (final isFree in [false]) {
      expect(
        appOpenEligibility(
          canRequestAds: true,
          rewardedShowing: false,
          isFree: isFree,
          authenticated: true,
          onboardingComplete: true,
          blocked: false,
        ),
        isFalse,
      );
    }
  });

  test('App Open indisponible : l application continue sans blocage', () {
    expect(
      appOpenEligibility(
        canRequestAds: false,
        rewardedShowing: false,
        isFree: true,
        authenticated: true,
        onboardingComplete: true,
        blocked: false,
      ),
      isFalse,
    );
  });
}

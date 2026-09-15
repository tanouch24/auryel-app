import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

ServerSideVerificationOptions rewardedSsvOptions({
  required String userId,
  required String customData,
}) => ServerSideVerificationOptions(userId: userId, customData: customData);

/// Façade unique AdMob. Les écrans ne manipulent jamais directement le SDK.
/// En debug, seuls les identifiants de test Google sont utilisés.
class AuryelAds {
  AuryelAds._();

  static final AuryelAds instance = AuryelAds._();

  static const _rewardedTest = 'ca-app-pub-3940256099942544/5224354917';
  static const _appOpenTest = 'ca-app-pub-3940256099942544/9257395921';
  static const _bannerTest = 'ca-app-pub-3940256099942544/6300978111';
  static const _rewardedProduction = 'ca-app-pub-6355299363807052/1344137680';
  static const _appOpenProduction = 'ca-app-pub-6355299363807052/4516417311';
  static const _bannerProduction = 'ca-app-pub-6355299363807052/5857419144';

  RewardedAd? _rewarded;
  AppOpenAd? _appOpen;
  bool _canRequestAds = false;
  bool _initializing = false;
  bool _rewardedShowing = false;
  DateTime? _lastRewardedAt;

  String get rewardedUnitId => kDebugMode ? _rewardedTest : _rewardedProduction;
  String get appOpenUnitId => kDebugMode ? _appOpenTest : _appOpenProduction;
  String get bannerUnitId => kDebugMode ? _bannerTest : _bannerProduction;
  bool get canRequestAds => _canRequestAds;
  bool get rewardedReady => _rewarded != null;
  bool get rewardedShowing => _rewardedShowing;

  /// Décision de confidentialité fournie par Google UMP.
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Ouvre le formulaire officiel UMP quand il est requis/disponible.
  Future<bool> showPrivacyOptions() async {
    try {
      final result = Completer<bool>();
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (!result.isCompleted) result.complete(error == null);
      });
      final shown = await result.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
      if (!shown) return false;
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (_canRequestAds) {
        _loadRewarded();
        _loadAppOpen();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await MobileAds.instance.initialize();
      final info = ConsentInformation.instance;
      final completer = Completer<void>();
      info.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            if (await info.isConsentFormAvailable()) {
              await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
            }
            _canRequestAds = await info.canRequestAds();
          } catch (_) {
            _canRequestAds = false;
          }
          if (!completer.isCompleted) completer.complete();
        },
        (_) {
          _canRequestAds = false;
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
      if (_canRequestAds) {
        _loadRewarded();
        _loadAppOpen();
      }
    } catch (_) {
      _canRequestAds = false;
    } finally {
      _initializing = false;
    }
  }

  void _loadRewarded() {
    if (!_canRequestAds || _rewarded != null) return;
    RewardedAd.load(
      adUnitId: rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// Retourne true uniquement si une publicité a été présentée et que le SDK
  /// a émis le callback de récompense. Une fermeture anticipée ne récompense pas.
  Future<bool> showRewarded({
    required Future<void> Function() onReward,
    ServerSideVerificationOptions? ssvOptions,
  }) async {
    if (!_canRequestAds || _rewarded == null) return false;
    final last = _lastRewardedAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return false;
    }
    final ad = _rewarded!;
    _rewarded = null;
    _rewardedShowing = true;
    var rewarded = false;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedShowing = false;
        if (!done.isCompleted) done.complete(rewarded);
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _rewardedShowing = false;
        if (!done.isCompleted) done.complete(false);
        _loadRewarded();
      },
    );
    try {
      if (ssvOptions != null) {
        await ad.setServerSideOptions(ssvOptions);
      }
      await ad.show(
        onUserEarnedReward: (_, ignoredReward) async {
          rewarded = true;
          _lastRewardedAt = DateTime.now();
          await onReward();
        },
      );
    } catch (_) {
      _rewardedShowing = false;
      if (!done.isCompleted) done.complete(false);
      _loadRewarded();
    }
    return done.future;
  }

  void _loadAppOpen() {
    if (!_canRequestAds || appOpenUnitId.isEmpty || _appOpen != null) return;
    AppOpenAd.load(
      adUnitId: appOpenUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => _appOpen = ad,
        onAdFailedToLoad: (_) => _appOpen = null,
      ),
    );
  }

  Future<void> showAppOpenIfEligible({
    required bool isFree,
    required bool authenticated,
    required bool onboardingComplete,
    required bool blocked,
  }) async {
    if (!_canRequestAds ||
        _rewardedShowing ||
        !isFree ||
        !authenticated ||
        !onboardingComplete ||
        blocked) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final stamp = '${today.year}-${today.month}-${today.day}';
    if (prefs.getString('last_app_open_ad_date') == stamp) return;
    final ad = _appOpen;
    if (ad == null) {
      _loadAppOpen();
      return;
    }
    _appOpen = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) async {
        await prefs.setString('last_app_open_ad_date', stamp);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadAppOpen();
      },
    );
    try {
      await ad.show();
    } catch (_) {
      _appOpen = null;
      _loadAppOpen();
    }
  }

  void dispose() {
    _rewarded?.dispose();
    _appOpen?.dispose();
    _rewarded = null;
    _appOpen = null;
  }
}

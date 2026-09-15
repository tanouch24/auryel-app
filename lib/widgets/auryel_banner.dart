import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_service.dart';

/// Bannière adaptative unique, affichée uniquement quand l'autorité Premium
/// confirme un compte Free. Statut inconnu ou erreur de chargement => espace
/// supprimé/fail-open, sans bloquer ni déplacer les actions de l'écran.
class AuryelBanner extends StatefulWidget {
  const AuryelBanner({super.key, required this.isPremium});

  final bool? isPremium;

  @override
  State<AuryelBanner> createState() => _AuryelBannerState();
}

class _AuryelBannerState extends State<AuryelBanner> {
  BannerAd? _ad;
  AdSize? _size;
  bool _loaded = false;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isPremium == false &&
        _ad == null &&
        AuryelAds.instance.canRequestAds) {
      _load();
    } else if (widget.isPremium == false && _ad == null) {
      _retryTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (AuryelAds.instance.canRequestAds && _ad == null) {
          _retryTimer?.cancel();
          _retryTimer = null;
          _load();
        }
      });
    }
  }

  Future<void> _load() async {
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null || widget.isPremium != false) return;
    final ad = BannerAd(
      adUnitId: AuryelAds.instance.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as BannerAd;
            _size = size;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    _ad = ad;
    _size = size;
    await ad.load();
  }

  @override
  void didUpdateWidget(covariant AuryelBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPremium != false && oldWidget.isPremium == false) {
      _ad?.dispose();
      _ad = null;
      _size = null;
      _loaded = false;
      _retryTimer?.cancel();
      _retryTimer = null;
    } else if (widget.isPremium == false && oldWidget.isPremium != false) {
      _load();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPremium != false || !_loaded || _ad == null || _size == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: _size!.width.toDouble(),
        height: _size!.height.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';

/// The legacy route is retained, but now presents the active Rewarded V1
/// entitlement state rather than the historical Stars wallet.
class RewardsWalletScreen extends StatefulWidget {
  const RewardsWalletScreen({super.key, this.controller});
  final RewardsController? controller;

  @override
  State<RewardsWalletScreen> createState() => _RewardsWalletScreenState();
}

class _RewardsWalletScreenState extends State<RewardsWalletScreen>
    with WidgetsBindingObserver {
  RewardsController? _controller;
  bool _ownsController = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = widget.controller ?? RewardsScope.maybeOf(context);
    if (_controller == null) {
      final auth = AuthScope.maybeOf(context);
      final api = auth?.rewardsApi;
      if (auth != null && api != null) {
        _controller = RewardsController(
          api: api,
          tokenProvider: auth.currentToken,
        );
        _ownsController = true;
      }
    }
    _controller?.addListener(_changed);
    _controller?.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller?.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_changed);
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  Future<void> _watch() async {
    if (_busy) return;
    final c = _controller;
    final auth = AuthScope.maybeOf(context);
    final account = auth?.account;
    final api = auth?.rewardsApi;
    if (c == null || auth == null || account == null || api == null) {
      setState(
        () => _message = 'Validation publicitaire indisponible pour le moment.',
      );
      return;
    }
    final token = await auth.currentToken();
    if (token == null) {
      setState(
        () => _message = 'Validation publicitaire indisponible pour le moment.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    String? session;
    try {
      session = await api.createAdmobRewardSession(token);
    } catch (_) {}
    if (session == null || !mounted) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Publicité indisponible pour le moment.';
        });
      }
      return;
    }
    final shown = await AuryelAds.instance.showRewarded(
      ssvOptions: rewardedSsvOptions(
        userId: account.userId,
        customData: session,
      ),
      onReward: () async {
        var credited = false;
        for (var i = 0; i < 8 && mounted; i++) {
          if (i > 0) await Future<void>.delayed(const Duration(seconds: 2));
          try {
            final current = await auth.currentToken();
            if (current == null) break;
            credited = await api.isAdmobRewardCredited(
              bearer: current,
              sessionId: session!,
            );
          } catch (_) {}
          if (credited) {
            await c.refresh();
            break;
          }
        }
        if (mounted) {
          setState(
            () => _message = credited
                ? 'Question ajoutée. Progression mise à jour.'
                : 'Validation serveur en cours.',
          );
        }
      },
    );
    if (mounted) {
      setState(() {
        _busy = false;
        if (!shown && _message == null) {
          _message = 'Publicité indisponible pour le moment.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final premium =
        ConsultationScope.maybeReadOf(context)?.quota?.isPremium == true;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: c == null
              ? const Center(
                  child: Text(
                    'Consultation gratuite indisponible pour le moment.',
                  ),
                )
              : ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back),
                          ),
                        ),
                        Text(
                          'Consultation gratuite',
                          style: AuryelText.display(
                            fontSize: 25,
                            color: AuryelColors.textCream,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Regardez une publicité pour poser une question à votre conseiller.',
                          style: AuryelText.body(
                            color: AuryelColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Metric(
                          label: 'Questions disponibles',
                          value: '${c.questionsAvailable}',
                          key: const Key('free-questions-available'),
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Progression',
                          value: '${c.rewardedProgress}/10 pubs vers +5 min',
                          key: const Key('rewarded-progress'),
                        ),
                        const SizedBox(height: 22),
                        if (!premium) ...[
                          ElevatedButton(
                            key: const Key('watch-rewarded-ad'),
                            onPressed:
                                AuryelAds.instance.rewardedReady && !_busy
                                ? _watch
                                : null,
                            child: Text(rewardedAdCtaLabel(loading: _busy)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '1 pub = 1 question',
                            textAlign: TextAlign.center,
                            style: AuryelText.body(
                              color: AuryelColors.textSecondary,
                            ),
                          ),
                          Text(
                            '10 pubs = +5 min',
                            textAlign: TextAlign.center,
                            style: AuryelText.body(
                              color: AuryelColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Une question comprend votre message et la réponse complète de votre conseiller.',
                            textAlign: TextAlign.center,
                            style: AuryelText.body(
                              fontSize: 12,
                              color: AuryelColors.textSecondary,
                            ),
                          ),
                        ] else
                          Text(
                            'Premium bénéficie déjà de consultations sans publicité.',
                            textAlign: TextAlign.center,
                            style: AuryelText.body(
                              color: AuryelColors.textSecondary,
                            ),
                          ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: AuryelText.body(
                              color: AuryelColors.goldLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AuryelColors.surface.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AuryelColors.warmBorder),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AuryelText.body(color: AuryelColors.textSecondary)),
        Text(
          value,
          style: AuryelText.body(
            fontWeight: FontWeight.w700,
            color: AuryelColors.goldLight,
          ),
        ),
      ],
    ),
  );
}

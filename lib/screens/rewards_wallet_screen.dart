import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../ads/ad_service.dart';
import '../api/rewards_api.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';
import 'daily_challenge_screen.dart';
import 'premium_screen.dart';
import 'tirage_screen.dart';

/// Libellés d'affichage des règles Étoiles — le SERVEUR décide QUELLES règles
/// sont actives et COMBIEN elles rapportent (`RewardRule.starsAmount`) ; ce
/// mapping ne fait QUE traduire un `rule_key` technique en copy FR, jamais un
/// montant. Une clé future encore inconnue de l'app (nouvelle règle ajoutée
/// côté serveur sans nouvelle version mobile) retombe sur un libellé neutre
/// dérivé de la clé plutôt que de planter ou de rester muette.
const Map<String, String> _kRuleLabels = {
  'wake_completed': 'Réveil Auryel',
  'daily_card_completed': 'Carte du jour',
  'tarot_completed': 'Tirage',
  'meditation_completed': 'Méditation',
  'share_completed': 'Partager Auryel',
  'streak_7_days': '7 jours consécutifs',
  'mini_game_completed': 'Mini-jeu du jour',
};

String _ruleLabel(String ruleKey) =>
    _kRuleLabels[ruleKey] ?? ruleKey.replaceAll('_', ' ');

/// CORRECTIF PRODUIT — description courte de CE QUE fait l'action (jamais un
/// montant : `stars_amount` reste exclusivement lu depuis `RewardRule`).
/// Même idiome que `_kRuleLabels` : une clé future inconnue de l'app retombe
/// sur une chaîne vide plutôt que de planter.
const Map<String, String> _kRuleDescriptions = {
  'wake_completed': 'Éteins ton réveil Auryel.',
  'daily_card_completed': 'Consulte ta carte du jour.',
  'tarot_completed': 'Fais ton tirage à 3 cartes.',
  'meditation_completed': 'Termine un Moment (méditation).',
  'share_completed': 'Partage Auryel avec tes proches.',
  'mini_game_completed': 'Termine une partie d’un mini-jeu.',
};

String? _ruleDescription(String ruleKey) => _kRuleDescriptions[ruleKey];

/// Limite quotidienne en toutes lettres, dérivée UNIQUEMENT de
/// `RewardRule.dailyLimit` (valeur serveur réelle) — `null` = pas de texte,
/// jamais une limite devinée.
String? _ruleLimitLabel(int? dailyLimit) {
  if (dailyLimit == null) return null;
  if (dailyLimit <= 1) return 'Une fois par jour';
  return 'Jusqu’à $dailyLimit fois par jour';
}

/// GROS CHANTIER AURYEL (Prompt 3/5) — libellés des produits « temps contre
/// Étoiles ». Coût/durée eux-mêmes JAMAIS codés en dur (résolus depuis
/// `ExpressProduct`) ; seul le TITRE est une copy locale.
const Map<String, String> _kExpressProductLabels = {
  'express_consultation_10min': 'Consultation express',
};

String _expressProductLabel(String productKey) =>
    _kExpressProductLabels[productKey] ?? productKey.replaceAll('_', ' ');

/// « Mes Étoiles » — GROS CHANTIER AURYEL (Prompt 2/5 & 3/5). Le SERVEUR est
/// l'unique autorité : cet écran n'AFFICHE que `GET /api/app/rewards/wallet`
/// et ne dépense qu'au travers de `purchase_express_consultation` (Prompt
/// 3/5) — jamais de montant/coût/durée choisi côté client.
class RewardsWalletScreen extends StatefulWidget {
  const RewardsWalletScreen({super.key, this.controller});

  /// Injecté en test. En production, l'écran construit son propre contrôleur
  /// à partir de `AuthScope.of(context).rewardsApi`.
  final RewardsController? controller;

  @override
  State<RewardsWalletScreen> createState() => _RewardsWalletScreenState();
}

class _RewardsWalletScreenState extends State<RewardsWalletScreen>
    with WidgetsBindingObserver {
  RewardsController? _controller;
  bool _ownsController = false;
  bool _firstFeedbackDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    if (widget.controller != null) {
      _controller = widget.controller;
    } else {
      // Priorité à l'instance PARTAGÉE (câblée dans main(), écoutée aussi par
      // le header Accueil via RewardsScope) : les deux affichent TOUJOURS le
      // même solde. Repli sur un contrôleur local UNIQUEMENT si aucun scope
      // n'est câblé (tests isolés qui ne montent que cet écran).
      final shared = RewardsScope.maybeOf(context);
      if (shared != null) {
        _controller = shared;
      } else {
        final auth = AuthScope.maybeOf(context);
        final api = auth?.rewardsApi;
        if (auth == null || api == null) return; // écran d'erreur contrôlé
        _controller = RewardsController(
          api: api,
          tokenProvider: auth.currentToken,
        );
        _ownsController = true;
      }
    }
    _controller!.addListener(_onControllerChange);
    _controller!.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller?.refresh();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
    if (_controller?.takeFirstStarFeedback() == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstStarFeedback();
      });
    }
  }

  Future<void> _showFirstStarFeedback() async {
    if (!mounted || _firstFeedbackDialogOpen) return;
    _firstFeedbackDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⭐ Première Étoile gagnée !'),
        content: const Text(
          'Continue tes missions pour débloquer du temps avec ton conseiller.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Voir mes Étoiles'),
          ),
        ],
      ),
    );
    _firstFeedbackDialogOpen = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChange);
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$d/$m à $h:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: c == null
              ? _errorState(context)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BackHeader(),
                      const SizedBox(height: 8),
                      if (ConsultationScope.maybeReadOf(context)
                              ?.quota
                              ?.isPremium ==
                          false) ...[
                        _RewardedAdCard(controller: c),
                        const SizedBox(height: 14),
                      ],
                      _BalanceBlock(controller: c),
                      const SizedBox(height: 14),
                      _NextTierBlock(controller: c),
                      const SizedBox(height: 18),
                      Text(
                        'Tes Étoiles récompensent tes activités dans Auryel.',
                        style: AuryelText.body(
                          fontSize: 13,
                          color: AuryelColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _RulesSection(controller: c),
                      const SizedBox(height: 16),
                      _SpendSection(controller: c),
                      const SizedBox(height: 14),
                      _MonthlyConversionCap(controller: c),
                      if (ConsultationScope.maybeReadOf(context)
                              ?.quota
                              ?.isPremium !=
                          true) ...[
                        const SizedBox(height: 16),
                        const _PremiumReminder(),
                      ],
                      const SizedBox(height: 16),
                      _HistorySection(controller: c, formatDate: _formatDate),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Mes Étoiles indisponible pour le moment.',
          textAlign: TextAlign.center,
          style: AuryelText.body(color: AuryelColors.textSecondary),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Retour'),
        ),
      ],
    ),
  );
}

class _BackHeader extends StatelessWidget {
  const _BackHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const PhosphorIcon(
            PhosphorIconsRegular.arrowLeft,
            size: 20,
            color: AuryelColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _BalanceBlock extends StatelessWidget {
  const _BalanceBlock({required this.controller});

  final RewardsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // CORRECTIF — `controller.loading` redevient `false` dès qu'un 1er
        // `refresh()` ÉCHOUE (ex. backend indisponible), alors que le wallet
        // n'a JAMAIS été chargé : se fier à `loading` seul affichait alors un
        // faux « 0 » (repli silencieux de `starsBalance`). On se fie à
        // `controller.wallet == null` — même principe que la pilule Accueil
        // (`_StarsPill`) : jamais un solde inventé tant que le serveur n'a
        // pas répondu au moins une fois avec succès.
        final hasWallet = controller.wallet != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mes Étoiles',
              style: AuryelText.display(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('⭐', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 10),
                Text(
                  hasWallet ? '${controller.starsBalance}' : '…',
                  key: const Key('rewards-wallet-balance'),
                  style: AuryelText.display(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AuryelColors.goldLight,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _NextTierBlock extends StatelessWidget {
  const _NextTierBlock({required this.controller});

  final RewardsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final products = [...controller.expressProducts]
          ..sort((a, b) => a.starsCost.compareTo(b.starsCost));
        if (products.isEmpty || controller.wallet == null) {
          return const SizedBox.shrink();
        }
        final balance = controller.starsBalance;
        final available = products
            .where((p) => p.starsCost <= balance)
            .toList();
        final higher = products.where((p) => p.starsCost > balance).toList();
        final next = higher.isEmpty ? null : higher.first;
        if (next == null && available.isEmpty) return const SizedBox.shrink();
        if (next == null) {
          final product = available.last;
          return _WalletInsight(
            title: '${_minutes(product)} min disponibles',
            subtitle: 'Tu peux débloquer du temps avec tes Étoiles.',
          );
        }
        final missing = next.starsCost - balance;
        final title = available.isNotEmpty
            ? '${_minutes(available.last)} min disponibles\nPlus que $missing ⭐ pour atteindre ${_minutes(next)} min'
            : 'Plus que $missing ⭐ pour débloquer ${_minutes(next)} min';
        return _WalletInsight(
          title: title,
          subtitle: 'Prochain palier disponible depuis les offres serveur.',
        );
      },
    );
  }

  static int _minutes(ExpressProduct product) =>
      (product.secondsGranted / 60).round();
}

class _WalletInsight extends StatelessWidget {
  const _WalletInsight({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AuryelColors.gold.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PhosphorIcon(
          PhosphorIconsRegular.sparkle,
          color: AuryelColors.goldLight,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AuryelText.body(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: AuryelText.body(
                  fontSize: 11,
                  color: AuryelColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MonthlyConversionCap extends StatelessWidget {
  const _MonthlyConversionCap({required this.controller});

  final RewardsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.wallet == null) return const SizedBox.shrink();
        final limit = controller.monthlyMinutesLimit;
        final used = controller.minutesConvertedThisMonth;
        final remaining = controller.monthlyMinutesRemaining;
        final reached = remaining <= 0;
        return Container(
          key: const Key('monthly-stars-conversion-cap'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AuryelColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AuryelColors.warmBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Jusqu’à $limit min de consultation par mois',
                style: AuryelText.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                reached
                    ? 'Limite mensuelle atteinte'
                    : '$used / $limit min débloquées ce mois · Encore $remaining min disponibles',
                style: AuryelText.body(
                  fontSize: 11.5,
                  color: reached
                      ? AuryelColors.goldLight
                      : AuryelColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (used / limit).clamp(0.0, 1.0).toDouble(),
                  minHeight: 6,
                  backgroundColor: AuryelColors.warmBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AuryelColors.gold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PremiumReminder extends StatelessWidget {
  const _PremiumReminder();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AuryelColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AuryelColors.warmBorder),
    ),
    child: Row(
      children: [
        const PhosphorIcon(
          PhosphorIconsRegular.crown,
          color: AuryelColors.goldLight,
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Auryel Premium',
                style: AuryelText.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.textCream,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '4 h/mois  ·  4,99 €/mois  ·  Sans publicité',
                style: AuryelText.body(
                  fontSize: 12,
                  color: AuryelColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
          child: const Text('Découvrir'),
        ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final PhosphorIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                PhosphorIcon(icon!, size: 15, color: AuryelColors.gold),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: AuryelText.body(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Une source de gain : nom + montant réel (serveur) en tête, description
/// courte + limite quotidienne réelle en dessous. Structure demandée pour
/// que « Comment gagner des Étoiles » soit enfin compréhensible d'un coup
/// d'œil (nom / récompense / description / limite éventuelle).
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule, this.onTap});

  final RewardRule rule;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final description = _ruleDescription(rule.ruleKey);
    final limit = _ruleLimitLabel(rule.dailyLimit);
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuryelColors.backgroundDeep.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _ruleLabel(rule.ruleKey),
                  style: AuryelText.body(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
              ),
              Text(
                '+${rule.starsAmount} ⭐',
                style: AuryelText.body(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.goldLight,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: AuryelText.body(
                fontSize: 12,
                color: AuryelColors.textSecondary,
              ),
            ),
          ],
          if (limit != null) ...[
            const SizedBox(height: 3),
            Text(
              limit,
              style: AuryelText.body(
                fontSize: 10.5,
                color: AuryelColors.textMuted,
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onTap, child: const Text('Ouvrir')),
            ),
          ],
        ],
      ),
    );
    return onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: content,
          );
  }
}

class _RulesSection extends StatelessWidget {
  const _RulesSection({required this.controller});

  final RewardsController controller;

  void _openActivity(BuildContext context, String ruleKey) {
    final Widget? destination = switch (ruleKey) {
      'mini_game_completed' => const DailyChallengeScreen(),
      'tarot_completed' => const TirageScreen(),
      'share_completed' => null,
      'wake_completed' => null,
      _ => null,
    };
    if (destination != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => destination));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // UNIQUEMENT les règles V4 actives renvoyées par le serveur.
        final rules = controller.rules
            .where(
              (r) =>
                  r.ruleKey == 'mini_game_completed' ||
                  r.ruleKey == 'tarot_completed' ||
                  r.ruleKey == 'wake_completed' ||
                  r.ruleKey == 'share_completed',
            )
            .toList(growable: false);
        return _SectionCard(
          title: 'Comment gagner des Étoiles',
          icon: PhosphorIconsRegular.sparkle,
          child: rules.isEmpty
              ? Text(
                  controller.loading ? 'Chargement…' : 'Aucune règle active.',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    color: AuryelColors.textMuted,
                  ),
                )
              : Column(
                  children: [
                    for (final rule in rules) ...[
                      _RuleRow(
                        rule: rule,
                        onTap: switch (rule.ruleKey) {
                          'tarot_completed' || 'mini_game_completed' =>
                            () => _openActivity(context, rule.ruleKey),
                          _ => null,
                        },
                      ),
                      if (rule != rules.last) const SizedBox(height: 12),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _RewardedAdCard extends StatefulWidget {
  const _RewardedAdCard({required this.controller});

  final RewardsController controller;

  @override
  State<_RewardedAdCard> createState() => _RewardedAdCardState();
}

class _RewardedAdCardState extends State<_RewardedAdCard> {
  bool _busy = false;
  String? _message;

  Future<void> _watch() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final auth = AuthScope.maybeOf(context);
    final account = auth?.account;
    final api = auth?.rewardsApi;
    final token = auth == null ? null : await auth.currentToken();
    String? sessionId;
    try {
      sessionId = auth == null || api == null || token == null
          ? null
          : await api.createAdmobRewardSession(token);
    } catch (_) {
      sessionId = null;
    }
    if (!mounted ||
        sessionId == null ||
        account == null ||
        auth == null ||
        api == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Validation publicitaire indisponible pour le moment.';
        });
      }
      return;
    }
    final verifiedSessionId = sessionId;
    final shown = await AuryelAds.instance.showRewarded(
      ssvOptions: rewardedSsvOptions(
        userId: account.userId,
        customData: verifiedSessionId,
      ),
      onReward: () async {
        var credited = false;
        for (var attempt = 0; attempt < 8 && mounted; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          final currentToken = await auth.currentToken();
          if (currentToken == null) break;
          try {
            credited = await api.isAdmobRewardCredited(
              bearer: currentToken,
              sessionId: verifiedSessionId,
            );
          } catch (_) {
            credited = false;
          }
          if (credited) {
            await widget.controller.refresh();
            break;
          }
        }
        if (mounted) {
          setState(() {
            _message = credited
                ? '+12 Étoiles reçues'
                : 'Validation de vos 12 Étoiles en cours.';
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!shown && _message == null) {
        _message = 'Annonce indisponible pour le moment.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = AuryelAds.instance.rewardedReady;
    return Container(
      key: const Key('rewarded-ad-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AuryelColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Regarde une publicité et augmente ton temps de consultation',
            style: AuryelText.body(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Chaque publicité terminée te rapporte +12 Étoiles. Cumule tes Étoiles et échange-les contre du temps avec ton conseiller.',
            style: AuryelText.body(
              fontSize: 12,
              color: AuryelColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('watch-rewarded-ad'),
            onPressed: ready && !_busy ? _watch : null,
            child: Text(
              _busy ? 'Chargement…' : 'Regarder une publicité · +6 ⭐',
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 6),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 11,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// GROS CHANTIER AURYEL (Prompt 3/5) — « UTILISER MES ÉTOILES » : dépenser
/// des Étoiles contre du temps de consultation. Coût/durée TOUJOURS résolus
/// serveur (`ExpressProduct`, depuis le MÊME wallet que le reste de l'écran)
/// — jamais un montant choisi côté client. Pas d'achat accidentel en un seul
/// tap : le tap ouvre une confirmation, jamais un achat direct.
class _SpendSection extends StatelessWidget {
  const _SpendSection({required this.controller});

  final RewardsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final products = controller.expressProducts;
        if (products.isEmpty) return const SizedBox.shrink();
        final balance = controller.starsBalance;
        return _SectionCard(
          title: 'Utiliser mes Étoiles',
          icon: PhosphorIconsRegular.sparkle,
          child: Column(
            children: [
              for (final product in products) ...[
                _ExpressProductCard(
                  product: product,
                  starsBalance: balance,
                  monthlyMinutesRemaining: controller.monthlyMinutesRemaining,
                  onUnlock: () =>
                      _showExpressConfirmSheet(context, controller, product),
                ),
                if (product != products.last) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ExpressProductCard extends StatelessWidget {
  const _ExpressProductCard({
    required this.product,
    required this.starsBalance,
    required this.monthlyMinutesRemaining,
    required this.onUnlock,
  });

  final ExpressProduct product;
  final int starsBalance;
  final int monthlyMinutesRemaining;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final minutes = (product.secondsGranted / 60).round();
    final canAfford = starsBalance >= product.starsCost;
    final fitsMonthlyCap = minutes <= monthlyMinutesRemaining;
    final missing = product.starsCost - starsBalance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AuryelColors.backgroundDeep.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _expressProductLabel(product.productKey),
            style: AuryelText.body(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$minutes min de consultation',
            style: AuryelText.body(fontSize: 12, color: AuryelColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${product.starsCost} ⭐',
                style: AuryelText.display(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.goldLight,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: canAfford && fitsMonthlyCap ? onUnlock : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AuryelColors.gold,
                  foregroundColor: AuryelColors.backgroundDeep,
                  disabledBackgroundColor: AuryelColors.warmBorder,
                  disabledForegroundColor: AuryelColors.textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'Débloquer $minutes min',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (!canAfford) ...[
            const SizedBox(height: 6),
            Text(
              'Il te manque $missing ⭐',
              style: AuryelText.body(
                fontSize: 11.5,
                color: AuryelColors.textMuted,
              ),
            ),
          ],
          if (canAfford && !fitsMonthlyCap) ...[
            const SizedBox(height: 6),
            Text(
              monthlyMinutesRemaining <= 0
                  ? 'Limite mensuelle atteinte'
                  : 'Il te reste $monthlyMinutesRemaining min convertibles ce mois.',
              style: AuryelText.body(
                fontSize: 11.5,
                color: AuryelColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet de confirmation — jamais un achat en un seul tap. Affiche le
/// solde actuel et le solde APRÈS achat, tous deux calculés depuis les
/// valeurs serveur déjà connues (jamais recalculées ni devinées ailleurs).
Future<void> _showExpressConfirmSheet(
  BuildContext pageContext,
  RewardsController controller,
  ExpressProduct product,
) async {
  final minutes = (product.secondsGranted / 60).round();
  final startingBalance = controller.starsBalance;
  String? idempotencyKey;

  // Résultat récupéré PENDANT que la sheet est encore montée (pour
  // `Navigator.pop`), puis traité APRÈS sa fermeture avec `pageContext` —
  // jamais le contexte de la sheet une fois celle-ci fermée (unmounted).
  ExpressConsultationResult? outcome;
  var busy = false;
  String? error;

  await showModalBottomSheet<void>(
    context: pageContext,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> confirm() async {
          setState(() => busy = true);
          idempotencyKey ??= generateIdempotencyKey('express');
          final result = await controller.purchaseExpressConsultation(
            productKey: product.productKey,
            idempotencyKey: idempotencyKey!,
          );
          if (!context.mounted) return;
          if (result == null) {
            setState(() {
              busy = false;
              error = 'Connexion impossible — réessaie.';
            });
            return;
          }
          if (result.success) {
            outcome = result;
            Navigator.of(sheetContext).pop();
            return;
          }
          setState(() {
            busy = false;
            error = result.isInsufficientBalance
                ? 'Solde insuffisant.'
                : result.isMonthlyLimitReached
                ? 'La limite de 30 minutes par mois est atteinte.'
                : 'Débloquer ce temps n’a pas fonctionné — réessaie plus tard.';
          });
        }

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            decoration: const BoxDecoration(
              color: AuryelColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Débloquer $minutes minutes de consultation pour '
                  '${product.starsCost} ⭐ ?',
                  textAlign: TextAlign.center,
                  style: AuryelText.display(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 18),
                _ConfirmBalanceRow(
                  label: 'Solde actuel',
                  value: '$startingBalance ⭐',
                ),
                const SizedBox(height: 6),
                _ConfirmBalanceRow(
                  label: 'Solde après achat',
                  value: '${startingBalance - product.starsCost} ⭐',
                  emphasize: true,
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 12.5,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: busy ? null : confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AuryelColors.gold,
                    foregroundColor: AuryelColors.backgroundDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmer'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(sheetContext).pop(),
                  child: Text(
                    'Annuler',
                    style: AuryelText.body(color: AuryelColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  // La sheet est fermée ICI : on retombe sur `pageContext` (celui de l'écran
  // appelant), jamais le contexte de la sheet (unmounted dès sa fermeture).
  final result = outcome;
  if (result == null || !pageContext.mounted) return;
  ConsultationScope.maybeReadOf(pageContext)?.refresh();
  _showExpressSuccessDialog(pageContext, minutes, result.starsBalance);
}

class _ConfirmBalanceRow extends StatelessWidget {
  const _ConfirmBalanceRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AuryelText.body(
            fontSize: 13,
            color: AuryelColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AuryelText.body(
            fontSize: 13,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            color: emphasize ? AuryelColors.goldLight : AuryelColors.textCream,
          ),
        ),
      ],
    );
  }
}

/// Feedback bref après succès — pas de modal envahissante, pas de confettis.
void _showExpressSuccessDialog(
  BuildContext context,
  int minutes,
  int newBalance,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AuryelColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        '+$minutes min de consultation',
        style: AuryelText.display(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AuryelColors.textCream,
        ),
      ),
      content: Text(
        'Nouveau solde : $newBalance ⭐',
        style: AuryelText.body(color: AuryelColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'Fermer',
            style: AuryelText.body(color: AuryelColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            // Retour à l'écran précédent (Accueil/Dashboard), où le CTA de
            // consultation habituel reflète déjà le nouveau temps disponible
            // — aucun flux de conseiller parallèle recréé ici.
            Navigator.of(context).maybePop();
          },
          child: const Text('Parler à mon conseiller'),
        ),
      ],
    ),
  );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.controller, required this.formatDate});

  final RewardsController controller;
  final String Function(DateTime?) formatDate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tx = controller.recentTransactions;
        return _SectionCard(
          title: 'Historique récent',
          icon: PhosphorIconsRegular.clockCounterClockwise,
          child: tx.isEmpty
              ? Text(
                  controller.loading
                      ? 'Chargement…'
                      : 'Aucun mouvement pour le moment.',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    color: AuryelColors.textMuted,
                  ),
                )
              : Column(
                  children: [
                    for (final t in tx)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _ruleLabel(t.reason),
                                style: AuryelText.body(
                                  fontSize: 12.5,
                                  color: AuryelColors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              formatDate(t.createdAt),
                              style: AuryelText.body(
                                fontSize: 11,
                                color: AuryelColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${t.deltaStars > 0 ? '+' : ''}'
                              '${t.deltaStars} ⭐',
                              style: AuryelText.body(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: t.deltaStars >= 0
                                    ? AuryelColors.goldLight
                                    : AuryelColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

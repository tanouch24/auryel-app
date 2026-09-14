import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/auth_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';

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
};

String _ruleLabel(String ruleKey) =>
    _kRuleLabels[ruleKey] ?? ruleKey.replaceAll('_', ' ');

/// « Mes Étoiles » — GROS CHANTIER AURYEL (Prompt 2/5). Le SERVEUR est
/// l'unique autorité : cet écran n'AFFICHE que `GET /api/app/rewards/wallet`.
/// Acquisition uniquement dans ce lot — pas de bouton de dépense (Prompt 3/5).
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
    if (mounted) setState(() {});
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
                      _BalanceBlock(controller: c),
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
                      _StreakSection(controller: c),
                      const SizedBox(height: 16),
                      _HistorySection(
                        controller: c,
                        formatDate: _formatDate,
                      ),
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
        final loading = controller.loading;
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
                  loading ? '…' : '${controller.starsBalance}',
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

class _RulesSection extends StatelessWidget {
  const _RulesSection({required this.controller});

  final RewardsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // UNIQUEMENT les règles ACTIVES renvoyées par le serveur — une action
        // future désactivée (mini-jeux, AdMob) n'apparaît jamais ici.
        final rules = controller.rules
            .where((r) => r.ruleKey != 'streak_7_days')
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
                    for (final rule in rules)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _ruleLabel(rule.ruleKey),
                                style: AuryelText.body(
                                  fontSize: 13,
                                  color: AuryelColors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              '+${rule.starsAmount} ⭐',
                              style: AuryelText.body(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AuryelColors.goldLight,
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

class _StreakSection extends StatelessWidget {
  const _StreakSection({required this.controller});

  final RewardsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final streak = controller.streak;
        return _SectionCard(
          title: 'Série actuelle',
          icon: PhosphorIconsRegular.fire,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔥 ${streak.currentStreak} jour${streak.currentStreak > 1 ? 's' : ''}',
                style: AuryelText.body(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Encore ${streak.nextRewardInDays} jour'
                '${streak.nextRewardInDays > 1 ? 's' : ''} pour gagner +50 ⭐',
                style: AuryelText.body(
                  fontSize: 12.5,
                  color: AuryelColors.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.controller,
    required this.formatDate,
  });

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

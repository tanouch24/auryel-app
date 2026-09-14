import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/rewards_api.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
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
  'mini_game_completed': 'Mini-jeu du jour',
};

String _ruleLabel(String ruleKey) =>
    _kRuleLabels[ruleKey] ?? ruleKey.replaceAll('_', ' ');

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
                      _SpendSection(controller: c),
                      const SizedBox(height: 16),
                      _StreakSection(controller: c),
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
    required this.onUnlock,
  });

  final ExpressProduct product;
  final int starsBalance;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final minutes = (product.secondsGranted / 60).round();
    final canAfford = starsBalance >= product.starsCost;
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
                onPressed: canAfford ? onUnlock : null,
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

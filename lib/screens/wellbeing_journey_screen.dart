import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/wellbeing_api.dart';
import '../state/auth_controller.dart';
import '../state/wellbeing_controller.dart';
import '../theme/auryel_theme.dart';
import 'meditation_screen.dart';
import 'tirage_screen.dart';

/// « Mon parcours bien-être » — 4 missions quotidiennes, progression par cycle
/// de 30 journées COMPLÉTÉES (jours non consécutifs), récompense de 15 minutes
/// de consultation à la 30e journée d'un cycle.
///
/// Le SERVEUR est l'unique autorité : cet écran n'AFFICHE que
/// `GET /api/app/wellbeing/progress`. Wording bien-être / expérience
/// quotidienne uniquement — jamais médical.
class WellbeingJourneyScreen extends StatefulWidget {
  const WellbeingJourneyScreen({super.key, this.controller});

  /// Injecté en test. En production, l'écran construit son propre contrôleur à
  /// partir de `AuthScope.of(context).wellbeingApi`.
  final WellbeingController? controller;

  @override
  State<WellbeingJourneyScreen> createState() => _WellbeingJourneyScreenState();
}

class _WellbeingJourneyScreenState extends State<WellbeingJourneyScreen>
    with WidgetsBindingObserver {
  WellbeingController? _controller;
  bool _ownsController = false;
  bool _rewardDialogOpen = false;

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
      final auth = AuthScope.maybeOf(context);
      final api = auth?.wellbeingApi;
      if (auth == null || api == null) {
        return; // endpoint non câblé -> écran d'erreur contrôlé
      }
      _controller = WellbeingController(
        api: api,
        tokenProvider: auth.currentToken,
      );
      _ownsController = true;
    }
    _controller!.addListener(_onControllerChange);
    _controller!.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller?.refresh();
  }

  void _onControllerChange() {
    final cycle = _controller?.pendingRewardCycle;
    if (cycle != null && !_rewardDialogOpen && mounted) {
      _rewardDialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showRewardDialog(cycle),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _showRewardDialog(int cycle) async {
    final c = _controller;
    if (c == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Rayonnement atteint',
          style: AuryelText.display(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tu as complété 30 journées de ton parcours.',
              style: AuryelText.body(
                fontSize: 13.5,
                height: 1.5,
                color: AuryelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '15 minutes de consultation viennent d’être ajoutées à ton '
              'temps disponible.',
              style: AuryelText.body(
                fontSize: 13.5,
                height: 1.5,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Continuer',
              style: AuryelText.body(
                color: AuryelColors.goldLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    await c.acknowledgeReward(cycle);
    _rewardDialogOpen = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChange);
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  Future<void> _openTirage() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TirageScreen()));
    await _controller?.refresh();
  }

  Future<void> _openMoment() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MeditationScreen()));
    await _controller?.refresh();
  }

  void _backToApp() => Navigator.of(context).maybePop();

  void _onMissionCta(String id) {
    switch (id) {
      case 'tirage':
        _openTirage();
      case 'moment':
        _openMoment();
      case 'pensee':
      case 'consultation':
        _backToApp();
    }
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: c == null
                    ? _ErrorState(onRetry: () async {})
                    : _Body(
                        controller: c,
                        onRefresh: c.refresh,
                        onMissionCta: _onMissionCta,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 20, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Retour',
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              size: 20,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              'Mon parcours bien-être',
              style: AuryelText.display(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.onRefresh,
    required this.onMissionCta,
  });

  final WellbeingController controller;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onMissionCta;

  @override
  Widget build(BuildContext context) {
    final progress = controller.progress;

    if (controller.loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AuryelColors.gold,
          ),
        ),
      );
    }

    if (progress == null) {
      return _ErrorState(onRetry: onRefresh);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AuryelColors.gold,
      backgroundColor: AuryelColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          if (controller.error != null) _InlineError(onRetry: onRefresh),
          _CycleCard(progress: progress),
          const SizedBox(height: 14),
          _LevelRow(progress: progress),
          const SizedBox(height: 20),
          _MissionsSection(
            progress: progress,
            busy: controller.busy,
            onCta: onMissionCta,
          ),
          const SizedBox(height: 20),
          _GlobalProgress(progress: progress),
          const SizedBox(height: 16),
          _RewardInfo(progress: progress),
        ],
      ),
    );
  }
}

class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.progress});

  final WellbeingProgress progress;

  @override
  Widget build(BuildContext context) {
    final done = progress.cycleCompletedDays;
    final target = WellbeingProgress.cycleTarget;
    final ratio = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AuryelColors.surface.withValues(alpha: 0.55),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CYCLE ${progress.cycleNumber}',
                style: AuryelText.body(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.gold,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                '$done / $target',
                style: AuryelText.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.goldLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$done ${done <= 1 ? 'jour complété' : 'jours complétés'}',
            style: AuryelText.display(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          if (progress.currentLevel != null) ...[
            const SizedBox(height: 2),
            Text(
              'Niveau ${progress.currentLevel}',
              style: AuryelText.body(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AuryelColors.warmBorder,
              valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.progress});

  final WellbeingProgress progress;

  @override
  Widget build(BuildContext context) {
    final next = progress.nextLevel;
    final String line;
    if (next == null) {
      line = 'Tu as atteint le dernier niveau de ce cycle.';
    } else {
      final n = progress.daysToNextLevel;
      line = 'Plus que $n ${n <= 1 ? 'jour' : 'jours'} avant $next';
    }
    return Row(
      children: [
        const PhosphorIcon(
          PhosphorIconsRegular.mountains,
          size: 16,
          color: AuryelColors.goldLight,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line,
            style: AuryelText.body(
              fontSize: 13,
              color: AuryelColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _MissionsSection extends StatelessWidget {
  const _MissionsSection({
    required this.progress,
    required this.busy,
    required this.onCta,
  });

  final WellbeingProgress progress;
  final bool busy;
  final ValueChanged<String> onCta;

  static const Map<String, ({String name, String todo, String cta})> _labels = {
    'pensee': (
      name: 'Pensée du jour',
      todo: 'À découvrir',
      cta: 'Voir la pensée du jour',
    ),
    'tirage': (
      name: 'Carte du jour',
      todo: 'À découvrir',
      cta: 'Découvrir ma carte',
    ),
    'consultation': (
      name: 'Consultation',
      todo: 'À faire',
      cta: 'Ouvrir une consultation',
    ),
    'moment': (name: 'Moment', todo: 'À faire', cta: 'Prendre un moment'),
  };

  @override
  Widget build(BuildContext context) {
    final done = progress.today.missions.where((m) => m.completed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'MISSIONS DU JOUR',
              style: AuryelText.body(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.gold,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              '$done/4',
              style: AuryelText.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final id in kWellbeingMissions)
          _MissionRow(
            label: _labels[id]!,
            completed: progress.today.mission(id)?.completed ?? false,
            enabled: !busy,
            onCta: () => onCta(id),
          ),
        if (progress.today.completed) ...[
          const SizedBox(height: 8),
          Text(
            'Journée complétée. Elle compte dans ton parcours.',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
        ],
      ],
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.label,
    required this.completed,
    required this.enabled,
    required this.onCta,
  });

  final ({String name, String todo, String cta}) label;
  final bool completed;
  final bool enabled;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AuryelColors.surface.withValues(alpha: 0.5),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PhosphorIcon(
                completed
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsRegular.circle,
                size: 20,
                color: completed
                    ? AuryelColors.goldLight
                    : AuryelColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label.name,
                  style: AuryelText.body(
                    fontSize: 13.5,
                    fontWeight: completed ? FontWeight.w600 : FontWeight.w400,
                    color: completed
                        ? AuryelColors.goldLight
                        : AuryelColors.textCream,
                  ),
                ),
              ),
              Text(
                completed ? 'Terminée' : label.todo,
                style: AuryelText.body(
                  fontSize: 11,
                  color: completed
                      ? AuryelColors.goldLight
                      : AuryelColors.textMuted,
                ),
              ),
            ],
          ),
          if (!completed)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 32),
                child: TextButton(
                  onPressed: enabled ? onCta : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    label.cta,
                    style: AuryelText.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.goldLight,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlobalProgress extends StatelessWidget {
  const _GlobalProgress({required this.progress});

  final WellbeingProgress progress;

  @override
  Widget build(BuildContext context) {
    final total = progress.completedDaysTotal;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AuryelColors.surface.withValues(alpha: 0.4),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Row(
        children: [
          const PhosphorIcon(
            PhosphorIconsRegular.path,
            size: 16,
            color: AuryelColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              total <= 1
                  ? '$total journée complétée depuis le début de ton parcours'
                  : '$total journées complétées depuis le début de ton parcours',
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardInfo extends StatelessWidget {
  const _RewardInfo({required this.progress});

  final WellbeingProgress progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AuryelColors.gold.withValues(alpha: 0.16),
            AuryelColors.gold.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(
          color: AuryelColors.goldLight.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsFill.gift,
                size: 15,
                color: AuryelColors.goldLight,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Complète 30 journées de ton parcours et gagne 15 minutes '
                  'de consultation.',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.goldLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Chaque journée complétée compte, même si tu fais une pause entre '
            'deux.',
            style: AuryelText.body(
              fontSize: 11.5,
              height: 1.4,
              color: AuryelColors.textMuted,
            ),
          ),
          if (progress.rewardEarnedForCurrentCycle) ...[
            const SizedBox(height: 8),
            Text(
              'Récompense du cycle ${progress.cycleNumber} déjà ajoutée à ton '
              'temps disponible.',
              style: AuryelText.body(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AuryelColors.surface.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mise à jour indisponible pour le moment.',
              style: AuryelText.body(
                fontSize: 12,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => onRetry(),
            child: Text(
              'Réessayer',
              style: AuryelText.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(
              PhosphorIconsThin.path,
              size: 42,
              color: AuryelColors.goldLight,
            ),
            const SizedBox(height: 14),
            Text(
              'Ton parcours n’a pas pu être chargé.',
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 14,
                color: AuryelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => onRetry(),
              child: Text(
                'Réessayer',
                style: AuryelText.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.goldLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

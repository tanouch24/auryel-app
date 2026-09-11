import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/auth_controller.dart';
import '../state/wellbeing_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/wellbeing_journey_map.dart';
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
      // AUDIT ACCUEIL/PARCOURS — priorité à l'instance PARTAGÉE (créée dans
      // main() et fournie via WellbeingScope) : c'est elle qu'Accueil écoute
      // aussi, donc les deux affichent TOUJOURS le même état, sans jamais
      // fermer/rouvrir l'app. Repli sur un contrôleur local UNIQUEMENT si
      // aucun scope n'est présent (tests isolés / hôtes hérités qui ne
      // câblent pas WellbeingScope).
      final shared = WellbeingScope.maybeOf(context);
      if (shared != null) {
        _controller = shared;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: _InlineError(onRetry: onRefresh),
          ),
        Expanded(
          child: WellbeingJourneyMap(
            progress: progress,
            busy: controller.busy,
            onMissionCta: onMissionCta,
            onRefresh: onRefresh,
          ),
        ),
      ],
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

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/content_repository.dart';
import '../data/daily_like_store.dart';
import '../data/daily_mission_tracker.dart';
import '../data/daily_share_tracker.dart';
import '../data/daily_thought.dart';
import '../screens/splash_screen.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart'
    show AdvisorInfo, advisorByName, advisorByGuideKey;
import '../widgets/auryel_wordmark.dart';
import '../widgets/consultation_block.dart' show ConsultationState;
import '../widgets/daily_message_sheet.dart';
import '../widgets/main_nav_scope.dart';
import 'dashboard_screen.dart';
import 'premium_screen.dart';
import 'tirage_jeu_screen.dart';

/// Reset DEBUG uniquement (geste caché — appui long sur l'icône profil,
/// visible seulement en `kDebugMode`).
Future<void> _debugResetOnboarding(BuildContext context) async {
  await AuryelStateScope.of(context).debugReset();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const SplashScreen()),
    (route) => false,
  );
}

/// Accueil « MON AURYEL AUJOURD'HUI » — comprendre sa journée en un coup d'œil,
/// avec le moins de scroll possible sur ~384 dp.
///
/// Ordre : AURYEL / accès Dashboard -> PENSÉE DU JOUR -> TES MISSIONS DU JOUR
/// -> TEMPS DISPONIBLE -> barre de navigation.
///
/// Les conseillers ne sont PLUS présentés ici (ni carrousel, ni « Changer de
/// conseiller ») : ils reviendront dans l'onglet central CONSULTATION (lot
/// suivant). Les données/assets/logique conseillers restent intacts.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.thoughtRepository});

  /// Injecté par les tests ; en production la source est le pack local
  /// `assets/pensees/`.
  final DailyThoughtRepository? thoughtRepository;

  @override
  Widget build(BuildContext context) {
    final state = AuryelStateScope.of(context);
    // Défensif : après un changement de compte / une connexion sur un nouvel
    // appareil, le profil local peut être absent (pas encore de récupération
    // serveur au login). `advisorByName('')` retombe alors sur le conseiller
    // par défaut (Séléna = `guide=selena` côté backend) au lieu de crasher.
    final advisor = advisorByName(state.selectedAdvisor ?? '');
    final consultation = ConsultationScope.maybeReadOf(context);
    final haloSize = math.min(360.0, MediaQuery.sizeOf(context).width);

    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 140,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: haloSize,
                  height: haloSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AuryelColors.gold.withValues(alpha: 0.16),
                        AuryelColors.gold.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
                child: Column(
                  children: [
                    const AuryelWordmark().animate().fadeIn(duration: 500.ms),
                    const SizedBox(height: 6),
                    Text(
                      'ESPACE PRIVÉ',
                      textAlign: TextAlign.center,
                      style: AuryelText.body(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: AuryelColors.textMuted,
                        letterSpacing: 2.4,
                      ),
                    ).animate().fadeIn(delay: 120.ms, duration: 500.ms),
                    const SizedBox(height: 16),
                    const _Ornament().animate().fadeIn(
                      delay: 200.ms,
                      duration: 500.ms,
                    ),
                    const SizedBox(height: 14),

                    // 1 — PENSÉE DU JOUR (lot inchangé).
                    _DailyThoughtZone(repository: thoughtRepository)
                        .animate()
                        .fadeIn(delay: 380.ms, duration: 500.ms),

                    const SizedBox(height: 16),
                    _Divider(),
                    const SizedBox(height: 12),

                    // 2 — TES MISSIONS DU JOUR.
                    _MissionsSection(repository: thoughtRepository)
                        .animate()
                        .fadeIn(delay: 480.ms, duration: 500.ms),

                    const SizedBox(height: 14),
                    _Divider(),
                    const SizedBox(height: 12),

                    // 3 — TEMPS DISPONIBLE (bloc compact).
                    (consultation == null
                            ? _TimeAvailableBlock(
                                consultation: null,
                                preferredAdvisor: advisor,
                              )
                            : ListenableBuilder(
                                listenable: consultation,
                                builder: (context, _) => _TimeAvailableBlock(
                                  consultation: consultation,
                                  preferredAdvisor: advisor,
                                ),
                              ))
                        .animate()
                        .fadeIn(delay: 560.ms, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onLongPress: kDebugMode
                        ? () => _debugResetOnboarding(context)
                        : null,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DashboardScreen(),
                        ),
                      ),
                      icon: PhosphorIcon(
                        PhosphorIconsThin.userCircle,
                        size: 22,
                        color: AuryelColors.textMuted,
                      ),
                      splashRadius: 20,
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 20,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.4),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
        Container(
          width: 20,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color: AuryelColors.warmBorder.withValues(alpha: 0.6),
  );
}

// ===========================================================================
// 1 — PENSÉE DU JOUR  (comportement inchangé — spacings légèrement compactés)
// ===========================================================================

class _DailyThoughtZone extends StatefulWidget {
  const _DailyThoughtZone({this.repository});

  final DailyThoughtRepository? repository;

  @override
  State<_DailyThoughtZone> createState() => _DailyThoughtZoneState();
}

class _DailyThoughtZoneState extends State<_DailyThoughtZone>
    with WidgetsBindingObserver {
  late final DailyThoughtRepository _repo =
      widget.repository ?? DailyThoughtRepository();
  final DailyShareTracker _tracker = DailyShareTracker();

  /// Source distante (serveur -> cache -> embarqué). `null` = pas de
  /// [ContentScope] dans l'arbre (tests hérités) -> on lit [_repo] embarqué.
  ContentRepository? _content;
  bool _bootstrapped = false;

  DailyThought? _thought;
  DateTime? _loadedDay;
  int _sharedDays = 0;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= ContentScope.maybeOf(context);
    if (!_bootstrapped) {
      _bootstrapped = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<DailyThought> _loadThought() => _content != null
      ? _content!.thoughtFor(DateTime.now())
      : _repo.thoughtFor(DateTime.now());

  Future<void> _refresh() async {
    if (_thought != null && _loadedDay == _today) {
      await _loadCounter();
      return;
    }
    try {
      final t = await _loadThought();
      if (!mounted) return;
      setState(() {
        _thought = t;
        _loadedDay = _today;
      });
    } catch (_) {
      /* garde la pensée précédente, jamais d'écran vide */
    }
    await _loadCounter();
  }

  Future<void> _loadCounter() async {
    try {
      final n = await _tracker.sharedDaysCount();
      if (mounted) setState(() => _sharedDays = n);
    } catch (_) {
      /* défaut : 0 */
    }
  }

  void _openPreview() {
    final t = _thought;
    if (t == null) return;
    showDailyThoughtSheet(
      context,
      thought: t,
      tracker: _tracker,
    ).then((_) => _loadCounter());
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedDay != null && _loadedDay != _today) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }

    final split = _thought?.splitAccent();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AuryelText.body(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              color: AuryelColors.textSecondary,
              height: 1.32,
            ),
            children: [
              if (split != null && split.lead.isNotEmpty)
                TextSpan(text: '${split.lead} '),
              TextSpan(
                text: split?.accent ?? '',
                style: AuryelText.body(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: AuryelColors.goldLight,
                  height: 1.32,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ShareRewardCta(onTap: _openPreview),
        const SizedBox(height: 4),
        _TapHereGuide(onTap: _openPreview),
        const SizedBox(height: 3),
        Text(
          '$_sharedDays / 30 jours',
          style: AuryelText.body(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 1),
        const _DailyLikeButton(),
      ],
    );
  }
}

/// Repère « Cliquez ici » + flèche vers le bouton de partage juste au-dessus.
/// Toute la zone déclenche le MÊME `onTap` (aucune logique de partage
/// dupliquée). Animation finie (3 bobs), désactivée si
/// `MediaQuery.disableAnimationsOf(context)`.
class _TapHereGuide extends StatelessWidget {
  const _TapHereGuide({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);

    Widget arrow = const PhosphorIcon(
      PhosphorIconsFill.arrowUp,
      size: 13,
      color: AuryelColors.goldLight,
    );
    if (animate) {
      arrow = arrow
          .animate(onPlay: (c) => c.repeat(reverse: true, count: 6))
          .moveY(begin: 0, end: -5, duration: 620.ms, curve: Curves.easeInOut);
    }

    Widget zone = Semantics(
      button: true,
      label: 'Cliquez ici pour partager',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                arrow,
                const SizedBox(width: 6),
                Text(
                  'Cliquez ici',
                  style: AuryelText.body(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.goldLight,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return animate ? zone.animate().fadeIn(duration: 260.ms) : zone;
  }
}

class _ShareRewardCta extends StatelessWidget {
  const _ShareRewardCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                AuryelColors.gold.withValues(alpha: 0.22),
                AuryelColors.gold.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(
              color: AuryelColors.goldLight.withValues(alpha: 0.70),
              width: 1.1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(
                PhosphorIconsFill.gift,
                size: 14,
                color: AuryelColors.goldLight,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Partage cette force avec tes contacts et gagne 1 h de '
                  'communication offerte.',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.goldLight,
                    letterSpacing: 0.1,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _DailyLikeButton extends StatefulWidget {
  const _DailyLikeButton();

  @override
  State<_DailyLikeButton> createState() => _DailyLikeButtonState();
}

class _DailyLikeButtonState extends State<_DailyLikeButton> {
  final DailyLikeStore _store = DailyLikeStore();
  bool _liked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _store.isLikedToday();
      if (mounted) setState(() => _liked = v);
    } catch (_) {
      /* défaut : non aimé */
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    setState(() => _liked = !_liked);
    try {
      final persisted = await _store.toggleToday();
      if (mounted && persisted != _liked) setState(() => _liked = persisted);
    } catch (_) {
      /* on garde l'état optimiste */
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _liked ? 'Retirer des favoris' : 'Ajouter aux favoris',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: PhosphorIcon(
              _liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
              size: 17,
              color: _liked ? AuryelColors.goldLight : AuryelColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 2 — TES MISSIONS DU JOUR
// ===========================================================================

enum _Mission { tirage, consultation, partage, moment }

class _MissionsSection extends StatefulWidget {
  const _MissionsSection({this.repository});

  final DailyThoughtRepository? repository;

  @override
  State<_MissionsSection> createState() => _MissionsSectionState();
}

class _MissionsSectionState extends State<_MissionsSection>
    with WidgetsBindingObserver {
  late final DailyThoughtRepository _repo =
      widget.repository ?? DailyThoughtRepository();
  final DailyShareTracker _shareTracker = DailyShareTracker();
  final DailyMissionTracker _missions = DailyMissionTracker();

  ContentRepository? _content;
  bool _bootstrapped = false;

  DailyThought? _thought;
  DateTime? _loadedDay;
  final Map<_Mission, bool> _done = {for (final m in _Mission.values) m: false};

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= ContentScope.maybeOf(context);
    if (!_bootstrapped) {
      _bootstrapped = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<DailyThought> _loadThought() => _content != null
      ? _content!.thoughtFor(DateTime.now())
      : _repo.thoughtFor(DateTime.now());

  Future<void> _refresh() async {
    // Consultation : une activité serveur RÉELLE (fenêtre de facturation en
    // cours ou session active) vaut « consulté aujourd'hui » et est persistée
    // localement pour la journée. Aucun crédit, aucune récompense.
    final c = ConsultationScope.maybeReadOf(context);
    if (c != null && (c.windowActive || c.hasActiveSession)) {
      await _missions.markDone(DailyMissionTracker.consultation);
    }

    try {
      if (_thought == null || _loadedDay != _today) {
        _thought = await _loadThought();
      }
    } catch (_) {
      /* la mission partage reste ouvrable via le CTA pensée */
    }

    final results = await Future.wait([
      _shareTracker.sharedToday(),
      _missions.isDone(DailyMissionTracker.tirage),
      _missions.isDone(DailyMissionTracker.consultation),
      _missions.isDone(DailyMissionTracker.moment),
    ]);
    if (!mounted) return;
    setState(() {
      _loadedDay = _today;
      _done[_Mission.partage] = results[0];
      _done[_Mission.tirage] = results[1];
      _done[_Mission.consultation] = results[2];
      _done[_Mission.moment] = results[3];
    });
  }

  void _goTab(int index, {VoidCallback? fallback}) {
    final scope = MainNavScope.maybeOf(context);
    if (scope != null) {
      scope.goToTab(index);
    } else {
      fallback?.call();
    }
  }

  Future<void> _onMissionTap(_Mission m) async {
    switch (m) {
      case _Mission.tirage:
        // Ouvre le hub « Tirage & Jeu » (onglet 1). La mission ne se coche
        // pas ici : uniquement sur une sauvegarde de tirage réelle.
        _goTab(
          kTabTirage,
          fallback: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TirageJeuScreen())),
        );
      case _Mission.consultation:
        // Ouvre l'onglet central CONSULTATION -> LISTE des discussions.
        // N'ouvre JAMAIS directement un ChatScreen basé sur `selectedAdvisor`
        // (J6-F2 §12). Ne coche PAS la mission (elle se coche sur une activité
        // de consultation réelle).
        _goTab(kTabConsultation);
      case _Mission.partage:
        final t = _thought;
        if (t == null) return;
        await showDailyThoughtSheet(
          context,
          thought: t,
          tracker: _shareTracker,
        );
      case _Mission.moment:
        // Ouvre l'onglet Méditation. La mission ne se coche PAS ici :
        // uniquement sur une séance réellement aboutie (cf. MeditationScreen).
        _goTab(kTabMeditation);
    }
    if (mounted) await _refresh();
  }

  int get _completed => _done.values.where((v) => v).length;

  @override
  Widget build(BuildContext context) {
    if (_loadedDay != null && _loadedDay != _today) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }

    final total = _Mission.values.length; // 4
    final completed = _completed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'TES MISSIONS DU JOUR',
              style: AuryelText.body(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.gold,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              '$completed/$total',
              style: AuryelText.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : completed / total,
            minHeight: 3,
            backgroundColor: AuryelColors.warmBorder,
            valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
          ),
        ),
        const SizedBox(height: 6),
        _MissionRow(
          label: 'Fais ton tirage',
          icon: PhosphorIconsRegular.cardsThree,
          done: _done[_Mission.tirage]!,
          onTap: () => _onMissionTap(_Mission.tirage),
        ),
        _MissionRow(
          label: 'Consulte ton conseiller',
          icon: PhosphorIconsRegular.chatCircle,
          done: _done[_Mission.consultation]!,
          onTap: () => _onMissionTap(_Mission.consultation),
        ),
        _MissionRow(
          label: 'Partage ta pensée',
          icon: PhosphorIconsRegular.shareNetwork,
          done: _done[_Mission.partage]!,
          onTap: () => _onMissionTap(_Mission.partage),
        ),
        _MissionRow(
          label: 'Prends ton Moment',
          icon: PhosphorIconsRegular.flowerLotus,
          done: _done[_Mission.moment]!,
          onTap: () => _onMissionTap(_Mission.moment),
        ),
        if (completed == total) ...[
          const SizedBox(height: 6),
          Text(
            'Journée Auryel complétée',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
              letterSpacing: 0.4,
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
    required this.icon,
    required this.done,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final animDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final color = done ? AuryelColors.goldLight : AuryelColors.textSecondary;

    return Semantics(
      button: true,
      checked: done,
      label: '$label${done ? ', accomplie' : ''}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: animDuration,
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: done
                      ? const PhosphorIcon(
                          PhosphorIconsFill.checkCircle,
                          key: ValueKey('done'),
                          size: 20,
                          color: AuryelColors.goldLight,
                        )
                      : PhosphorIcon(
                          PhosphorIconsRegular.circle,
                          key: const ValueKey('todo'),
                          size: 20,
                          color: AuryelColors.textMuted,
                        ),
                ),
                const SizedBox(width: 12),
                PhosphorIcon(icon, size: 15, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AuryelText.body(
                      fontSize: 13,
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      color: color,
                    ),
                  ),
                ),
                if (!done)
                  PhosphorIcon(
                    PhosphorIconsRegular.caretRight,
                    size: 13,
                    color: AuryelColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 3 — TEMPS DISPONIBLE (bloc compact)
// ===========================================================================

class _TimeAvailableBlock extends StatelessWidget {
  const _TimeAvailableBlock({
    required this.consultation,
    this.preferredAdvisor,
  });

  final ConsultationController? consultation;
  final AdvisorInfo? preferredAdvisor;

  static ConsultationState _derive(ConsultationController c) {
    if (c.hasActiveSession) return ConsultationState.active;
    final q = c.quota;
    if (q?.firstFreeAvailable == true) return ConsultationState.firstFree;
    final t = c.time;
    if (t != null) {
      return t.hasTime
          ? ConsultationState.subscriberAvailable
          : ConsultationState.locked;
    }
    if (q == null) return ConsultationState.firstFree;
    if (q.isPremium && q.monthlyRemaining > 0) {
      return ConsultationState.subscriberAvailable;
    }
    if (q.earnedAvailable > 0) return ConsultationState.subscriberAvailable;
    return ConsultationState.locked;
  }

  void _openConsultationTab(BuildContext context) {
    // J6-F2 §9-§12 — le CTA consultation de l'Accueil ouvre TOUJOURS l'onglet
    // Consultation (la LISTE) : jamais un ChatScreen, jamais un fil choisi
    // d'office, jamais `selectedAdvisor`.
    MainNavScope.maybeOf(context)?.goToTab(kTabConsultation);
  }

  void _openPremium(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    final value = c?.availableTimeLabel ?? '1 h offerte';
    final state = c != null ? _derive(c) : ConsultationState.firstFree;

    String? activeLine;
    String ctaLabel;
    VoidCallback? onTap;

    // « au moins une consultation existe » : fil listé OU session logique en
    // cours.
    final hasThread =
        c != null && (c.hasConsultations || c.hasResumableConsultation);

    switch (state) {
      case ConsultationState.active:
        final session = c!.active!;
        final adv = advisorByGuideKey(session.advisorId) ?? preferredAdvisor;
        final name = adv?.name;
        activeLine = name != null ? 'Consultation en cours avec $name' : null;
        ctaLabel = 'Consultation en cours';
        onTap = () => _openConsultationTab(context);
      case ConsultationState.locked:
        ctaLabel = 'S’abonner';
        onTap = () => _openPremium(context);
      case ConsultationState.firstFree:
      case ConsultationState.subscriberAvailable:
        ctaLabel = hasThread
            ? 'Consultation en cours'
            : 'Commencer une consultation';
        onTap = () => _openConsultationTab(context);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AuryelColors.surface.withValues(alpha: 0.5),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TEMPS DISPONIBLE',
            style: AuryelText.body(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: AuryelColors.gold,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AuryelText.display(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          if (activeLine != null) ...[
            const SizedBox(height: 2),
            Text(
              activeLine,
              style: AuryelText.body(
                fontSize: 11,
                color: AuryelColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _CompactCta(label: ctaLabel, onTap: onTap),
        ],
      ),
    );
  }
}

class _CompactCta extends StatelessWidget {
  const _CompactCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AuryelColors.backgroundDeep,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

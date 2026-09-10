import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/wellbeing_api.dart';
import '../theme/auryel_theme.dart';

/// « Mon parcours bien-être » rendu comme une CARTE DE PROGRESSION type jeu :
/// un chemin serpentant relie les 30 journées du cycle courant. Les journées
/// complétées sont validées (or, coche), la journée du jour est mise en valeur
/// (halo doré + « AUJOURD'HUI »), les journées futures sont visibles mais
/// verrouillées. Le serveur reste l'unique autorité (données [WellbeingProgress]
/// inchangées) — ce widget ne fait que les mettre en scène.
///
/// Ce n'est PAS une liste verticale de tâches ni une checklist : c'est un
/// chemin visuel avec des nœuds reliés, où l'on avance jour après jour.
class WellbeingJourneyMap extends StatefulWidget {
  const WellbeingJourneyMap({
    super.key,
    required this.progress,
    required this.busy,
    required this.onMissionCta,
    required this.onRefresh,
  });

  final WellbeingProgress progress;
  final bool busy;
  final ValueChanged<String> onMissionCta;
  final Future<void> Function() onRefresh;

  @override
  State<WellbeingJourneyMap> createState() => _WellbeingJourneyMapState();
}

class _WellbeingJourneyMapState extends State<WellbeingJourneyMap> {
  final ScrollController _scroll = ScrollController();
  bool _centered = false;

  static const int _cycle = 30;
  static const double _topPad = 18;
  static const double _rowGap = 64;
  static const double _bottomPad = 24;

  // Fractions d'abscisse (S-curve douce) selon la parité de la ligne.
  static const List<double> _xFrac = [0.24, 0.5, 0.76, 0.5];

  int get _done => widget.progress.cycleCompletedDays.clamp(0, _cycle);
  int get _currentIndex => _done >= _cycle ? _cycle - 1 : _done;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _centerOnCurrent(double viewportH) {
    if (_centered || !_scroll.hasClients) return;
    _centered = true;
    final y = _topPad + _currentIndex * _rowGap;
    final target = (y - viewportH * 0.42).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final pathHeight = _topPad + (_cycle - 1) * _rowGap + _bottomPad;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: AuryelColors.gold,
      backgroundColor: AuryelColors.surface,
      child: LayoutBuilder(
        builder: (context, box) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _centerOnCurrent(box.maxHeight),
          );
          return SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(progress: p),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, inner) {
                    final w = inner.maxWidth;
                    final centers = <Offset>[
                      for (var i = 0; i < _cycle; i++)
                        Offset(
                          w * _xFrac[i % 4],
                          _topPad + i * _rowGap,
                        ),
                    ];
                    return SizedBox(
                      height: pathHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PathPainter(
                                centers: centers,
                                completedThrough: _done,
                              ),
                            ),
                          ),
                          for (var i = 0; i < _cycle; i++)
                            _NodePositioned(
                              center: centers[i],
                              day: i + 1,
                              state: i < _done
                                  ? _NodeState.done
                                  : (i == _done && _done < _cycle)
                                        ? _NodeState.current
                                        : _NodeState.locked,
                              levelName: _levelForDay(i + 1),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                _TodayStep(
                  progress: p,
                  busy: widget.busy,
                  onCta: widget.onMissionCta,
                ),
                const SizedBox(height: 14),
                _RewardLine(progress: p),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _levelForDay(int day) {
    for (final (d, name) in kWellbeingLevels) {
      if (d == day) return name;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.progress});

  final WellbeingProgress progress;

  @override
  Widget build(BuildContext context) {
    final done = progress.cycleCompletedDays;
    const target = 30;
    final ratio = (done / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
              Flexible(
                child: Text(
                  'CYCLE ${progress.cycleNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.gold,
                    letterSpacing: 2,
                  ),
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
          const SizedBox(height: 6),
          Text(
            done <= 1 ? '$done journée validée' : '$done journées validées',
            style: AuryelText.display(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          if (progress.currentLevel != null) ...[
            const SizedBox(height: 2),
            Text(
              'Niveau ${progress.currentLevel}',
              style: AuryelText.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AuryelColors.warmBorder,
              valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progress.completedDaysTotal <= 1
                ? '${progress.completedDaysTotal} journée complétée depuis le début'
                : '${progress.completedDaysTotal} journées complétées depuis le début',
            style: AuryelText.body(
              fontSize: 11.5,
              color: AuryelColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

enum _NodeState { done, current, locked }

class _NodePositioned extends StatelessWidget {
  const _NodePositioned({
    required this.center,
    required this.day,
    required this.state,
    required this.levelName,
  });

  final Offset center;
  final int day;
  final _NodeState state;
  final String? levelName;

  @override
  Widget build(BuildContext context) {
    final size = switch (state) {
      _NodeState.current => 52.0,
      _NodeState.done => 38.0,
      _NodeState.locked => 30.0,
    };
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: _Node(day: day, state: state, size: size, levelName: levelName),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.day,
    required this.state,
    required this.size,
    required this.levelName,
  });

  final int day;
  final _NodeState state;
  final double size;
  final String? levelName;

  @override
  Widget build(BuildContext context) {
    final Widget circle;
    switch (state) {
      case _NodeState.done:
        circle = Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AuryelColors.goldGradient,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.check_rounded,
            size: 20,
            color: AuryelColors.backgroundDeep,
          ),
        );
      case _NodeState.current:
        circle = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AuryelColors.goldGradient,
            boxShadow: [
              BoxShadow(
                color: AuryelColors.goldLight.withValues(alpha: 0.55),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
            border: Border.all(color: AuryelColors.textCream, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: AuryelText.display(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AuryelColors.backgroundDeep,
            ),
          ),
        );
      case _NodeState.locked:
        circle = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AuryelColors.surface.withValues(alpha: 0.7),
            border: Border.all(
              color: AuryelColors.warmBorder,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: AuryelText.body(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textMuted,
            ),
          ),
        );
    }

    final children = <Widget>[circle];
    if (state == _NodeState.current) {
      children
        ..add(const SizedBox(height: 4))
        ..add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AuryelColors.backgroundDeep.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'AUJOURD’HUI',
              style: AuryelText.body(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: AuryelColors.goldLight,
                letterSpacing: 0.8,
              ),
            ),
          ),
        );
    } else if (levelName != null) {
      children
        ..add(const SizedBox(height: 3))
        ..add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                state == _NodeState.done
                    ? PhosphorIconsFill.star
                    : PhosphorIconsRegular.star,
                size: 10,
                color: state == _NodeState.done
                    ? AuryelColors.goldLight
                    : AuryelColors.textMuted,
              ),
              const SizedBox(width: 3),
              Text(
                levelName!,
                style: AuryelText.body(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: state == _NodeState.done
                      ? AuryelColors.goldLight
                      : AuryelColors.textMuted,
                ),
              ),
            ],
          ),
        );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Trace le chemin serpentant entre les nœuds : segment complété en or, reste
/// en teinte discrète.
class _PathPainter extends CustomPainter {
  _PathPainter({required this.centers, required this.completedThrough});

  final List<Offset> centers;
  final int completedThrough;

  Path _through(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final mid = Offset(
        (pts[i - 1].dx + pts[i].dx) / 2,
        (pts[i - 1].dy + pts[i].dy) / 2,
      );
      path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.length < 2) return;
    final base = Paint()
      ..color = AuryelColors.warmBorder.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_through(centers), base);

    final n = completedThrough.clamp(0, centers.length);
    if (n >= 2) {
      final gold = Paint()
        ..color = AuryelColors.goldLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(_through(centers.sublist(0, n)), gold);
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.completedThrough != completedThrough || old.centers != centers;
}

// ---------------------------------------------------------------------------

class _TodayStep extends StatelessWidget {
  const _TodayStep({
    required this.progress,
    required this.busy,
    required this.onCta,
  });

  final WellbeingProgress progress;
  final bool busy;
  final ValueChanged<String> onCta;

  static const Map<String, ({String name, String cta})> _labels = {
    'pensee': (name: 'Pensée du jour', cta: 'Voir la pensée'),
    'tirage': (name: 'Carte du jour', cta: 'Découvrir ma carte'),
    'consultation': (name: 'Consultation', cta: 'Ouvrir'),
    'moment': (name: 'Moment', cta: 'Prendre un moment'),
  };

  @override
  Widget build(BuildContext context) {
    final day = progress.cycleCompletedDays + 1;
    final done = progress.today.missions.where((m) => m.completed).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AuryelColors.surface.withValues(alpha: 0.55),
        border: Border.all(
          color: AuryelColors.goldLight.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ÉTAPE DU JOUR · JOUR $day',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AuryelColors.gold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$done/4',
                style: AuryelText.body(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AuryelColors.goldLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final id in kWellbeingMissions)
            _MissionChip(
              label: _labels[id]!,
              completed: progress.today.mission(id)?.completed ?? false,
              enabled: !busy,
              onTap: () => onCta(id),
            ),
          if (progress.today.completed) ...[
            const SizedBox(height: 4),
            Text(
              'Journée complétée — elle est validée sur ta carte.',
              style: AuryelText.body(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MissionChip extends StatelessWidget {
  const _MissionChip({
    required this.label,
    required this.completed,
    required this.enabled,
    required this.onTap,
  });

  final ({String name, String cta}) label;
  final bool completed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: PhosphorIcon(
              completed
                  ? PhosphorIconsFill.checkCircle
                  : PhosphorIconsRegular.circle,
              size: 18,
              color: completed
                  ? AuryelColors.goldLight
                  : AuryelColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.name,
                  style: AuryelText.body(
                    fontSize: 13,
                    fontWeight: completed
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: completed
                        ? AuryelColors.goldLight
                        : AuryelColors.textCream,
                  ),
                ),
                if (!completed)
                  TextButton(
                    onPressed: enabled ? onTap : null,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(
                      label.cta,
                      style: AuryelText.body(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (completed) ...[
            const SizedBox(width: 6),
            Text(
              'Terminée',
              style: AuryelText.body(
                fontSize: 10.5,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewardLine extends StatelessWidget {
  const _RewardLine({required this.progress});

  final WellbeingProgress progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            AuryelColors.gold.withValues(alpha: 0.14),
            AuryelColors.gold.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: AuryelColors.goldLight.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const PhosphorIcon(
            PhosphorIconsFill.gift,
            size: 15,
            color: AuryelColors.goldLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              progress.rewardEarnedForCurrentCycle
                  ? 'Récompense du cycle ${progress.cycleNumber} déjà ajoutée à ton temps de consultation.'
                  : 'Au bout des 30 journées : 15 minutes de consultation offertes. Chaque journée compte, même après une pause.',
              style: AuryelText.body(
                fontSize: 11.5,
                height: 1.4,
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

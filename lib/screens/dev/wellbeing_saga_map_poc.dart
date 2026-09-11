// ============================================================================
// POC — DEV ONLY. Prototype visuel isolé du futur parcours bien-être Auryel
// avec le package `saga_map`.
//
// Ce fichier ne remplace PAS l'écran de production
// (`screens/wellbeing_journey_screen.dart` + `widgets/wellbeing_journey_map.dart`,
// qui restent le parcours réel affiché aux utilisatrices). Aucune logique
// métier réelle n'est câblée ici : l'état des 7 jours est une donnée figée de
// démonstration, uniquement destinée à évaluer si `saga_map` peut donner une
// sensation de "monde à explorer" façon jeu d'aventure.
//
// Accès : geste debug uniquement (voir home_screen.dart, appui long sur la
// carte « Suivre mon parcours bien-être », gardé par `kDebugMode`). Ne touche
// à aucune navigation de production.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saga_map/saga_map.dart';

import '../../theme/auryel_theme.dart';

/// Un des 7 jours du parcours prototype.
class _JourneyStep {
  const _JourneyStep({
    required this.dayLabel,
    required this.title,
    required this.blurb,
  });

  final String dayLabel;
  final String title;
  final String blurb;
}

const List<_JourneyStep> _kSteps = [
  _JourneyStep(
    dayLabel: 'Jour 1',
    title: 'Première lumière',
    blurb: 'Tu poses la première pierre de ton chemin.',
  ),
  _JourneyStep(
    dayLabel: 'Jour 2',
    title: 'Le miroir',
    blurb: 'Un instant pour te regarder telle que tu es.',
  ),
  _JourneyStep(
    dayLabel: 'Jour 3',
    title: 'La clairière',
    blurb: 'Une pause lumineuse au milieu de la forêt.',
  ),
  _JourneyStep(
    dayLabel: 'Jour 4',
    title: 'Le passage',
    blurb: 'Le chemin se resserre avant de s’ouvrir à nouveau.',
  ),
  _JourneyStep(
    dayLabel: 'Jour 5',
    title: 'Le sanctuaire',
    blurb: 'Un lieu à toi, protégé, pour souffler.',
  ),
  _JourneyStep(
    dayLabel: 'Jour 6',
    title: 'La montagne',
    blurb: 'La pente se fait sentir, mais la vue change tout.',
  ),
  _JourneyStep(
    dayLabel: 'Jour 7',
    title: 'Le sommet',
    blurb: 'Le point culminant de cette première semaine.',
  ),
];

/// Exemple d'état demandé : jours 1-3 terminés, jour 4 en cours, 5-7 verrouillés.
const int _kCurrentStepId = 3; // "Jour 4" (id zéro-based)

const Map<int, LevelCompletionState> _kDemoProgress = {
  0: LevelCompletionState.completed,
  1: LevelCompletionState.completed,
  2: LevelCompletionState.completed,
  3: LevelCompletionState.unlocked,
  4: LevelCompletionState.locked,
  5: LevelCompletionState.locked,
  6: LevelCompletionState.locked,
};

const String _kAuryelBiomeId = 'auryel_sanctuaire_nocturne';
const double _kStepHeight = 0.145;

/// Écran prototype : carte d'aventure verticale à 7 étapes, univers Auryel
/// original (forêt nocturne, rivière, clairière, sanctuaire, montagne, lune,
/// étoiles, brume, chemin doré) — inspiration jeu d'aventure/exploration,
/// aucun asset ni référence Nintendo/Zelda.
class WellbeingSagaMapPocScreen extends StatefulWidget {
  const WellbeingSagaMapPocScreen({super.key});

  @override
  State<WellbeingSagaMapPocScreen> createState() =>
      _WellbeingSagaMapPocScreenState();
}

class _WellbeingSagaMapPocScreenState extends State<WellbeingSagaMapPocScreen>
    with TickerProviderStateMixin {
  late final SagaCharacterController _character;
  late final List<LevelData> _levels;

  @override
  void initState() {
    super.initState();
    _character = SagaCharacterController(
      vsync: this,
      initialPosition: (_kCurrentStepId - 1).clamp(0, 6).toDouble(),
    );
    _levels = List.generate(_kSteps.length, (i) {
      // Léger balancement latéral non linéaire : chemin qui serpente au lieu
      // d'un simple zig-zag mécanique gauche/droite.
      final wobble = math.sin(i * 1.9) * 0.22;
      final x = (0.5 + wobble).clamp(0.24, 0.76);
      return LevelData(
        id: i,
        position: SagaPoint(x, i * _kStepHeight),
        biomeId: _kAuryelBiomeId,
      );
    });
    // Petite marche d'arrivée : donne une sensation de présence/déplacement
    // dès l'ouverture, sans dépendre d'une vraie action utilisateur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _character.moveTo(_kCurrentStepId.toDouble());
      }
    });
  }

  @override
  void dispose() {
    _character.dispose();
    super.dispose();
  }

  void _handleNodeTap(LevelData level) {
    final step = _kSteps[level.id];
    final state = _kDemoProgress[level.id] ?? LevelCompletionState.locked;
    switch (state) {
      case LevelCompletionState.completed:
        _showStepInfoSheet(step);
      case LevelCompletionState.unlocked:
        _showContinueSheet(step);
      case LevelCompletionState.locked:
        _showLockedFeedback();
    }
  }

  void _showStepInfoSheet(_JourneyStep step) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PocSheet(
        icon: Icons.check_circle_rounded,
        iconColor: AuryelColors.goldLight,
        dayLabel: step.dayLabel,
        title: step.title,
        body: step.blurb,
        primaryLabel: 'Fermer',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showContinueSheet(_JourneyStep step) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PocSheet(
        icon: Icons.auto_awesome_rounded,
        iconColor: AuryelColors.gold,
        dayLabel: '${step.dayLabel} · en cours',
        title: step.title,
        body: step.blurb,
        primaryLabel: 'Continuer mon parcours',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showLockedFeedback() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('poc-locked-snackbar'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AuryelColors.surface,
          content: const Text(
            'Disponible prochainement',
            style: TextStyle(color: AuryelColors.textCream),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final current = _kSteps[_kCurrentStepId];
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AuryelColors.textCream,
        title: const Text(
          'POC — Carte d’aventure (saga_map)',
          style: TextStyle(fontSize: 15),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PocHeaderBanner(current: current),
            Expanded(
              child: ClipRect(
                child: InteractiveViewer(
                  key: const Key('poc-map-viewer'),
                  constrained: false,
                  minScale: 0.7,
                  maxScale: 2.4,
                  boundaryMargin: const EdgeInsets.symmetric(
                    horizontal: 120,
                    vertical: 160,
                  ),
                  child: MapChunkWidget(
                    key: const Key('poc-map-chunk'),
                    levels: _levels,
                    chunkIndex: 0,
                    chunkExtent: 1180,
                    chunkSpanNormalized: 1.0,
                    lateralBounds: const SagaLateralBounds(min: 0.12, max: 0.88),
                    biomeThemeResolver: const _AuryelBiomeThemeResolver(),
                    backgroundConfig:
                        const SagaMapBackgroundConfig.builder(_buildAuryelBackdrop),
                    pathCurvature: 0.85,
                    pathProgressPosition: _kCurrentStepId.toDouble(),
                    baseNodeSize: 60,
                    progressResolver: (level) => LevelProgress(
                      levelId: level.id,
                      state: _kDemoProgress[level.id] ?? LevelCompletionState.locked,
                    ),
                    interactionPolicy: const SagaNodeInteractionPolicy(
                      emitTapForLockedNode: true,
                      emitTapForCompletedNode: true,
                    ),
                    onLevelTap: _handleNodeTap,
                    character: SagaCharacter(
                      controller: _character,
                      size: const Size(40, 56),
                      builder: (context, state) => const _PlayerAvatar(),
                    ),
                    nodeBuilder: (context, level, layout) => _JourneyNode(
                      key: Key('poc-node-${level.id}'),
                      step: _kSteps[level.id],
                      state: _kDemoProgress[level.id] ?? LevelCompletionState.locked,
                      isCurrent: level.id == _kCurrentStepId,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildAuryelBackdrop(BuildContext context, int? chunkIndex) {
  return const _AuryelSceneBackdrop();
}

/// Thème unique "sanctuaire nocturne" : chemin parcouru doré/lumineux, chemin
/// futur assombri — l'effet "walked vs upcoming" du package.
class _AuryelBiomeThemeResolver implements SagaBiomeThemeResolver {
  const _AuryelBiomeThemeResolver();

  @override
  SagaBiomeTheme resolve(String biomeId) => const SagaBiomeTheme(
    backgroundColor: Colors.transparent,
    pathFillColor: Color(0xFFE8C468),
    pathBorderColor: Color(0xFFB8860B),
    upcomingPathFillColor: Color(0xFF241C3A),
    upcomingPathBorderColor: Color(0xFF150F24),
    shadowColor: Color(0x66000000),
    pathBorderWidth: 4.5,
    pathInnerStrokeWidth: 2.5,
    shadowBlurSigma: 10,
  );
}

/// Bandeau supérieur fixe : rappelle l'étape actuelle sans dépendre du zoom.
class _PocHeaderBanner extends StatelessWidget {
  const _PocHeaderBanner({required this.current});

  final _JourneyStep current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AuryelColors.gold.withValues(alpha: 0.16),
            AuryelColors.gold.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: AuryelColors.goldLight.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AuryelColors.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${current.dayLabel} · étape actuelle',
                  style: const TextStyle(
                    color: AuryelColors.goldLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AuryelColors.textCream,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un nœud de progression : terminé (doré, coché), actuel (halo pulsant),
/// verrouillé (assombri, cadenas).
class _JourneyNode extends StatelessWidget {
  const _JourneyNode({
    super.key,
    required this.step,
    required this.state,
    required this.isCurrent,
  });

  final _JourneyStep step;
  final LevelCompletionState state;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final dayNumber = step.dayLabel.replaceAll(RegExp(r'[^0-9]'), '');
    if (isCurrent) {
      return _CurrentNodePulse(dayNumber: dayNumber);
    }
    switch (state) {
      case LevelCompletionState.completed:
        return _NodeDisc(
          dayNumber: dayNumber,
          background: const LinearGradient(
            colors: [AuryelColors.goldLight, AuryelColors.goldDark],
          ),
          borderColor: AuryelColors.goldLight,
          textColor: const Color(0xFF241505),
          glow: AuryelColors.gold.withValues(alpha: 0.45),
          badge: const Icon(Icons.check_rounded, size: 13, color: Color(0xFF241505)),
        );
      case LevelCompletionState.locked:
        return _NodeDisc(
          dayNumber: dayNumber,
          background: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
          borderColor: Colors.white.withValues(alpha: 0.18),
          textColor: Colors.white.withValues(alpha: 0.45),
          glow: Colors.transparent,
          badge: Icon(Icons.lock_outline_rounded,
              size: 12, color: Colors.white.withValues(alpha: 0.55)),
          dimmed: true,
        );
      case LevelCompletionState.unlocked:
        // Ne devrait pas survenir hors de `_kCurrentStepId` dans ce POC ;
        // traité comme "actuel" par sécurité visuelle.
        return _CurrentNodePulse(dayNumber: dayNumber);
    }
  }
}

class _NodeDisc extends StatelessWidget {
  const _NodeDisc({
    required this.dayNumber,
    required this.background,
    required this.borderColor,
    required this.textColor,
    required this.glow,
    required this.badge,
    this.dimmed = false,
  });

  final String dayNumber;
  final Gradient background;
  final Color borderColor;
  final Color textColor;
  final Color glow;
  final Widget badge;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: background,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: glow == Colors.transparent
            ? null
            : [BoxShadow(color: glow, blurRadius: 14, spreadRadius: 1)],
      ),
      alignment: Alignment.center,
      child: Text(
        dayNumber,
        style: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Opacity(
      opacity: dimmed ? 0.85 : 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          disc,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF120E17),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: badge,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nœud "étape actuelle" : halo pulsant continu, pour qu'il se distingue au
/// premier regard sur la carte (pas de simple couleur différente).
class _CurrentNodePulse extends StatefulWidget {
  const _CurrentNodePulse({required this.dayNumber});

  final String dayNumber;

  @override
  State<_CurrentNodePulse> createState() => _CurrentNodePulseState();
}

class _CurrentNodePulseState extends State<_CurrentNodePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 70 + 10 * t,
              height: 70 + 10 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AuryelColors.gold.withValues(alpha: 0.20 * (1 - t)),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF3D6), AuryelColors.gold],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AuryelColors.gold.withValues(alpha: 0.65),
                    blurRadius: 12 + 6 * t,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                widget.dayNumber,
                style: const TextStyle(
                  color: Color(0xFF241505),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Petit avatar/marqueur joueur : orbe doré avec halo respirant, indépendant
/// du son (ce POC n'utilise aucun média audio/vidéo).
class _PlayerAvatar extends StatefulWidget {
  const _PlayerAvatar();

  @override
  State<_PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<_PlayerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathe,
      builder: (context, _) {
        final t = _breathe.value;
        return SizedBox(
          width: 40,
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 2,
                child: Container(
                  width: 30 + 8 * t,
                  height: 30 + 8 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFE9B0).withValues(alpha: 0.5 * (1 - t) + 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE9B0), Color(0xFFC9A227)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD87A).withValues(alpha: 0.75),
                        blurRadius: 9 + 4 * t,
                      ),
                    ],
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

/// Fond de carte procédural original : forêt nocturne, rivière, clairière,
/// sanctuaire, montagne, lune, étoiles, brume — univers Auryel (violet
/// profond, bleu-nuit, doré). Aucun asset externe : peint entièrement par un
/// `CustomPainter`, sans copier d'univers de jeu existant.
class _AuryelSceneBackdrop extends StatelessWidget {
  const _AuryelSceneBackdrop();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(painter: _AuryelScenePainter()),
    );
  }
}

class _AuryelScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Ciel : bleu-noir en haut -> violet profond -> presque noir en bas.
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF080714),
          Color(0xFF201538),
          Color(0xFF150C22),
          Color(0xFF0C0812),
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), sky);

    _paintStars(canvas, w, h);
    _paintMoon(canvas, w, h);
    _paintMountains(canvas, w, h);
    _paintForestBand(canvas, w, h, top: h * 0.30, jaggedness: 1.0);
    _paintRiver(canvas, w, h);
    _paintSanctuary(canvas, w, h);
    _paintForestBand(canvas, w, h, top: h * 0.72, jaggedness: 1.25);
    _paintMist(canvas, w, h);
  }

  void _paintStars(Canvas canvas, double w, double h) {
    final rnd = math.Random(7);
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 70; i++) {
      final dx = rnd.nextDouble() * w;
      final dy = rnd.nextDouble() * h * 0.6;
      final radius = 0.5 + rnd.nextDouble() * 1.3;
      paint.color = Colors.white.withValues(alpha: 0.25 + rnd.nextDouble() * 0.55);
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  void _paintMoon(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.76, h * 0.12);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF3E7C8).withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 90));
    canvas.drawCircle(center, 90, glow);
    final moon = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFF7E3), Color(0xFFE6D6A8)],
      ).createShader(Rect.fromCircle(center: center, radius: 26));
    canvas.drawCircle(center, 26, moon);
  }

  void _paintMountains(Canvas canvas, double w, double h) {
    final path = Path()..moveTo(0, h * 0.30);
    final points = [0.0, 0.15, 0.32, 0.48, 0.65, 0.82, 1.0];
    final heights = [0.30, 0.20, 0.26, 0.16, 0.24, 0.18, 0.28];
    for (var i = 0; i < points.length; i++) {
      path.lineTo(w * points[i], h * heights[i]);
    }
    path.lineTo(w, h * 0.30);
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF1B1330).withValues(alpha: 0.9),
    );
  }

  void _paintForestBand(
    Canvas canvas,
    double w,
    double h, {
    required double top,
    required double jaggedness,
  }) {
    final rnd = math.Random((top * 13).round());
    final path = Path()..moveTo(0, top + 40);
    double x = 0;
    while (x < w) {
      final treeWidth = 18 + rnd.nextDouble() * 22;
      final treeHeight = (26 + rnd.nextDouble() * 30) * jaggedness;
      path.lineTo(x + treeWidth / 2, top - treeHeight);
      path.lineTo(x + treeWidth, top + 40);
      x += treeWidth;
    }
    path.lineTo(w, top + 60);
    path.lineTo(0, top + 60);
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF130E20).withValues(alpha: 0.95),
    );
  }

  void _paintRiver(Canvas canvas, double w, double h) {
    final y = h * 0.55;
    final path = Path()
      ..moveTo(0, y)
      ..quadraticBezierTo(w * 0.3, y - 22, w * 0.55, y)
      ..quadraticBezierTo(w * 0.8, y + 22, w, y - 6)
      ..lineTo(w, y + 34)
      ..quadraticBezierTo(w * 0.8, y + 56, w * 0.55, y + 34)
      ..quadraticBezierTo(w * 0.3, y + 12, 0, y + 34)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AuryelColors.gold.withValues(alpha: 0.18),
            const Color(0xFF3A2F63).withValues(alpha: 0.35),
          ],
        ).createShader(Rect.fromLTWH(0, y - 20, w, 70)),
    );
  }

  void _paintSanctuary(Canvas canvas, double w, double h) {
    final baseX = w * 0.5;
    final baseY = h * 0.47;
    final paint = Paint()..color = const Color(0xFF0F0A1A).withValues(alpha: 0.92);
    // Toit pointu.
    final roof = Path()
      ..moveTo(baseX - 26, baseY)
      ..lineTo(baseX, baseY - 30)
      ..lineTo(baseX + 26, baseY)
      ..close();
    canvas.drawPath(roof, paint);
    // Corps + arche.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(baseX - 20, baseY, 40, 26),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, paint);
    final archPaint = Paint()..color = AuryelColors.gold.withValues(alpha: 0.55);
    canvas.drawArc(
      Rect.fromLTWH(baseX - 7, baseY + 8, 14, 18),
      math.pi,
      math.pi,
      false,
      archPaint..style = PaintingStyle.stroke..strokeWidth = 1.6,
    );
    // Lueur douce autour du sanctuaire.
    canvas.drawCircle(
      Offset(baseX, baseY + 6),
      42,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AuryelColors.gold.withValues(alpha: 0.14),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(baseX, baseY + 6), radius: 42)),
    );
  }

  void _paintMist(Canvas canvas, double w, double h) {
    final bands = [h * 0.50, h * 0.68, h * 0.85];
    for (final y in bands) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 30);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w * 0.5, y), width: w * 1.2, height: 46),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuryelScenePainter oldDelegate) => false;
}

/// Feuille bas d'écran pour l'information d'une étape ou le CTA "Continuer".
class _PocSheet extends StatelessWidget {
  const _PocSheet({
    required this.icon,
    required this.iconColor,
    required this.dayLabel,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final Color iconColor;
  final String dayLabel;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF171120),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AuryelColors.goldLight.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Text(
                  dayLabel,
                  style: const TextStyle(
                    color: AuryelColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: AuryelColors.textCream,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(color: AuryelColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AuryelColors.gold,
                  foregroundColor: const Color(0xFF241505),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

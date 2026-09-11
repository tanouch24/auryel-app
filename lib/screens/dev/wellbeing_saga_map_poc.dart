// ============================================================================
// POC — DEV/TEST UNIQUEMENT. Prototype visuel isolé du futur parcours
// bien-être Auryel avec le package `saga_map` : une véritable carte
// d'aventure animée (30 jours, 6 régions), pas une roadmap.
//
// Ce fichier ne remplace PAS l'écran de production
// (`screens/wellbeing_journey_screen.dart` + `widgets/wellbeing_journey_map.dart`,
// qui restent le parcours réel affiché aux utilisatrices). Aucune logique
// métier réelle n'est câblée ici : la progression (`_progress`, `_currentDay1`)
// est un état LOCAL, purement visuel, jamais lu ni écrit nulle part ailleurs
// dans l'app — aucun appel API, aucune persistance.
//
// ACCÈS TEMPORAIRE POUR CE BUILD DE TEST SAMSUNG UNIQUEMENT :
// voir `kAuryelPocTempSamsungTestAccessEnabled` tout en bas de ce fichier et
// le commentaire associé dans home_screen.dart. Cet accès doit être RETIRÉ
// (ou re-gardé par kDebugMode) avant toute release de production réelle.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:saga_map/saga_map.dart';

import '../../theme/auryel_theme.dart';

// ============================================================================
// 1. MONDE : régions, jours, étapes majeures
// ============================================================================

const int kAuryelPocTotalDays = 30;

/// Jour actuel de démonstration (1-based) — reprend l'exemple du HUD demandé :
/// "Jour 12 / 30 — 40 % du parcours". Purement une donnée de démo locale.
const int kAuryelPocDemoCurrentDay1 = 12;

/// Une région du monde (5 jours chacune, 6 régions -> 30 jours).
class _WorldRegion {
  const _WorldRegion({
    required this.name,
    required this.startDay1,
    required this.endDay1,
    required this.washColor,
    required this.decorColor,
    required this.ambient,
  });

  final String name;
  final int startDay1;
  final int endDay1;

  /// Teinte dominante de la région, en glacis translucide sur le ciel de base.
  final Color washColor;

  /// Couleur des silhouettes/décor (arbres, rochers, colonnes...).
  final Color decorColor;

  /// Lueur d'ambiance (lucioles, lanternes, cristal...) propre à la région.
  final Color ambient;

  bool contains(int day1) => day1 >= startDay1 && day1 <= endDay1;
}

const List<_WorldRegion> _kAuryelPocRegions = [
  _WorldRegion(
    name: 'La Forêt Intérieure',
    startDay1: 1,
    endDay1: 5,
    washColor: Color(0xFF16321F),
    decorColor: Color(0xFF0C1B12),
    ambient: Color(0xFFBFE7A8),
  ),
  _WorldRegion(
    name: 'La Rivière des Émotions',
    startDay1: 6,
    endDay1: 10,
    washColor: Color(0xFF173248),
    decorColor: Color(0xFF10222F),
    ambient: Color(0xFF9FD3E8),
  ),
  _WorldRegion(
    name: 'Le Sanctuaire de l’Ancrage',
    startDay1: 11,
    endDay1: 15,
    washColor: Color(0xFF2E2145),
    decorColor: Color(0xFF17101F),
    ambient: Color(0xFFE4CE88),
  ),
  _WorldRegion(
    name: 'La Vallée de la Sérénité',
    startDay1: 16,
    endDay1: 20,
    washColor: Color(0xFF3B335A),
    decorColor: Color(0xFF473F66),
    ambient: Color(0xFFEDE3F8),
  ),
  _WorldRegion(
    name: 'Le Chemin de l’Équilibre',
    startDay1: 21,
    endDay1: 25,
    washColor: Color(0xFF241F33),
    decorColor: Color(0xFF161222),
    ambient: Color(0xFFCFC7E8),
  ),
  _WorldRegion(
    name: 'L’Ascension',
    startDay1: 26,
    endDay1: 30,
    washColor: Color(0xFF120B22),
    decorColor: Color(0xFF08050F),
    ambient: Color(0xFFFFF3D6),
  ),
];

_WorldRegion _regionForDay1(int day1) =>
    _kAuryelPocRegions.firstWhere((r) => r.contains(day1), orElse: () => _kAuryelPocRegions.last);

bool isMajorDay1(int day1) => day1 % 5 == 0;

/// Nom des étapes majeures (tous les 5 jours).
String? majorNameForDay1(int day1) {
  switch (day1) {
    case 5:
      return 'La Clairière';
    case 10:
      return 'Ancrage';
    case 15:
      return 'Harmonie';
    case 20:
      return 'Sérénité';
    case 25:
      return 'Équilibre';
    case 30:
      return 'Le Sommet';
    default:
      return null;
  }
}

IconData iconForMajorDay1(int day1) {
  switch (day1) {
    case 5:
      return Icons.local_fire_department_rounded; // feu de camp / clairière
    case 10:
      return Icons.foundation_rounded; // pont / ancrage
    case 15:
      return Icons.account_balance_rounded; // temple / sanctuaire
    case 20:
      return Icons.diamond_rounded; // cristal
    case 25:
      return Icons.meeting_room_rounded; // portail
    case 30:
    default:
      return Icons.auto_awesome_rounded; // sommet / lumière
  }
}

String blurbForDay1(int day1) {
  final major = majorNameForDay1(day1);
  if (major != null) {
    return 'Une étape marquante de ${_regionForDay1(day1).name}.';
  }
  return 'Une courte mission t’attend dans ${_regionForDay1(day1).name}.';
}

/// Fraction verticale normalisée (0..1) du jour [day1] le long du chemin.
/// Petite marge en haut/bas (0.02) pour que le décor respire autour du
/// premier et du dernier nœud.
double dayYFraction(int day1) {
  const margin = 0.02;
  final t = (day1 - 1) / (kAuryelPocTotalDays - 1);
  return margin + t * (1 - 2 * margin);
}

/// Position latérale (0..1) du chemin à l'index continu [i] (0-based, peut
/// être fractionnaire) — un serpentin organique, pas un zig-zag mécanique.
/// Partagée entre le placement des nœuds et le décor, pour que la rivière/les
/// arbres semblent vraiment longer le chemin.
double pathXFraction(double i) {
  final slow = math.sin(i * 0.35) * 0.20;
  final fast = math.sin(i * 1.7) * 0.09;
  return (0.5 + slow + fast).clamp(0.16, 0.84);
}

const String _kAuryelBiomeId = 'auryel_monde_nocturne';

/// Taille de base du chemin, en pixels avant mise à l'échelle responsive
/// (`ResolvedSagaLayout.nodeSpacing`). Choisie pour ~130px entre deux jours
/// consécutifs sur mobile — un vrai monde à parcourir, pas une mini-carte.
const double kAuryelPocChunkExtent = 4400;
const double kAuryelPocChunkSpan = 1.0;
const SagaLateralBounds kAuryelPocLateralBounds = SagaLateralBounds(min: 0.12, max: 0.88);

/// Longueur réelle du chemin en pixels pour un [viewportWidth] donné —
/// même calcul que celui fait en interne par `MapChunkWidget`, dupliqué ici
/// pour positionner la caméra et les décors hors-bande sans dépendre d'un
/// détail d'implémentation privé du package.
double resolveAlongExtent(double viewportWidth) {
  const resolver = SagaResponsiveResolver();
  final layout = resolver.resolveForWidth(viewportWidth);
  return (kAuryelPocChunkExtent * layout.nodeSpacing).roundToDouble();
}

// ============================================================================
// 2. ÉCRAN
// ============================================================================

/// Écran prototype : véritable carte d'aventure de 30 jours / 6 régions,
/// univers Auryel 100% original (aucun asset, aucune référence Zelda/Nintendo).
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
  final TransformationController _transform = TransformationController();

  late int _currentDay1;
  late final Map<int, LevelCompletionState> _progress;

  bool _isAnimatingProgress = false;
  double _animatedPathProgress = 0;
  int? _burstAtLevelId;

  bool _cameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _currentDay1 = kAuryelPocDemoCurrentDay1;
    _progress = {
      for (var day1 = 1; day1 <= kAuryelPocTotalDays; day1++)
        day1 - 1: day1 < _currentDay1
            ? LevelCompletionState.completed
            : day1 == _currentDay1
                ? LevelCompletionState.unlocked
                : LevelCompletionState.locked,
    };
    _animatedPathProgress = (_currentDay1 - 1).toDouble();

    _character = SagaCharacterController(
      vsync: this,
      initialPosition: (_currentDay1 - 1).toDouble(),
    );
    _levels = List.generate(kAuryelPocTotalDays, (i) {
      return LevelData(
        id: i,
        position: SagaPoint(pathXFraction(i.toDouble()), dayYFraction(i + 1)),
        biomeId: _kAuryelBiomeId,
      );
    });
  }

  @override
  void dispose() {
    _character.dispose();
    _transform.dispose();
    super.dispose();
  }

  double get _pathProgressPosition =>
      _isAnimatingProgress ? _animatedPathProgress : (_currentDay1 - 1).toDouble();

  void _centerCameraOnCurrent(double viewportWidth, double viewportHeight) {
    final alongExtent = resolveAlongExtent(viewportWidth);
    final targetY = dayYFraction(_currentDay1) * alongExtent;
    final minDy = math.min(0.0, viewportHeight - alongExtent);
    final dy = (viewportHeight / 2 - targetY).clamp(minDy, 0.0);
    _transform.value = Matrix4.translationValues(0.0, dy, 0.0);
  }

  void _handleNodeTap(LevelData level) {
    final day1 = level.id + 1;
    final state = _progress[level.id] ?? LevelCompletionState.locked;
    switch (state) {
      case LevelCompletionState.completed:
        _showCompletedSheet(day1);
      case LevelCompletionState.unlocked:
        _showCurrentSheet(day1);
      case LevelCompletionState.locked:
        _showFutureSheet();
    }
  }

  void _showCompletedSheet(int day1) {
    final major = majorNameForDay1(day1);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PocSheet(
        icon: Icons.check_circle_rounded,
        iconColor: AuryelColors.goldLight,
        dayLabel: 'Jour $day1 · terminé',
        title: major ?? _regionForDay1(day1).name,
        body: 'Mission terminée. ${blurbForDay1(day1)}',
        primaryLabel: 'Revoir',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showCurrentSheet(int day1) {
    final major = majorNameForDay1(day1);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PocSheet(
        icon: Icons.auto_awesome_rounded,
        iconColor: AuryelColors.gold,
        dayLabel: 'Jour $day1 · en cours',
        title: major ?? _regionForDay1(day1).name,
        body: blurbForDay1(day1),
        primaryLabel: 'Continuer mon parcours',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showFutureSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PocSheet(
        key: const Key('poc-future-sheet'),
        icon: Icons.blur_on_rounded,
        iconColor: AuryelColors.textMuted,
        dayLabel: 'À venir',
        title: 'Dans la brume',
        body: 'Cette étape se révélera bientôt.',
        primaryLabel: 'Fermer',
        onPrimary: () => Navigator.of(context).pop(),
      ),
    );
  }

  /// Joue l'animation de progression : le nœud actuel s'illumine, le chemin
  /// se colore en or jusqu'à l'étape suivante, l'avatar avance, la caméra
  /// accompagne légèrement, puis une petite lueur marque l'arrivée.
  ///
  /// ARCHITECTURE : cette méthode est le SEUL point d'entrée de l'animation
  /// de progression. Elle ne dépend d'aucune logique métier réelle — dans le
  /// futur écran de production, il suffira d'appeler cette même méthode (ou
  /// son équivalent) au moment où une mission est RÉELLEMENT validée côté
  /// backend, sans rien changer à l'animation elle-même. Ici, un bouton DEV
  /// la déclenche pour la démonstration.
  Future<void> _playProgressionDemo(double viewportWidth, double viewportHeight) async {
    if (_isAnimatingProgress) return;
    final fromDay1 = _currentDay1;
    final toDay1 = fromDay1 + 1;
    if (toDay1 > kAuryelPocTotalDays) return;

    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    setState(() => _isAnimatingProgress = true);

    final duration = reduceMotion
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 1800);
    final pathAnim = AnimationController(vsync: this, duration: duration);
    final fromId = (fromDay1 - 1).toDouble();
    final toId = (toDay1 - 1).toDouble();
    final curved = CurvedAnimation(parent: pathAnim, curve: Curves.easeInOut);

    final alongExtent = resolveAlongExtent(viewportWidth);
    final fromY = dayYFraction(fromDay1) * alongExtent;
    final toY = dayYFraction(toDay1) * alongExtent;
    final minDy = math.min(0.0, viewportHeight - alongExtent);

    void tick() {
      final t = curved.value;
      setState(() => _animatedPathProgress = fromId + (toId - fromId) * t);
      final y = fromY + (toY - fromY) * t;
      final dy = (viewportHeight / 2 - y).clamp(minDy, 0.0);
      _transform.value = Matrix4.translationValues(0.0, dy, 0.0);
    }

    pathAnim.addListener(tick);

    await Future.wait([
      pathAnim.forward(),
      _character.moveTo(toId, animate: !reduceMotion),
    ]);
    pathAnim.removeListener(tick);
    pathAnim.dispose();

    if (!mounted) return;
    setState(() {
      _progress[(fromDay1 - 1)] = LevelCompletionState.completed;
      _progress[(toDay1 - 1)] = LevelCompletionState.unlocked;
      _currentDay1 = toDay1;
      _animatedPathProgress = toId;
      _isAnimatingProgress = false;
      _burstAtLevelId = toDay1 - 1;
    });

    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _burstAtLevelId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = ((_currentDay1 / kAuryelPocTotalDays) * 100).round();
    return Scaffold(
      backgroundColor: const Color(0xFF07050F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AuryelColors.textCream,
        title: const Text(
          'POC — Carte d’aventure (saga_map)',
          style: TextStyle(fontSize: 14),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _PocHud(currentDay1: _currentDay1, percent: percent),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportWidth = constraints.maxWidth;
                  final viewportHeight = constraints.maxHeight;
                  if (!_cameraInitialized) {
                    _cameraInitialized = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _centerCameraOnCurrent(viewportWidth, viewportHeight);
                      }
                    });
                  }
                  final alongExtent = resolveAlongExtent(viewportWidth);
                  return ClipRect(
                    child: InteractiveViewer(
                      key: const Key('poc-map-viewer'),
                      transformationController: _transform,
                      constrained: false,
                      minScale: 0.6,
                      maxScale: 2.2,
                      boundaryMargin: const EdgeInsets.symmetric(
                        horizontal: 140,
                        vertical: 240,
                      ),
                      child: RepaintBoundary(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            MapChunkWidget(
                              key: const Key('poc-map-chunk'),
                              levels: _levels,
                              chunkIndex: 0,
                              chunkExtent: kAuryelPocChunkExtent,
                              chunkSpanNormalized: kAuryelPocChunkSpan,
                              lateralBounds: kAuryelPocLateralBounds,
                              biomeThemeResolver: const _AuryelBiomeThemeResolver(),
                              backgroundConfig: SagaMapBackgroundConfig.builder(
                                (context, chunkIndex) => RepaintBoundary(
                                  child: _AuryelWorldBackdrop(
                                    revealedFraction: dayYFraction(_currentDay1),
                                  ),
                                ),
                              ),
                              pathCurvature: 0.9,
                              pathProgressPosition: _pathProgressPosition,
                              baseNodeSize: 54,
                              progressResolver: (level) => LevelProgress(
                                levelId: level.id,
                                state: _progress[level.id] ?? LevelCompletionState.locked,
                              ),
                              interactionPolicy: const SagaNodeInteractionPolicy(
                                emitTapForLockedNode: true,
                                emitTapForCompletedNode: true,
                              ),
                              onLevelTap: _isAnimatingProgress ? null : _handleNodeTap,
                              character: SagaCharacter(
                                controller: _character,
                                size: const Size(40, 56),
                                builder: (context, state) => const RepaintBoundary(
                                  child: _PlayerAvatar(),
                                ),
                              ),
                              nodeBuilder: (context, level, layout) {
                                final day1 = level.id + 1;
                                final state = _progress[level.id] ?? LevelCompletionState.locked;
                                final isCurrent = day1 == _currentDay1;
                                final major = isMajorDay1(day1);
                                final burst = _burstAtLevelId == level.id;
                                return _JourneyNode(
                                  key: Key('poc-node-${level.id}'),
                                  day1: day1,
                                  state: state,
                                  isCurrent: isCurrent,
                                  isMajor: major,
                                  burst: burst,
                                );
                              },
                            ),
                            // Décor "premier plan" : le chemin passe visuellement
                            // DERRIÈRE ces deux éléments, pour donner une vraie
                            // sensation de profondeur (forêt + pont de la rivière).
                            Positioned(
                              top: dayYFraction(3) * alongExtent - 46,
                              left: 0,
                              right: 0,
                              child: const IgnorePointer(
                                child: Center(child: _ForegroundCanopy()),
                              ),
                            ),
                            Positioned(
                              top: dayYFraction(8) * alongExtent - 30,
                              left: 0,
                              right: 0,
                              child: const IgnorePointer(
                                child: Center(child: _ForegroundBridge()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _PocDevBar(
              isAnimating: _isAnimatingProgress,
              currentDay1: _currentDay1,
              totalDays: kAuryelPocTotalDays,
              onPlay: () {
                final box = context.findRenderObject();
                double w = 400, h = 700;
                if (box is RenderBox && box.hasSize) {
                  w = box.size.width;
                  h = box.size.height * 0.6;
                }
                _playProgressionDemo(w, h);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. HUD
// ============================================================================

class _PocHud extends StatelessWidget {
  const _PocHud({required this.currentDay1, required this.percent});

  final int currentDay1;
  final int percent;

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
          const Icon(Icons.auto_awesome_rounded, color: AuryelColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: const Key('poc-hud-day'),
                  'Jour $currentDay1 / $kAuryelPocTotalDays',
                  style: const TextStyle(
                    color: AuryelColors.textCream,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: currentDay1 / kAuryelPocTotalDays,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(AuryelColors.gold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            key: const Key('poc-hud-percent'),
            '$percent %',
            style: const TextStyle(
              color: AuryelColors.goldLight,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PocDevBar extends StatelessWidget {
  const _PocDevBar({
    required this.isAnimating,
    required this.currentDay1,
    required this.totalDays,
    required this.onPlay,
  });

  final bool isAnimating;
  final int currentDay1;
  final int totalDays;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final canAdvance = currentDay1 < totalDays;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('poc-dev-play-progress'),
          onPressed: isAnimating || !canAdvance ? null : onPlay,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(
            isAnimating
                ? 'Progression en cours…'
                : canAdvance
                    ? 'DEV — Simuler la progression'
                    : 'Parcours terminé',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AuryelColors.goldLight,
            side: BorderSide(color: AuryelColors.goldLight.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. THÈME DE CHEMIN (parcouru doré vs à venir assombri)
// ============================================================================

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

// ============================================================================
// 5. NŒUDS DE PROGRESSION
// ============================================================================

class _JourneyNode extends StatelessWidget {
  const _JourneyNode({
    super.key,
    required this.day1,
    required this.state,
    required this.isCurrent,
    required this.isMajor,
    required this.burst,
  });

  final int day1;
  final LevelCompletionState state;
  final bool isCurrent;
  final bool isMajor;
  final bool burst;

  @override
  Widget build(BuildContext context) {
    Widget node;
    if (isCurrent) {
      node = _CurrentNodePulse(
        day1: day1,
        icon: isMajor ? iconForMajorDay1(day1) : null,
      );
    } else if (isMajor) {
      node = _MajorNode(day1: day1, state: state, icon: iconForMajorDay1(day1));
    } else {
      node = _NormalNode(state: state);
    }
    if (!burst) return node;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [node, const _NodeBurst()],
    );
  }
}

/// Petit point élégant — la majorité des jours. Pas un simple cercle
/// identique partout : terminé = doré lumineux, futur = terne/noyé.
class _NormalNode extends StatelessWidget {
  const _NormalNode({required this.state});

  final LevelCompletionState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case LevelCompletionState.completed:
        return Center(
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AuryelColors.goldLight, AuryelColors.goldDark],
              ),
              boxShadow: [
                BoxShadow(color: AuryelColors.gold.withValues(alpha: 0.55), blurRadius: 8),
              ],
            ),
          ),
        );
      case LevelCompletionState.locked:
        return Center(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
          ),
        );
      case LevelCompletionState.unlocked:
        return Center(
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AuryelColors.gold.withValues(alpha: 0.85),
            ),
          ),
        );
    }
  }
}

/// Étape majeure (tous les 5 jours) : un vrai petit lieu (icône thématique
/// dans un médaillon), pas juste un cercle plus gros.
class _MajorNode extends StatelessWidget {
  const _MajorNode({required this.day1, required this.state, required this.icon});

  final int day1;
  final LevelCompletionState state;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final done = state == LevelCompletionState.completed;
    final ringColor = done
        ? AuryelColors.goldLight
        : Colors.white.withValues(alpha: 0.22);
    final bg = done
        ? const LinearGradient(colors: [Color(0xFF3A2E14), Color(0xFF241804)])
        : LinearGradient(colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ]);
    final iconColor = done ? AuryelColors.goldLight : Colors.white.withValues(alpha: 0.35);
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: bg,
          border: Border.all(color: ringColor, width: 2),
          boxShadow: done
              ? [BoxShadow(color: AuryelColors.gold.withValues(alpha: 0.35), blurRadius: 12)]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}

/// Étape actuelle : la plus vivante — halo qui respire (2-3s), avatar présent
/// sur le chemin à cet endroit (rendu séparément par `SagaCharacter`).
class _CurrentNodePulse extends StatefulWidget {
  const _CurrentNodePulse({required this.day1, required this.icon});

  final int day1;
  final IconData? icon;

  @override
  State<_CurrentNodePulse> createState() => _CurrentNodePulseState();
}

class _CurrentNodePulseState extends State<_CurrentNodePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pulse.value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 66 + 12 * t,
                height: 66 + 12 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AuryelColors.gold.withValues(alpha: 0.18 * (1 - t) + 0.04),
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3D6), AuryelColors.gold],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AuryelColors.gold.withValues(alpha: 0.6),
                      blurRadius: 10 + 6 * t,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: widget.icon != null
                    ? Icon(widget.icon, size: 20, color: const Color(0xFF241505))
                    : Text(
                        '${widget.day1}',
                        style: const TextStyle(
                          color: Color(0xFF241505),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Petite lueur/particules à l'arrivée d'une progression — brève, discrète.
class _NodeBurst extends StatefulWidget {
  const _NodeBurst();

  @override
  State<_NodeBurst> createState() => _NodeBurstState();
}

class _NodeBurstState extends State<_NodeBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return IgnorePointer(
            child: Opacity(
              opacity: (1 - t).clamp(0, 1),
              child: Container(
                width: 30 + 90 * t,
                height: 30 + 90 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AuryelColors.goldLight.withValues(alpha: 0.8),
                    width: 2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 6. AVATAR — "VOUS ÊTES ICI"
// ============================================================================

/// Orbe Auryel : anneau doré tournant lentement + cœur lumineux respirant.
/// Représente l'utilisateur sur le chemin, à l'étape actuelle.
class _PlayerAvatar extends StatefulWidget {
  const _PlayerAvatar();

  @override
  State<_PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<_PlayerAvatar> with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _breathe.value = 0.5;
      _spin.value = 0;
    } else {
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
      if (!_spin.isAnimating) _spin.repeat();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathe, _spin]),
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
                bottom: 0,
                child: Container(
                  width: 32 + 8 * t,
                  height: 32 + 8 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFE9B0).withValues(alpha: 0.45 * (1 - t) + 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                child: Transform.rotate(
                  angle: _spin.value * 2 * math.pi,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AuryelColors.goldLight.withValues(alpha: 0.75),
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 7,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE9B0), Color(0xFFC9A227)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD87A).withValues(alpha: 0.8),
                        blurRadius: 8 + 4 * t,
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

// ============================================================================
// 7. DÉCOR PREMIER PLAN (profondeur : chemin derrière ces éléments)
// ============================================================================

class _ForegroundCanopy extends StatelessWidget {
  const _ForegroundCanopy();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 70,
      child: CustomPaint(painter: _CanopyPainter()),
    );
  }
}

class _CanopyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0A1810).withValues(alpha: 0.92);
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final cx = size.width * (0.08 + i * 0.21);
      final r = 26.0 + (i.isEven ? 8 : 0);
      path.addOval(Rect.fromCircle(center: Offset(cx, 18), radius: r));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CanopyPainter oldDelegate) => false;
}

class _ForegroundBridge extends StatelessWidget {
  const _ForegroundBridge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 48,
      child: CustomPaint(painter: _BridgePainter()),
    );
  }
}

class _BridgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final deck = Paint()..color = const Color(0xFF120E1E).withValues(alpha: 0.9);
    final rail = Paint()
      ..color = AuryelColors.gold.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final deckRect = Rect.fromLTWH(6, 20, size.width - 12, 10);
    canvas.drawRRect(RRect.fromRectAndRadius(deckRect, const Radius.circular(3)), deck);
    final railPath = Path()
      ..moveTo(6, 12)
      ..quadraticBezierTo(size.width / 2, 2, size.width - 6, 12);
    canvas.drawPath(railPath, rail);
    for (var i = 0; i < 5; i++) {
      final x = 12.0 + i * (size.width - 24) / 4;
      canvas.drawLine(Offset(x, 12), Offset(x, 20), rail);
    }
  }

  @override
  bool shouldRepaint(covariant _BridgePainter oldDelegate) => false;
}

// ============================================================================
// 8. FOND DE MONDE — 6 régions, brouillard de non-découverte
// ============================================================================

class _AuryelWorldBackdrop extends StatefulWidget {
  const _AuryelWorldBackdrop({required this.revealedFraction});

  /// Fraction verticale (0..1) déjà "découverte" (jusqu'à l'étape actuelle).
  final double revealedFraction;

  @override
  State<_AuryelWorldBackdrop> createState() => _AuryelWorldBackdropState();
}

class _AuryelWorldBackdropState extends State<_AuryelWorldBackdrop>
    with TickerProviderStateMixin {
  // Deux contrôleurs partagés et légers pour TOUT le décor animé (scintillement
  // des étoiles, dérive de la brume) — pas un contrôleur par élément.
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _twinkle.value = 0;
      _drift.value = 0;
    } else {
      if (!_twinkle.isAnimating) _twinkle.repeat(reverse: true);
      if (!_drift.isAnimating) _drift.repeat();
    }
  }

  @override
  void dispose() {
    _twinkle.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Couche statique : peinte une fois, transformée (pas repeinte) par
        // l'InteractiveViewer lors du pan/zoom.
        RepaintBoundary(
          child: CustomPaint(
            painter: _AuryelWorldPainter(revealedFraction: widget.revealedFraction),
          ),
        ),
        // Scintillement discret d'un petit nombre d'étoiles (overlay léger).
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _twinkle,
            builder: (context, _) => CustomPaint(
              painter: _TwinkleOverlayPainter(t: _twinkle.value),
            ),
          ),
        ),
        // Brume qui dérive très lentement (translation, pas de repaint lourd).
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, _) => CustomPaint(
              painter: _MistOverlayPainter(t: _drift.value, revealedFraction: widget.revealedFraction),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fond statique complet : 6 régions, décor par région, voile de brouillard
/// sur le monde non découvert.
class _AuryelWorldPainter extends CustomPainter {
  _AuryelWorldPainter({required this.revealedFraction});

  final double revealedFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Ciel de base : bleu-noir -> violet profond -> presque noir.
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF06050C),
          Color(0xFF120C1E),
          Color(0xFF090714),
          Color(0xFF060510),
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), base);

    // Glacis coloré par région, bords adoucis pour fondre l'une dans l'autre.
    for (final region in _kAuryelPocRegions) {
      final top = dayYFraction(region.startDay1) * h;
      final bottom = dayYFraction(region.endDay1) * h;
      final blend = (bottom - top) * 0.5;
      final rect = Rect.fromLTRB(0, top - blend, w, bottom + blend);
      final wash = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            region.washColor.withValues(alpha: 0),
            region.washColor.withValues(alpha: 0.55),
            region.washColor.withValues(alpha: 0.55),
            region.washColor.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.22, 0.78, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, wash);
    }

    _paintStars(canvas, w, h);

    for (final region in _kAuryelPocRegions) {
      final top = dayYFraction(region.startDay1) * h;
      final bottom = dayYFraction(region.endDay1) * h;
      final rect = Rect.fromLTRB(0, top, w, bottom);
      _paintRegionDecor(canvas, rect, region, w, h);
    }

    // Voile du monde non découvert : au-delà de l'étape actuelle, assombri /
    // désaturé, mais jamais totalement masqué (donne envie de continuer).
    final revealedY = revealedFraction * h;
    if (revealedY < h) {
      final veil = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x00050309), Color(0x9A050309)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromLTWH(0, revealedY, w, h - revealedY));
      canvas.drawRect(Rect.fromLTWH(0, revealedY, w, h - revealedY), veil);
    }
    // Chaleur douce sur le monde déjà parcouru.
    if (revealedY > 0) {
      final warmth = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AuryelColors.gold.withValues(alpha: 0.05),
            AuryelColors.gold.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, revealedY));
      canvas.drawRect(Rect.fromLTWH(0, 0, w, revealedY), warmth);
    }
  }

  void _paintStars(Canvas canvas, double w, double h) {
    final rnd = math.Random(7);
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 140; i++) {
      final dx = rnd.nextDouble() * w;
      final dy = rnd.nextDouble() * h;
      final radius = 0.5 + rnd.nextDouble() * 1.3;
      paint.color = Colors.white.withValues(alpha: 0.10 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  void _paintRegionDecor(
    Canvas canvas,
    Rect rect,
    _WorldRegion region,
    double w,
    double h,
  ) {
    switch (region.name) {
      case 'La Forêt Intérieure':
        _forestDecor(canvas, rect, region, w, h);
      case 'La Rivière des Émotions':
        _riverDecor(canvas, rect, region, w, h);
      case 'Le Sanctuaire de l’Ancrage':
        _sanctuaryDecor(canvas, rect, region, w, h);
      case 'La Vallée de la Sérénité':
        _valleyDecor(canvas, rect, region, w, h);
      case 'Le Chemin de l’Équilibre':
        _mountainDecor(canvas, rect, region, w, h);
      case 'L’Ascension':
        _ascensionDecor(canvas, rect, region, w, h);
    }
  }

  void _treeLine(Canvas canvas, Rect rect, Color color, double w, {required bool left}) {
    final rnd = math.Random((rect.top * 3).round() + (left ? 1 : 2));
    final baseX = left ? 0.0 : w;
    final dir = left ? 1.0 : -1.0;
    var y = rect.top;
    final paint = Paint()..color = color.withValues(alpha: 0.85);
    while (y < rect.bottom) {
      final reach = 18 + rnd.nextDouble() * 26;
      final path = Path()
        ..moveTo(baseX, y - 20)
        ..lineTo(baseX + dir * reach, y)
        ..lineTo(baseX, y + 20)
        ..close();
      canvas.drawPath(path, paint);
      y += 34 + rnd.nextDouble() * 20;
    }
  }

  void _forestDecor(Canvas canvas, Rect rect, _WorldRegion region, double w, double h) {
    _treeLine(canvas, rect, region.decorColor, w, left: true);
    _treeLine(canvas, rect, region.decorColor, w, left: false);
    // Clairière au jour majeur (Jour 5).
    final clearingY = dayYFraction(5) * h;
    if (clearingY >= rect.top && clearingY <= rect.bottom) {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          region.ambient.withValues(alpha: 0.18),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: Offset(w / 2, clearingY), radius: 90));
      canvas.drawCircle(Offset(w / 2, clearingY), 90, glow);
    }
    // Petites lumières (lucioles) statiques, discrètes.
    final rnd = math.Random(21);
    final firefly = Paint();
    for (var i = 0; i < 10; i++) {
      final dx = rect.left + rnd.nextDouble() * w;
      final dy = rect.top + rnd.nextDouble() * (rect.height);
      firefly.color = region.ambient.withValues(alpha: 0.35);
      canvas.drawCircle(Offset(dx, dy), 1.6, firefly);
    }
  }

  void _riverDecor(Canvas canvas, Rect rect, _WorldRegion region, double w, double h) {
    // Ruban de rivière qui longe le chemin (même fonction de serpentin).
    final path = Path();
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = rect.top + t * rect.height;
      final continuousIndex = (region.startDay1 - 1) + t * (region.endDay1 - region.startDay1);
      final x = pathXFraction(continuousIndex) * w + 46;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final riverPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [
        region.ambient.withValues(alpha: 0.28),
        const Color(0xFF20395A).withValues(alpha: 0.4),
      ]).createShader(rect);
    canvas.drawPath(path, riverPaint);

    // Rochers épars.
    final rnd = math.Random(33);
    final rockPaint = Paint()..color = region.decorColor;
    for (var i = 0; i < 8; i++) {
      final dx = rect.left + rnd.nextDouble() * w;
      final dy = rect.top + rnd.nextDouble() * rect.height;
      canvas.drawOval(Rect.fromCenter(center: Offset(dx, dy), width: 22, height: 12), rockPaint);
    }
  }

  void _sanctuaryDecor(Canvas canvas, Rect rect, _WorldRegion region, double w, double h) {
    final columnPaint = Paint()..color = region.decorColor.withValues(alpha: 0.9);
    for (var i = 0; i < 4; i++) {
      final x = w * (0.15 + i * 0.23);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 6, rect.top + 30, 12, rect.height - 60),
          const Radius.circular(3),
        ),
        columnPaint,
      );
    }
    // Lanternes (lueur chaude ponctuelle).
    final rnd = math.Random(41);
    for (var i = 0; i < 6; i++) {
      final dx = rect.left + rnd.nextDouble() * w;
      final dy = rect.top + rnd.nextDouble() * rect.height;
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          region.ambient.withValues(alpha: 0.4),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: Offset(dx, dy), radius: 16));
      canvas.drawCircle(Offset(dx, dy), 16, glow);
    }
    // Sanctuaire (jour majeur 15).
    final sanctuaryY = dayYFraction(15) * h;
    if (sanctuaryY >= rect.top && sanctuaryY <= rect.bottom) {
      _drawTempleMotif(canvas, Offset(w / 2, sanctuaryY - 10), region.ambient);
    }
  }

  void _valleyDecor(Canvas canvas, Rect rect, _WorldRegion region, double w, double h) {
    // Ciel plus lumineux : lavis clair additionnel.
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.05);
    canvas.drawRect(rect, light);
    final hillPaint = Paint()..color = region.decorColor.withValues(alpha: 0.75);
    final hills = Path()..moveTo(0, rect.bottom - 40);
    for (var i = 0; i <= 6; i++) {
      final x = w * i / 6;
      final y = rect.bottom - 40 - (i.isEven ? 26 : 8);
      hills.lineTo(x, y);
    }
    hills.lineTo(w, rect.bottom);
    hills.lineTo(0, rect.bottom);
    hills.close();
    canvas.drawPath(hills, hillPaint);
    // Reflet d'eau discret.
    final waterY = dayYFraction(18) * h;
    final water = Paint()
      ..shader = LinearGradient(colors: [
        region.ambient.withValues(alpha: 0.12),
        Colors.transparent,
      ]).createShader(Rect.fromLTWH(0, waterY - 20, w, 40));
    canvas.drawRect(Rect.fromLTWH(0, waterY - 20, w, 40), water);
  }

  void _mountainDecor(Canvas canvas, Rect rect, _WorldRegion region, double w, double h) {
    final peakPaint = Paint()..color = region.decorColor.withValues(alpha: 0.92);
    final peaks = Path()..moveTo(0, rect.top + 60);
    const xs = [0.0, 0.2, 0.4, 0.55, 0.72, 0.9, 1.0];
    const ys = [60.0, 18, 46, 4, 34, 12, 50];
    for (var i = 0; i < xs.length; i++) {
      peaks.lineTo(w * xs[i], rect.top + ys[i]);
    }
    peaks.lineTo(w, rect.top + 60);
    peaks.lineTo(w, rect.top + 90);
    peaks.lineTo(0, rect.top + 90);
    peaks.close();
    canvas.drawPath(peaks, peakPaint);

    // Passage/pont d'altitude (jour majeur 25).
    final passY = dayYFraction(25) * h;
    if (passY >= rect.top && passY <= rect.bottom) {
      final railPaint = Paint()
        ..color = region.ambient.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawLine(Offset(w * 0.3, passY), Offset(w * 0.7, passY), railPaint);
    }
  }

  void _ascensionDecor(Canvas canvas, Rect rect, _WorldRegion region, double w, double h) {
    // Lune, plus proéminente ici.
    final moonCenter = Offset(w * 0.72, rect.top + rect.height * 0.22);
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        region.ambient.withValues(alpha: 0.30),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: moonCenter, radius: 95));
    canvas.drawCircle(moonCenter, 95, glow);
    final moon = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFFFF7E3),
        region.ambient,
      ]).createShader(Rect.fromCircle(center: moonCenter, radius: 28));
    canvas.drawCircle(moonCenter, 28, moon);

    // Temple final au sommet (jour 30).
    final summitY = dayYFraction(30) * h;
    if (summitY >= rect.top && summitY <= rect.bottom) {
      _drawTempleMotif(canvas, Offset(w / 2, summitY - 10), region.ambient, scale: 1.3);
      final burst = Paint()
        ..shader = RadialGradient(colors: [
          region.ambient.withValues(alpha: 0.25),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: Offset(w / 2, summitY), radius: 130));
      canvas.drawCircle(Offset(w / 2, summitY), 130, burst);
    }
  }

  void _drawTempleMotif(Canvas canvas, Offset base, Color glowColor, {double scale = 1.0}) {
    final paint = Paint()..color = const Color(0xFF0D0916).withValues(alpha: 0.92);
    final roofW = 30 * scale;
    final roofH = 32 * scale;
    final roof = Path()
      ..moveTo(base.dx - roofW, base.dy)
      ..lineTo(base.dx, base.dy - roofH)
      ..lineTo(base.dx + roofW, base.dy)
      ..close();
    canvas.drawPath(roof, paint);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(base.dx - roofW * 0.75, base.dy, roofW * 1.5, 28 * scale),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, paint);
    final archPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawArc(
      Rect.fromLTWH(base.dx - 8 * scale, base.dy + 8 * scale, 16 * scale, 20 * scale),
      math.pi,
      math.pi,
      false,
      archPaint,
    );
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        glowColor.withValues(alpha: 0.16),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset(base.dx, base.dy + 6), radius: 46 * scale));
    canvas.drawCircle(Offset(base.dx, base.dy + 6), 46 * scale, glow);
  }

  @override
  bool shouldRepaint(covariant _AuryelWorldPainter oldDelegate) =>
      oldDelegate.revealedFraction != revealedFraction;
}

/// Overlay très léger : scintillement d'une poignée d'étoiles fixes.
class _TwinkleOverlayPainter extends CustomPainter {
  _TwinkleOverlayPainter({required this.t});

  final double t;

  static const _points = [
    Offset(0.18, 0.06),
    Offset(0.62, 0.10),
    Offset(0.35, 0.03),
    Offset(0.80, 0.90),
    Offset(0.22, 0.94),
    Offset(0.55, 0.97),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.5 * t);
    for (final p in _points) {
      canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), 1.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TwinkleOverlayPainter oldDelegate) => oldDelegate.t != t;
}

/// Overlay très léger : 2 nappes de brume qui dérivent lentement.
class _MistOverlayPainter extends CustomPainter {
  _MistOverlayPainter({required this.t, required this.revealedFraction});

  final double t;
  final double revealedFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final bands = [size.height * 0.30, size.height * 0.62];
    for (var i = 0; i < bands.length; i++) {
      final y = bands[i];
      final dx = math.sin((t + i * 0.5) * 2 * math.pi) * 26;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.045)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 34);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5 + dx, y),
          width: size.width * 1.3,
          height: 50,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MistOverlayPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.revealedFraction != revealedFraction;
}

// ============================================================================
// 9. FICHES D'INTERACTION (bottom sheet Auryel — pas de Snackbar)
// ============================================================================

class _PocSheet extends StatelessWidget {
  const _PocSheet({
    super.key,
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

// ============================================================================
// 10. ACCÈS TEMPORAIRE — CE BUILD DE TEST SAMSUNG UNIQUEMENT
// ============================================================================
//
// IMPORTANT : cette constante rend le geste d'ouverture du POC (voir
// home_screen.dart) accessible même en build RELEASE, pour permettre le test
// sur Samsung de ce lot. Elle doit être repassée à `false` (ou re-gardée par
// `kDebugMode`) avant toute release de production réelle — ce n'est PAS une
// porte destinée à rester ouverte.
const bool kAuryelPocTempSamsungTestAccessEnabled = true;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/memory_game.dart';
import '../data/memory_stats.dart';
import '../theme/auryel_theme.dart';

/// Jeu Auryel — jeu de paires (Memory). Le joueur retourne deux cartes ; si
/// elles correspondent elles restent découvertes, sinon elles se retournent.
/// Objectif : retrouver toutes les paires.
///
/// 3 niveaux (8 / 12 / 16 cartes), parties illimitées, statistiques ludiques
/// LOCALES uniquement. AUCUNE récompense en temps de consultation n'est
/// accordée ici (le vrai crédit serveur relève d'un lot backend dédié).
class JeuAuryelScreen extends StatefulWidget {
  const JeuAuryelScreen({
    super.key,
    this.random,
    this.stats,
    this.resolveDelay = const Duration(milliseconds: 700),
    this.enableTicker = true,
    this.clock,
  });

  /// Test : mélange déterministe.
  final Random? random;

  /// Test : store injecté.
  final MemoryStats? stats;

  /// Délai avant qu'une paire non trouvée ne se retourne (0 en test).
  final Duration resolveDelay;

  /// Test : coupe le `Timer.periodic` d'affichage du chrono.
  final bool enableTicker;

  /// Test : horloge déterministe pour le chrono.
  final DateTime Function()? clock;

  @override
  State<JeuAuryelScreen> createState() => _JeuAuryelScreenState();
}

enum _Phase { menu, playing }

class _JeuAuryelScreenState extends State<JeuAuryelScreen> {
  late final MemoryGame _game = MemoryGame(
    random: widget.random,
    resolveDelay: widget.resolveDelay,
    clock: widget.clock,
  );
  late final MemoryStats _stats = widget.stats ?? MemoryStats();

  _Phase _phase = _Phase.menu;
  GameDifficulty _selected = GameDifficulty.facile;
  Timer? _ticker;

  /// Test uniquement : accès au moteur de jeu pour piloter une partie.
  @visibleForTesting
  MemoryGame get debugGame => _game;

  // Résultat consolidé à la victoire (calculé une seule fois).
  bool _resultRecorded = false;
  Duration? _bestTime;
  bool _newRecord = false;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _game.removeListener(_onGameChanged);
    _game.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    if (!mounted) return;
    if (_game.isWon && !_resultRecorded) {
      _resultRecorded = true;
      _ticker?.cancel();
      _recordResult();
    }
    setState(() {});
  }

  Future<void> _recordResult() async {
    final d = _game.difficulty;
    final time = _game.elapsed;
    final isRecord = await _stats.recordCompletion(d, time);
    final best = await _stats.bestTime(d);
    if (!mounted) return;
    setState(() {
      _newRecord = isRecord;
      _bestTime = best;
    });
  }

  void _startGame(GameDifficulty d) {
    _resultRecorded = false;
    _newRecord = false;
    _bestTime = null;
    _selected = d;
    _game.start(d);
    _stats.markStarted(d);
    setState(() => _phase = _Phase.playing);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    if (!widget.enableTicker) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _game.isWon) return;
      setState(() {});
    });
  }

  void _backToMenu() {
    _ticker?.cancel();
    setState(() => _phase = _Phase.menu);
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: _phase == _Phase.menu ? _buildMenu() : _buildGame(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // MENU / choix du niveau
  // -------------------------------------------------------------------------
  Widget _buildMenu() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const PhosphorIcon(
                PhosphorIconsRegular.arrowLeft,
                size: 20,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AURYEL · JEU',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AuryelColors.gold,
              letterSpacing: 3.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Le Jeu Auryel',
            textAlign: TextAlign.center,
            style: AuryelText.display(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Retrouve les paires cachées. Un jeu de mémoire pour ralentir '
            'et revenir à toi.',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 12.5,
              height: 1.4,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'CHOISIS TON NIVEAU',
            style: AuryelText.body(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AuryelColors.gold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          for (final d in GameDifficulty.values) ...[
            _DifficultyCard(
              difficulty: d,
              selected: _selected == d,
              onTap: () => setState(() => _selected = d),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          _GoldButton(label: 'Commencer', onTap: () => _startGame(_selected)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // PARTIE
  // -------------------------------------------------------------------------
  Widget _buildGame() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        _GameHeader(
          elapsedLabel: _mmss(_game.elapsed),
          moves: _game.moves,
          matched: _game.matchedPairs,
          total: _game.totalPairs,
          onQuit: _backToMenu,
          onRestart: () => _startGame(_game.difficulty),
        ),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: _Board(
                  cards: _game.cards,
                  reduceMotion: reduceMotion,
                  onTap: _game.flip,
                ),
              ),
              if (_game.isWon)
                _WinOverlay(
                  time: _mmss(_game.elapsed),
                  moves: _game.moves,
                  bestTime: _bestTime == null ? null : _mmss(_bestTime!),
                  newRecord: _newRecord,
                  onReplay: () => _startGame(_game.difficulty),
                  onChangeLevel: _backToMenu,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.difficulty,
    required this.selected,
    required this.onTap,
  });

  final GameDifficulty difficulty;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${difficulty.label}, ${difficulty.cardCount} cartes',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? AuryelColors.gold.withValues(alpha: 0.14)
                  : AuryelColors.surface.withValues(alpha: 0.55),
              border: Border.all(
                color: selected
                    ? AuryelColors.goldLight.withValues(alpha: 0.8)
                    : AuryelColors.warmBorder,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  selected
                      ? PhosphorIconsFill.circle
                      : PhosphorIconsRegular.circle,
                  size: 16,
                  color: selected
                      ? AuryelColors.goldLight
                      : AuryelColors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  difficulty.label,
                  style: AuryelText.display(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    '${difficulty.cardCount} cartes · '
                    '${difficulty.pairCount} paires',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AuryelText.body(
                      fontSize: 11.5,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameHeader extends StatelessWidget {
  const _GameHeader({
    required this.elapsedLabel,
    required this.moves,
    required this.matched,
    required this.total,
    required this.onQuit,
    required this.onRestart,
  });

  final String elapsedLabel;
  final int moves;
  final int matched;
  final int total;
  final VoidCallback onQuit;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onQuit,
            tooltip: 'Quitter la partie',
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              size: 20,
              color: AuryelColors.textMuted,
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Stat(icon: PhosphorIconsRegular.timer, value: elapsedLabel),
                const SizedBox(width: 16),
                _Stat(icon: PhosphorIconsRegular.handTap, value: '$moves'),
                const SizedBox(width: 16),
                _Stat(
                  icon: PhosphorIconsRegular.cardsThree,
                  value: '$matched/$total',
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRestart,
            tooltip: 'Recommencer',
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowsClockwise,
              size: 18,
              color: AuryelColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(icon, size: 14, color: AuryelColors.gold),
        const SizedBox(width: 5),
        Text(
          value,
          style: AuryelText.body(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textCream,
          ),
        ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.cards,
    required this.reduceMotion,
    required this.onTap,
  });

  final List<MemoryCard> cards;
  final bool reduceMotion;
  final void Function(int slotId) onTap;

  @override
  Widget build(BuildContext context) {
    // 4 colonnes : lisible de 360 à 430 dp pour 8 / 12 / 16 cartes.
    const cols = 4;
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final card = cards[i];
        return _CardTile(
          key: ValueKey('memory-card-${card.slotId}'),
          card: card,
          reduceMotion: reduceMotion,
          onTap: () => onTap(card.slotId),
        );
      },
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    super.key,
    required this.card,
    required this.reduceMotion,
    required this.onTap,
  });

  final MemoryCard card;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showFace = card.revealed || card.matched;
    final face = _Face(
      key: const ValueKey('face'),
      asset: card.faceAsset,
      matched: card.matched,
    );
    const back = _Back(key: ValueKey('back'));

    return Semantics(
      button: !card.matched,
      label: card.matched
          ? 'Carte trouvée'
          : (card.revealed ? 'Carte retournée' : 'Carte face cachée'),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: showFace ? face : back,
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AuryelColors.surfaceLight,
        border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.45)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          MemoryGame.backAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Center(
            child: PhosphorIcon(
              PhosphorIconsRegular.sparkle,
              size: 22,
              color: AuryelColors.gold,
            ),
          ),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({super.key, required this.asset, required this.matched});

  final String asset;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AuryelColors.surface,
        border: Border.all(
          color: matched
              ? AuryelColors.goldLight.withValues(alpha: 0.9)
              : AuryelColors.warmBorder,
          width: matched ? 1.6 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: matched ? 0.55 : 1,
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
              child: PhosphorIcon(
                PhosphorIconsRegular.moon,
                size: 22,
                color: AuryelColors.goldLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WinOverlay extends StatelessWidget {
  const _WinOverlay({
    required this.time,
    required this.moves,
    required this.bestTime,
    required this.newRecord,
    required this.onReplay,
    required this.onChangeLevel,
  });

  final String time;
  final int moves;
  final String? bestTime;
  final bool newRecord;
  final VoidCallback onReplay;
  final VoidCallback onChangeLevel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AuryelColors.backgroundDeep.withValues(alpha: 0.82),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(
                  PhosphorIconsFill.sparkle,
                  size: 34,
                  color: AuryelColors.goldLight,
                ),
                const SizedBox(height: 12),
                Text(
                  'Toutes les paires trouvées',
                  textAlign: TextAlign.center,
                  style: AuryelText.display(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Temps  $time   ·   Coups  $moves',
                  style: AuryelText.body(
                    fontSize: 13,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                if (bestTime != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    newRecord
                        ? 'Nouveau meilleur temps : $bestTime'
                        : 'Meilleur temps : $bestTime',
                    style: AuryelText.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.goldLight,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _GoldButton(label: 'Rejouer', onTap: onReplay),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: onChangeLevel,
                  child: Text(
                    'Changer de niveau',
                    style: AuryelText.body(
                      fontSize: 12.5,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text(
                    label,
                    style: AuryelText.body(
                      fontSize: 14,
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
      ),
    );
  }
}

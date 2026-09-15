import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/memory_api.dart';
import '../data/memory_game.dart';
import '../data/memory_stats.dart';
import '../state/auth_controller.dart';
import '../state/memory_rewards_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';

/// Jeu Auryel — jeu de paires (Memory). Le joueur retourne deux cartes ; si
/// elles correspondent elles restent découvertes, sinon elles se retournent.
/// Objectif : retrouver toutes les paires.
///
/// 3 niveaux (8 / 12 / 16 cartes), parties illimitées. Une partie est OUVERTE
/// puis FERMÉE côté serveur (`/api/app/memory/start` + `/complete`) : le SERVEUR
/// est l'unique autorité pour la récompense (chrono, seuil « moins de
/// 20 / 40 / 80 s »). GROS CHANTIER AURYEL (Prompt 3/5) : la récompense est
/// désormais des ÉTOILES (règle `mini_game_completed`), avec un plafond
/// PARTAGÉ par toute la catégorie mini-jeux (Memory / Suite intuitive /
/// Carte cachée) — une seule récompense par jour, tous jeux confondus. Le
/// chrono affiché ici est purement indicatif. Si le backend n'est pas câblé
/// / joignable, le jeu reste entièrement jouable, sans récompense.
class JeuAuryelScreen extends StatefulWidget {
  const JeuAuryelScreen({
    super.key,
    this.random,
    this.stats,
    this.rewardsController,
    this.resolveDelay = const Duration(milliseconds: 700),
    this.enableTicker = true,
    this.clock,
  });

  /// Test : mélange déterministe.
  final Random? random;

  /// Test : store injecté.
  final MemoryStats? stats;

  /// Test : contrôleur de récompenses injecté. En production, l'écran le
  /// construit depuis `AuthScope.of(context).memoryApi` s'il est câblé.
  final MemoryRewardsController? rewardsController;

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

  MemoryRewardsController? _rewards;
  bool _ownsRewards = false;

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

  // Récompense serveur — uniquement quand une partie serveur a été ouverte.
  String? _gameId;
  bool _finalizingReward = false;
  MemoryCompleteResult? _rewardResult;
  bool _rewardError = false;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onGameChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rewards != null) return;
    if (widget.rewardsController != null) {
      _rewards = widget.rewardsController;
    } else {
      final auth = AuthScope.maybeOf(context);
      final api = auth?.memoryApi;
      if (auth != null && api != null) {
        _rewards = MemoryRewardsController(
          api: api,
          tokenProvider: auth.currentToken,
        );
        _ownsRewards = true;
      }
    }
    if (_rewards != null) {
      _rewards!.addListener(_onRewardsChanged);
      _rewards!.refresh();
    }
  }

  void _onRewardsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _game.removeListener(_onGameChanged);
    _game.dispose();
    _rewards?.removeListener(_onRewardsChanged);
    if (_ownsRewards) _rewards?.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    if (!mounted) return;
    if (_game.isWon && !_resultRecorded) {
      _resultRecorded = true;
      _ticker?.cancel();
      _recordResult();
      _finalizeReward();
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

  /// Ferme la partie serveur et récupère le verdict de récompense. Le body ne
  /// contient QUE `game_id` : c'est le serveur qui calcule le chrono et décide.
  Future<void> _finalizeReward() async {
    final rewards = _rewards;
    final gameId = _gameId;
    if (rewards == null || gameId == null) return;
    setState(() {
      _finalizingReward = true;
      _rewardError = false;
    });
    final res = await rewards.completeGame(gameId);
    if (!mounted) return;
    setState(() {
      _finalizingReward = false;
      _rewardResult = res;
      _rewardError = res == null;
    });
    if (res != null && res.rewardCredited) {
      // GROS CHANTIER AURYEL (Prompt 3/5) — la récompense Memory est
      // désormais des Étoiles (plus du temps) : le header Accueil doit
      // refléter le nouveau solde immédiatement.
      RewardsScope.maybeReadOf(context)?.refresh();
    }
  }

  Future<void> _startGame(GameDifficulty d) async {
    _resultRecorded = false;
    _newRecord = false;
    _bestTime = null;
    _gameId = null;
    _rewardResult = null;
    _rewardError = false;
    _finalizingReward = false;
    _selected = d;

    // Le jeu démarre IMMÉDIATEMENT (aucune attente réseau) : le plateau est
    // jouable tout de suite. La partie serveur est ouverte en parallèle ; son
    // `game_id` sert à la finalisation à la victoire. Le serveur horodate son
    // `started_at` à la réception -> le joueur n'est jamais pénalisé par la
    // latence.
    _game.start(d);
    _stats.markStarted(d);
    _startTicker();
    setState(() => _phase = _Phase.playing);

    final rewards = _rewards;
    if (rewards != null) {
      final session = await rewards.startGame(d.apiDifficulty);
      if (!mounted) return;
      _gameId = session?.gameId;
      // La victoire a pu tomber AVANT la réponse `start` (jeu très rapide) :
      // finaliser maintenant si c'est le cas et pas encore fait.
      if (_gameId != null &&
          _game.isWon &&
          _rewardResult == null &&
          !_finalizingReward) {
        _finalizeReward();
      }
    }
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
    _rewards?.refresh();
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
    final progress = _rewards?.progress;
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
            'Retrouve les paires cachées. Termine vite pour gagner des '
            'Étoiles.',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 12.5,
              height: 1.4,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Une récompense mini-jeu par jour, tous jeux confondus.',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(height: 24),
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
              eligibleToday: progress?.eligibleToday,
              starsReward: progress?.starsReward ?? 0,
              nextResetAt: progress?.nextResetAt,
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
    if (!_game.hasStarted) {
      return Center(
        child: Text(
          'Préparation de la partie…',
          style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
        ),
      );
    }
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
              // CORRECTIF VISUEL — le plateau (8/12/16 cartes) n'occupait que
              // le haut de l'espace disponible, laissant un grand bloc vide
              // en dessous (constaté à l'écran). `Center` + grille non
              // scrollable (contenu toujours fixe et petit) : le plateau se
              // centre verticalement, aucun changement de logique de jeu.
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: _Board(
                    cards: _game.cards,
                    reduceMotion: reduceMotion,
                    onTap: _game.flip,
                  ),
                ),
              ),
              if (_game.isWon) _buildWinLayer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWinLayer() {
    final serverBound =
        _gameId != null ||
        _finalizingReward ||
        _rewardResult != null ||
        _rewardError;
    if (!serverBound) {
      return _WinOverlay(
        time: _mmss(_game.elapsed),
        moves: _game.moves,
        bestTime: _bestTime == null ? null : _mmss(_bestTime!),
        newRecord: _newRecord,
        onReplay: () => _startGame(_game.difficulty),
        onChangeLevel: _backToMenu,
      );
    }
    return _RewardOutcomeOverlay(
      finalizing: _finalizingReward,
      hadError: _rewardError,
      result: _rewardResult,
      difficulty: _game.difficulty,
      time: _mmss(_game.elapsed),
      onReplay: () => _startGame(_game.difficulty),
      onChangeLevel: _backToMenu,
    );
  }
}

// ===========================================================================

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.difficulty,
    required this.selected,
    required this.onTap,
    this.eligibleToday,
    this.starsReward = 0,
    this.nextResetAt,
  });

  final GameDifficulty difficulty;
  final bool selected;
  final VoidCallback onTap;

  /// GROS CHANTIER AURYEL (Prompt 3/5) — PARTAGÉ par les 3 difficultés (une
  /// seule récompense mini-jeux par jour, toute la catégorie confondue) :
  /// `null` tant que la progression n'est pas encore chargée.
  final bool? eligibleToday;
  final int starsReward;
  final String? nextResetAt;

  @override
  Widget build(BuildContext context) {
    final locked = eligibleToday == false;
    final rewardLine = starsReward > 0
        ? 'Moins de ${difficulty.rewardThresholdSeconds} sec · +$starsReward ⭐'
        : 'Moins de ${difficulty.rewardThresholdSeconds} sec';
    final statusLine = locked
        ? _lockedLabel(nextResetAt)
        : (eligibleToday == true ? 'Récompense disponible aujourd’hui' : null);

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${difficulty.label}, ${difficulty.cardCount} cartes, $rewardLine'
          '${statusLine != null ? ', $statusLine' : ''}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                        '${difficulty.cardCount} cartes',
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
                const SizedBox(height: 6),
                Text(
                  rewardLine,
                  style: AuryelText.body(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AuryelColors.goldLight,
                  ),
                ),
                if (statusLine != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    statusLine,
                    style: AuryelText.body(
                      fontSize: 10.5,
                      height: 1.3,
                      color: locked
                          ? AuryelColors.textMuted
                          : AuryelColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _lockedLabel(String? nextEligibleIso) {
    final until = _humanizeUntil(nextEligibleIso);
    return until == null
        ? 'Récompense déjà obtenue'
        : 'Récompense déjà obtenue · à nouveau dans $until';
  }
}

/// « dans 3 j » / « dans 5 h » / « bientôt » à partir d'un ISO-8601, ou `null`.
String? _humanizeUntil(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final diff = dt.difference(DateTime.now());
  if (diff.inSeconds <= 0) return null;
  if (diff.inHours >= 24) {
    final d = (diff.inHours / 24).ceil();
    return '$d j';
  }
  if (diff.inHours >= 1) return '${diff.inHours} h';
  return 'moins d’une heure';
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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

/// Fin de partie SANS récompense serveur (backend non câblé / injoignable) —
/// overlay ludique local, inchangé.
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

/// Fin de partie AVEC verdict serveur : récompense gagnée / temps dépassé /
/// récompense déjà obtenue (cooldown) / partie expirée / non validée. Sobre —
/// aucun confetti, aucune roue, aucun wording financier.
class _RewardOutcomeOverlay extends StatelessWidget {
  const _RewardOutcomeOverlay({
    required this.finalizing,
    required this.hadError,
    required this.result,
    required this.difficulty,
    required this.time,
    required this.onReplay,
    required this.onChangeLevel,
  });

  final bool finalizing;
  final bool hadError;
  final MemoryCompleteResult? result;
  final GameDifficulty difficulty;
  final String time;
  final VoidCallback onReplay;
  final VoidCallback onChangeLevel;

  @override
  Widget build(BuildContext context) {
    final threshold = difficulty.rewardThresholdSeconds;

    late final IconData icon;
    late final String title;
    late final String body;
    String? note;

    if (finalizing) {
      icon = PhosphorIconsRegular.hourglassMedium;
      title = 'Partie terminée';
      body = 'Validation en cours…';
    } else if (result == null || hadError) {
      icon = PhosphorIconsRegular.cloudSlash;
      title = 'Partie terminée';
      body =
          'La récompense n’a pas pu être validée. Ta partie reste jouable, '
          'réessaie plus tard.';
    } else if (result!.rewardCredited) {
      icon = PhosphorIconsFill.sparkle;
      title = 'Bravo';
      body = 'Ta partie est terminée.';
      note = 'Les jeux restent des fonctionnalités de contenu.';
    } else if (result!.isTimeExceeded) {
      icon = PhosphorIconsRegular.timer;
      title = 'Partie terminée';
      body = 'Termine en moins de $threshold secondes pour réussir la partie.';
      note = 'Temps  $time';
    } else if (result!.isDailyLimitReached) {
      icon = PhosphorIconsRegular.checkCircle;
      title = 'Partie terminée';
      body = 'Cette partie est déjà terminée.';
      note = 'Reviens demain pour une nouvelle partie.';
    } else if (result!.isExpired) {
      icon = PhosphorIconsRegular.hourglass;
      title = 'Partie terminée';
      body = 'La partie a expiré avant d’être validée.';
    } else {
      icon = PhosphorIconsRegular.info;
      title = 'Partie terminée';
      body = 'Cette partie n’a pas pu être validée pour une récompense.';
    }

    return Positioned.fill(
      child: ColoredBox(
        color: AuryelColors.backgroundDeep.withValues(alpha: 0.82),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(icon, size: 34, color: AuryelColors.goldLight),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AuryelText.display(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 13,
                    height: 1.5,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    note,
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.goldLight,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (!finalizing) ...[
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

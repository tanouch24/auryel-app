import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/mini_game_api.dart';
import '../state/auth_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';

/// « Carte cachée » — GROS CHANTIER AURYEL (Prompt 3/5). Mini-jeu de mémoire/
/// attention : 3 cartes retournées, une cible brièvement montrée, mélange
/// visuel simple, l'utilisateur retrouve la bonne carte. IMPORTANT :
/// AUCUNE formulation de gain/chance/pari — c'est un jeu de mémoire, jamais
/// un jeu de hasard. Le SERVEUR décide seul de la récompense
/// (`/api/app/minigame/start` + `/finish`).
class HiddenCardScreen extends StatefulWidget {
  const HiddenCardScreen({super.key, this.random, this.miniGameApi});

  /// Test : position cible déterministe.
  final Random? random;

  /// Test : API injectée.
  final MiniGameApi? miniGameApi;

  @override
  State<HiddenCardScreen> createState() => _HiddenCardScreenState();
}

const _kCardCount = 3;
const _kCardSymbol = '🔮';

enum _Phase { reveal, hidden, guessing, result }

class _HiddenCardScreenState extends State<HiddenCardScreen> {
  late final Random _random = widget.random ?? Random();
  late int _targetIndex = _random.nextInt(_kCardCount);
  _Phase _phase = _Phase.reveal;
  int? _guessIndex;
  MiniGameSession? _session;
  MiniGameResult? _result;
  bool _finishing = false;
  Timer? _timer;
  bool _sessionRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `AuthScope.maybeOf` dépend de l'arbre `InheritedWidget` — jamais
    // appelable depuis `initState()`. Démarré UNE SEULE fois.
    if (_sessionRequested) return;
    _sessionRequested = true;
    _startSession();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _phase = _Phase.hidden);
      // « Mélange visuel simple » : une brève pause qui matérialise le
      // mélange avant de rendre les cartes cliquables — jamais un vrai tirage
      // aléatoire supplémentaire (la position cible est fixée dès le départ).
      _timer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _phase = _Phase.guessing);
      });
    });
  }

  Future<void> _startSession() async {
    final auth = AuthScope.maybeOf(context);
    final api = widget.miniGameApi ?? auth?.miniGameApi;
    if (api == null || auth == null) return;
    final token = await auth.currentToken();
    if (token == null || token.isEmpty || !mounted) return;
    try {
      final session = await api.start(bearer: token, gameKey: 'hidden_card');
      if (mounted) setState(() => _session = session);
    } catch (_) {
      /* jeu jouable sans récompense si le backend n'est pas joignable */
    }
  }

  bool get _correct => _guessIndex == _targetIndex;

  void _onTapCard(int index) {
    if (_phase != _Phase.guessing || _finishing) return;
    setState(() => _guessIndex = index);
    _finish();
  }

  /// GROS CHANTIER AURYEL (Prompt 3/5) §14 — récompense la manche RÉELLEMENT
  /// terminée (un choix fait), pas la performance : `finish` est appelé dès
  /// qu'une carte est choisie, juste ou fausse.
  Future<void> _finish() async {
    setState(() {
      _finishing = true;
      _phase = _Phase.result;
    });
    final session = _session;
    final auth = AuthScope.maybeOf(context);
    final api = widget.miniGameApi ?? auth?.miniGameApi;
    if (session == null || api == null || auth == null) {
      setState(() => _finishing = false);
      return;
    }
    final token = await auth.currentToken();
    if (token == null || token.isEmpty) {
      setState(() => _finishing = false);
      return;
    }
    try {
      final result = await api.finish(
        bearer: token,
        sessionId: session.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _finishing = false;
      });
      if (result.awarded) {
        RewardsScope.maybeReadOf(context)?.refresh();
      }
    } catch (_) {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _targetIndex = _random.nextInt(_kCardCount);
      _guessIndex = null;
      _result = null;
      _phase = _Phase.reveal;
    });
    _startSession();
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _phase = _Phase.hidden);
      _timer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _phase = _Phase.guessing);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Row(
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
              ),
              Expanded(child: Center(child: _buildBody())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_phase == _Phase.result) return _buildResult();
    // CORRECTIF VISUEL — les 3 cartes flottaient seules sur le fond noir,
    // impression de grand bloc vide (constaté à l'écran, Samsung). Panneau
    // premium cohérent avec le reste d'Auryel : aucun changement de logique.
    return _GamePanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(
            PhosphorIconsFill.cardsThree,
            size: 26,
            color: AuryelColors.goldLight,
          ),
          const SizedBox(height: 14),
          Text(
            'Carte cachée',
            style: AuryelText.display(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            switch (_phase) {
              _Phase.reveal => 'Repère la carte…',
              _Phase.hidden => 'Les cartes se mélangent…',
              _ => 'Où était la carte ?',
            },
            textAlign: TextAlign.center,
            style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _kCardCount; i++) ...[
                _CardTile(
                  faceUp: _phase == _Phase.reveal && i == _targetIndex,
                  enabled: _phase == _Phase.guessing,
                  onTap: () => _onTapCard(i),
                ),
                if (i != _kCardCount - 1) const SizedBox(width: 16),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    late final String title;
    late final String body;
    if (_finishing) {
      title = 'Manche terminée';
      body = 'Validation en cours…';
    } else if (result == null) {
      title = 'Manche terminée';
      body = _correct
          ? 'Bien joué, tu as retrouvé la bonne carte !'
          : 'Manche terminée — bien tenté !';
    } else if (result.awarded) {
      title = 'Bravo';
      body = 'Tu as gagné ${result.starsAwarded} ⭐.';
    } else if (result.isDailyLimitReached) {
      title = 'Manche terminée';
      body = 'Tu as déjà obtenu la récompense mini-jeu du jour.';
    } else {
      title = 'Manche terminée';
      body = _correct
          ? 'Bien joué, tu as retrouvé la bonne carte !'
          : 'Bien tenté !';
    }
    return _GamePanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            _correct
                ? PhosphorIconsFill.sparkle
                : PhosphorIconsRegular.checkCircle,
            size: 34,
            color: AuryelColors.goldLight,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AuryelText.display(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 13,
              height: 1.5,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          if (!_finishing) ...[
            ElevatedButton(
              onPressed: _restart,
              style: ElevatedButton.styleFrom(
                backgroundColor: AuryelColors.gold,
                foregroundColor: AuryelColors.backgroundDeep,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
              child: const Text('Rejouer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                'Retour',
                style: AuryelText.body(color: AuryelColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Panneau premium partagé par les états jeu/résultat — CORRECTIF VISUEL :
/// avant, le contenu flottait seul sur le fond noir, ce qui donnait
/// l'impression d'un écran vide. Même habillage que `_SectionCard` /
/// `_RewardLine` ailleurs dans Auryel : aucune logique, uniquement de la
/// présentation.
class _GamePanel extends StatelessWidget {
  const _GamePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AuryelColors.surface.withValues(alpha: 0.55),
              AuryelColors.surface.withValues(alpha: 0.25),
            ],
          ),
          border: Border.all(
            color: AuryelColors.goldLight.withValues(alpha: 0.3),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.faceUp,
    required this.enabled,
    required this.onTap,
  });

  final bool faceUp;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: faceUp ? 'Carte visible' : 'Carte cachée',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 82,
            height: 112,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: faceUp ? AuryelColors.goldGradient : null,
              color: faceUp ? null : AuryelColors.surfaceLight,
              border: Border.all(
                color: faceUp
                    ? AuryelColors.goldLight
                    : AuryelColors.warmBorder,
                width: faceUp ? 2 : 1,
              ),
              boxShadow: faceUp
                  ? [
                      BoxShadow(
                        color: AuryelColors.gold.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: faceUp
                ? const Text(_kCardSymbol, style: TextStyle(fontSize: 28))
                : PhosphorIcon(
                    PhosphorIconsRegular.question,
                    size: 24,
                    color: AuryelColors.gold.withValues(alpha: 0.7),
                  ),
          ),
        ),
      ),
    );
  }
}

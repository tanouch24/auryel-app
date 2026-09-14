import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/mini_game_api.dart';
import '../state/auth_controller.dart';
import '../state/rewards_controller.dart';
import '../theme/auryel_theme.dart';

/// « Suite intuitive » — GROS CHANTIER AURYEL (Prompt 3/5). Mini-jeu de
/// mémoire/attention : 4 symboles apparaissent brièvement dans un certain
/// ordre, l'utilisateur les reproduit. Simple, apaisant, 20 s à 1 min.
/// AUCUNE formulation de gain/chance/pari : c'est un jeu de mémoire, pas un
/// pari. Le SERVEUR décide seul de la récompense (`/api/app/minigame/start`
/// + `/finish`) — le chrono/résultat affichés ici sont indicatifs.
class SequenceRecallScreen extends StatefulWidget {
  const SequenceRecallScreen({super.key, this.random, this.miniGameApi});

  /// Test : séquence déterministe.
  final Random? random;

  /// Test : API injectée.
  final MiniGameApi? miniGameApi;

  @override
  State<SequenceRecallScreen> createState() => _SequenceRecallScreenState();
}

const _kSymbols = ['🌙', '⭐', '✨', '🔮'];
const _kSequenceLength = 4;

enum _Phase { showing, input, result }

class _SequenceRecallScreenState extends State<SequenceRecallScreen> {
  late final Random _random = widget.random ?? Random();
  late final List<int> _sequence = List.generate(
    _kSequenceLength,
    (_) => _random.nextInt(_kSymbols.length),
  );

  _Phase _phase = _Phase.showing;
  int _showIndex = -1;
  final List<int> _input = [];
  MiniGameSession? _session;
  MiniGameResult? _result;
  bool _finishing = false;
  Timer? _showTimer;
  bool _sessionRequested = false;

  @override
  void initState() {
    super.initState();
    _playSequence();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `AuthScope.maybeOf` dépend de l'arbre `InheritedWidget` — jamais
    // appelable depuis `initState()`. Démarré UNE SEULE fois.
    if (_sessionRequested) return;
    _sessionRequested = true;
    _startSession();
  }

  Future<void> _startSession() async {
    final auth = AuthScope.maybeOf(context);
    final api = widget.miniGameApi ?? auth?.miniGameApi;
    if (api == null || auth == null) return;
    final token = await auth.currentToken();
    if (token == null || token.isEmpty || !mounted) return;
    try {
      final session = await api.start(bearer: token, gameKey: 'sequence_recall');
      if (mounted) setState(() => _session = session);
    } catch (_) {
      /* jeu jouable sans récompense si le backend n'est pas joignable */
    }
  }

  void _playSequence() {
    var i = 0;
    void step() {
      if (!mounted) return;
      if (i >= _sequence.length) {
        setState(() {
          _showIndex = -1;
          _phase = _Phase.input;
        });
        return;
      }
      setState(() => _showIndex = _sequence[i]);
      _showTimer = Timer(const Duration(milliseconds: 550), () {
        if (!mounted) return;
        setState(() => _showIndex = -1);
        _showTimer = Timer(const Duration(milliseconds: 200), () {
          i++;
          step();
        });
      });
    }

    step();
  }

  void _onTapSymbol(int index) {
    if (_phase != _Phase.input || _finishing) return;
    setState(() => _input.add(index));
    if (_input.length >= _sequence.length) {
      _finish();
    }
  }

  /// GROS CHANTIER AURYEL (Prompt 3/5) §14 — Auryel récompense la
  /// PARTICIPATION/completion d'une manche réelle, pas la performance
  /// hardcore : `finish` est appelé dès que l'utilisateur a reproduit une
  /// séquence COMPLÈTE (juste ou fausse), jamais sur un simple abandon
  /// (fermer l'écran avant la fin ne déclenche jamais `finish`).
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

  bool get _correct =>
      _input.length == _sequence.length &&
      List.generate(_sequence.length, (i) => _input[i] == _sequence[i])
          .every((ok) => ok);

  void _restart() {
    setState(() {
      _sequence
        ..clear()
        ..addAll(
          List.generate(_kSequenceLength, (_) => _random.nextInt(_kSymbols.length)),
        );
      _input.clear();
      _result = null;
      _phase = _Phase.showing;
    });
    _startSession();
    _playSequence();
  }

  @override
  void dispose() {
    _showTimer?.cancel();
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Suite intuitive',
            style: AuryelText.display(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _phase == _Phase.showing
                ? 'Observe l’ordre…'
                : 'Reproduis l’ordre que tu viens de voir.',
            textAlign: TextAlign.center,
            style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
          ),
          const SizedBox(height: 36),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < _kSymbols.length; i++)
                _SymbolTile(
                  symbol: _kSymbols[i],
                  highlighted: _showIndex == i,
                  onTap: () => _onTapSymbol(i),
                  enabled: _phase == _Phase.input,
                ),
            ],
          ),
          const SizedBox(height: 28),
          if (_phase == _Phase.input)
            Text(
              '${_input.length} / ${_sequence.length}',
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.textMuted,
              ),
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
          ? 'Bien joué, tu as retrouvé l’ordre !'
          : 'Manche terminée — pas tout à fait, mais bien tenté !';
    } else if (result.awarded) {
      title = 'Bravo';
      body = 'Tu as gagné ${result.starsAwarded} ⭐.';
    } else if (result.isDailyLimitReached) {
      title = 'Manche terminée';
      body = 'Tu as déjà obtenu la récompense mini-jeu du jour.';
    } else {
      title = 'Manche terminée';
      body = _correct
          ? 'Bien joué, tu as retrouvé l’ordre !'
          : 'Pas tout à fait, mais bien tenté !';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            _correct ? PhosphorIconsFill.sparkle : PhosphorIconsRegular.checkCircle,
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

class _SymbolTile extends StatelessWidget {
  const _SymbolTile({
    required this.symbol,
    required this.highlighted,
    required this.onTap,
    required this.enabled,
  });

  final String symbol;
  final bool highlighted;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Symbole $symbol',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: highlighted ? AuryelColors.goldGradient : null,
              color: highlighted ? null : AuryelColors.surface.withValues(alpha: 0.6),
              border: Border.all(
                color: highlighted
                    ? AuryelColors.goldLight
                    : AuryelColors.warmBorder,
                width: highlighted ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(symbol, style: const TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
  }
}

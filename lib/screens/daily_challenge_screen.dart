import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/auth_controller.dart';
import '../state/memory_rewards_controller.dart';
import '../theme/auryel_theme.dart';
import 'hidden_card_screen.dart';
import 'jeu_auryel_screen.dart';
import 'sequence_recall_screen.dart';

/// « Défi du jour » — GROS CHANTIER AURYEL (Prompt 3/5). Point d'entrée
/// unique vers les 3 mini-jeux Auryel (Memory / Suite intuitive / Carte
/// cachée), qui partagent TOUS la même récompense quotidienne (règle
/// `mini_game_completed`, `award_stars`) : terminer UN SEUL des 3 jeux
/// aujourd'hui suffit à obtenir la récompense du jour ; les 3 restent
/// accessibles ensuite (rejouer est toujours possible, sans re-gagner).
/// Le SERVEUR reste l'unique autorité — ce statut vient de
/// `GET /api/app/memory/progress` (même plafond que Memory, PAS une 2ᵉ
/// source de vérité).
class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key, this.controller});

  /// Test : contrôleur injecté.
  final MemoryRewardsController? controller;

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen>
    with WidgetsBindingObserver {
  MemoryRewardsController? _controller;
  bool _ownsController = false;

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
      final api = auth?.memoryApi;
      if (auth == null || api == null) return;
      _controller = MemoryRewardsController(api: api, tokenProvider: auth.currentToken);
      _ownsController = true;
    }
    _controller!.addListener(_onChange);
    _controller!.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller?.refresh();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onChange);
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  Future<void> _openGame(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    // Retour du jeu : le statut du jour a pu changer (récompense obtenue).
    _controller?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final eligible = c?.eligibleToday;
    final stars = c?.starsReward ?? 0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const SizedBox(height: 4),
                Text(
                  'Défi du jour',
                  style: AuryelText.display(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  stars > 0
                      ? 'Termine un mini-jeu aujourd’hui : +$stars ⭐'
                      : 'Termine un mini-jeu aujourd’hui pour une récompense.',
                  style: AuryelText.body(
                    fontSize: 13,
                    height: 1.4,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                if (eligible == false)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AuryelColors.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AuryelColors.goldLight.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const PhosphorIcon(
                          PhosphorIconsFill.checkCircle,
                          size: 16,
                          color: AuryelColors.goldLight,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Récompense du jour obtenue ✓',
                            style: AuryelText.body(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AuryelColors.goldLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'LES 3 JEUX',
                  style: AuryelText.body(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.gold,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                _GameCard(
                  icon: PhosphorIconsRegular.puzzlePiece,
                  title: 'Le Jeu Auryel',
                  body: 'Retrouve les paires cachées. Trois niveaux, parties '
                      'illimitées.',
                  onTap: () => _openGame(const JeuAuryelScreen()),
                ),
                const SizedBox(height: 12),
                _GameCard(
                  icon: PhosphorIconsRegular.sparkle,
                  title: 'Suite intuitive',
                  body: 'Observe l’ordre des symboles et reproduis-le.',
                  onTap: () => _openGame(const SequenceRecallScreen()),
                ),
                const SizedBox(height: 12),
                _GameCard(
                  icon: PhosphorIconsRegular.cardsThree,
                  title: 'Carte cachée',
                  body: 'Repère la carte, puis retrouve-la après le mélange.',
                  onTap: () => _openGame(const HiddenCardScreen()),
                ),
                const SizedBox(height: 16),
                Text(
                  'Les jeux restent accessibles même après ta récompense du '
                  'jour — pour le plaisir, sans nouveau gain.',
                  style: AuryelText.body(
                    fontSize: 11,
                    height: 1.4,
                    color: AuryelColors.textMuted,
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

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $body',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AuryelColors.surface.withValues(alpha: 0.55),
              border: Border.all(color: AuryelColors.warmBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AuryelColors.gold.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AuryelColors.goldLight.withValues(alpha: 0.5),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: PhosphorIcon(icon, size: 20, color: AuryelColors.goldLight),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AuryelText.body(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textCream,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: AuryelText.body(
                          fontSize: 11.5,
                          height: 1.3,
                          color: AuryelColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const PhosphorIcon(
                  PhosphorIconsRegular.arrowRight,
                  size: 15,
                  color: AuryelColors.goldLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

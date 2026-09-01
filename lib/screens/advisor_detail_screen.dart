import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import 'chat_screen.dart';

/// Fiche complète d'un conseiller : portrait, présentation, vocal, CTA.
/// Même identité premium noir/or que le reste de l'appli.
///
/// UX-B §6 — le CTA du bas est branché :
///   * conseiller déjà préféré  -> « Commencer ma consultation » (ouvre le chat)
///   * autre conseiller         -> « Choisir ce conseiller » (change le préféré,
///     synchro backend `guide` seul, aucun crédit, aucune consultation créée).
class AdvisorDetailScreen extends StatefulWidget {
  const AdvisorDetailScreen({
    super.key,
    required this.advisor,
    required this.selectedAdvisorName,
  });

  final AdvisorInfo advisor;

  /// Nom du conseiller préféré au moment de l'ouverture — sert au rendu initial.
  /// L'action lit toujours l'état LIVE via [AuryelStateScope].
  final String? selectedAdvisorName;

  @override
  State<AdvisorDetailScreen> createState() => _AdvisorDetailScreenState();
}

class _AdvisorDetailScreenState extends State<AdvisorDetailScreen> {
  bool _busy = false;

  AdvisorInfo get _advisor => widget.advisor;

  Future<void> _onCta() async {
    if (_busy) return;
    final state = AuryelStateScope.of(context);
    final isSelected = _advisor.name == state.selectedAdvisor;

    if (isSelected) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(advisor: _advisor)),
      );
      return;
    }
    await _choose(state);
  }

  Future<void> _choose(AuryelState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final consultation = ConsultationScope.maybeReadOf(context);

    // UX-B §7 — une consultation active avec un AUTRE conseiller n'est pas une
    // erreur : elle continue, seul le préféré (prochaine consultation) change.
    final activeOtherId =
        (consultation != null &&
            consultation.hasActiveSession &&
            consultation.active?.advisorId != null &&
            consultation.active!.advisorId.isNotEmpty &&
            consultation.active!.advisorId != _advisor.guideKey)
        ? consultation.active!.advisorId
        : null;

    if (activeOtherId != null) {
      final activeName =
          advisorByGuideKey(activeOtherId)?.name ?? 'ton conseiller';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AuryelColors.surface,
          title: Text(
            'Ta consultation en cours continue',
            style: AuryelText.cardTitle(),
          ),
          content: Text(
            'Ta consultation avec $activeName reste accessible.\n\n'
            '${_advisor.name} deviendra ton conseiller pour ta prochaine '
            'consultation.',
            style: AuryelText.bodySecondary(color: AuryelColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Annuler',
                style: AuryelText.body(color: AuryelColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Choisir ${_advisor.name}',
                style: AuryelText.body(
                  color: AuryelColors.goldLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    final outcome = await state.changeAdvisor(_advisor.name, _advisor.guideKey);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case AdvisorChangeOutcome.synced:
      case AdvisorChangeOutcome.localOnly:
        messenger.showSnackBar(
          SnackBar(
            content: Text('${_advisor.name} est maintenant ton conseiller.'),
          ),
        );
        navigator.popUntil((r) => r.isFirst);
      case AdvisorChangeOutcome.unchanged:
        navigator.popUntil((r) => r.isFirst);
      case AdvisorChangeOutcome.networkFailed:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Connexion impossible — ton conseiller n’a pas été changé. '
              'Réessaie.',
            ),
          ),
        );
      case AdvisorChangeOutcome.unauthorized:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Ta session a expiré. Reconnecte-toi.'),
          ),
        );
        navigator.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = AuryelStateScope.of(context).selectedAdvisor;
    final isSelected = _advisor.name == selectedName;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: PhosphorIcon(
                              PhosphorIconsThin.arrowLeft,
                              size: 22,
                              color: AuryelColors.textMuted,
                            ),
                            splashRadius: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 132,
                        height: 132,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AuryelColors.goldGradient,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            _advisor.assetPath,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(_advisor.name, style: AuryelText.screenTitle()),
                      const SizedBox(height: 6),
                      Text(
                        _advisor.specialty,
                        textAlign: TextAlign.center,
                        style: AuryelText.overline(color: AuryelColors.gold),
                      ),
                      const SizedBox(height: 28),
                      _VoicePlayer(
                        advisorName: _advisor.name,
                        voicePath: _advisor.voicePath,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _advisor.bio,
                        textAlign: TextAlign.left,
                        style: AuryelText.bodyText(),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                child: _GoldCta(
                  label: isSelected
                      ? 'Commencer ma consultation'
                      : 'Choisir ce conseiller',
                  busy: _busy,
                  onTap: _onCta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldCta extends StatelessWidget {
  const _GoldCta({required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AuryelColors.goldGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            AuryelColors.backgroundDeep,
                          ),
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AuryelText.button(),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lecteur du vocal de présentation — design sobre, bouton play or.
class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({required this.advisorName, required this.voicePath});

  final String advisorName;
  final String voicePath;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(AssetSource(widget.voicePath));
    }
    if (mounted) setState(() => _isPlaying = !_isPlaying);
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggle,
              child: Ink(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AuryelColors.goldGradient,
                ),
                child: Center(
                  child: PhosphorIcon(
                    _isPlaying
                        ? PhosphorIconsFill.pause
                        : PhosphorIconsFill.play,
                    size: 20,
                    color: AuryelColors.backgroundDeep,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PRÉSENTATION VOCALE',
                  style: AuryelText.overline(),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AuryelColors.warmBorder,
                    valueColor: const AlwaysStoppedAnimation(AuryelColors.gold),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_format(_position)} / ${_format(_duration)}',
                  style: AuryelText.body(
                    fontSize: 10.5,
                    color: AuryelColors.textMuted,
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

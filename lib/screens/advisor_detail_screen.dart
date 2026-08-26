import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';

/// Fiche complète d'un conseiller : portrait, présentation, vocal, CTA.
/// Même identité premium noir/or que le reste de l'appli.
class AdvisorDetailScreen extends StatelessWidget {
  const AdvisorDetailScreen({
    super.key,
    required this.advisor,
    required this.selectedAdvisorName,
  });

  final AdvisorInfo advisor;
  final String? selectedAdvisorName;

  @override
  Widget build(BuildContext context) {
    final isSelected = advisor.name == selectedAdvisorName;
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
                            advisor.assetPath,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        advisor.name,
                        style: AuryelText.display(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        advisor.specialty,
                        textAlign: TextAlign.center,
                        style: AuryelText.body(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.gold,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _VoicePlayer(
                        advisorName: advisor.name,
                        voicePath: advisor.voicePath,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        advisor.bio,
                        textAlign: TextAlign.left,
                        style: AuryelText.body(
                          fontSize: 14.5,
                          height: 1.55,
                          color: AuryelColors.textSecondary,
                        ),
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
                  onTap: () {},
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
  const _GoldCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

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
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.backgroundDeep,
                    letterSpacing: 0.4,
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
                  style: AuryelText.body(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textMuted,
                    letterSpacing: 1.2,
                  ),
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

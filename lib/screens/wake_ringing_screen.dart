import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/wake_sound_catalog.dart';
import '../data/wake_video.dart';
import '../services/wake_alarm_channel.dart';
import '../theme/auryel_theme.dart';
import '../widgets/wake_video_stage.dart';
import 'wake_after_screen.dart';

/// Écran d'alarme V2 : un MP4 local contient l'image, la musique et la voix.
/// Le réseau n'est utilisé qu'avant l'alarme, lors de la préparation du cache.
class WakeRingingScreen extends StatefulWidget {
  const WakeRingingScreen({
    super.key,
    this.alarmChannel,
    this.now,
    this.testMode = false,
    this.video = WakeVideoCatalog.pilot,
    this.cache,
    this.returnToOnboarding = false,
  });

  final WakeAlarmChannel? alarmChannel;
  final DateTime? now;
  final bool testMode;
  final WakeVideo video;
  final WakeVideoCache? cache;
  final bool returnToOnboarding;

  @override
  State<WakeRingingScreen> createState() => _WakeRingingScreenState();
}

class _WakeRingingScreenState extends State<WakeRingingScreen> {
  late final WakeAlarmChannel _channel =
      widget.alarmChannel ?? MethodChannelWakeAlarm();
  final _videoKey = GlobalKey<WakeVideoStageState>();
  late final _cache = widget.cache ?? WakeVideoCache();
  final _fallbackPlayer = ap.AudioPlayer();
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  bool _acting = false;

  Future<void> _startFallback() async {
    if (_acting) return;
    try {
      final sound = wakeSoundOptions.first;
      await _fallbackPlayer.setReleaseMode(ap.ReleaseMode.loop);
      await _fallbackPlayer.setVolume(0.65);
      await _fallbackPlayer.play(
        ap.AssetSource(sound.assetPath.replaceFirst('assets/', '')),
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    unawaited(_videoKey.currentState?.stop());
    unawaited(_fallbackPlayer.stop());
    unawaited(_fallbackPlayer.dispose());
    _cache.close();
    super.dispose();
  }

  String get _timeLabel =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  Future<void> _stopMedia() async {
    await _videoKey.currentState?.stop();
    try {
      await _fallbackPlayer.stop();
    } catch (_) {}
  }

  Future<void> _turnOff() async {
    if (_acting) return;
    setState(() => _acting = true);
    await _stopMedia();
    await _channel.stopRinging();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WakeAfterScreen(
          pendingContext: 'Je viens de terminer mon réveil Auryel.',
          returnToOnboarding: widget.returnToOnboarding,
        ),
      ),
    );
  }

  Future<void> _snooze() async {
    if (_acting) return;
    setState(() => _acting = true);
    await _stopMedia();
    await _channel.stopRinging();
    if (!widget.testMode) await _channel.snoozeAlarm(minutes: 10);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            _CachedVideoView(
              key: ValueKey(widget.video.id),
              video: widget.video,
              cache: _cache,
              stageKey: _videoKey,
              onError: _startFallback,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.16),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'AURYEL · RÉVEIL',
                      style: AuryelText.body(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.goldLight,
                        letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeLabel,
                      style: AuryelText.display(
                        fontSize: 64,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: 'Éteindre le réveil',
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _acting ? null : _turnOff,
                          child: Ink(
                            width: 112,
                            height: 112,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AuryelColors.goldGradient,
                            ),
                            child: const Icon(
                              Icons.alarm_off_rounded,
                              size: 46,
                              color: AuryelColors.backgroundDeep,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Éteindre',
                      style: AuryelText.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (!widget.testMode)
                      TextButton.icon(
                        onPressed: _acting ? null : _snooze,
                        icon: const PhosphorIcon(
                          PhosphorIconsRegular.clockClockwise,
                          size: 16,
                          color: AuryelColors.textMuted,
                        ),
                        label: Text(
                          'Répéter dans 10 min',
                          style: AuryelText.body(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AuryelColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CachedVideoView extends StatefulWidget {
  const _CachedVideoView({
    super.key,
    required this.video,
    required this.cache,
    required this.stageKey,
    required this.onError,
  });

  final WakeVideo video;
  final WakeVideoCache cache;
  final GlobalKey<WakeVideoStageState> stageKey;
  final Future<void> Function() onError;

  @override
  State<_CachedVideoView> createState() => _CachedVideoViewState();
}

class _CachedVideoViewState extends State<_CachedVideoView> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await widget.cache.prepare(widget.video);
    if (file == null) {
      await widget.onError();
    } else if (mounted) {
      setState(() => _path = file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) return const ColoredBox(color: Colors.black);
    return WakeVideoStage(
      key: widget.stageKey,
      file: File(path),
      onError: widget.onError,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/relaxation_video.dart';
import '../theme/auryel_theme.dart';
import '../widgets/relaxation_video_background.dart';

/// Lecteur vidéo autonome de la Bibliothèque.
///
/// Il réutilise la même surface `video_player` que le Réveil et les
/// méditations existantes, mais ne partage aucun état d'alarme, d'audio ou de
/// récompense. Les vidéos d'ambiance restent muettes par conception.
class RelaxationVideoPlayerScreen extends StatefulWidget {
  const RelaxationVideoPlayerScreen({
    super.key,
    required this.video,
    this.displayTitle,
  });

  final RelaxationVideo video;
  final String? displayTitle;

  @override
  State<RelaxationVideoPlayerScreen> createState() =>
      _RelaxationVideoPlayerScreenState();
}

class _RelaxationVideoPlayerScreenState
    extends State<RelaxationVideoPlayerScreen>
    with WidgetsBindingObserver {
  late final RelaxationVideoSurface _surface = VideoPlayerRelaxationSurface();
  bool _loading = true;
  bool _ready = false;
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final ok = await _surface.load(widget.video.videoUrl);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final started = await _surface.play();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ready = true;
      _playing = started;
    });
  }

  Future<void> _togglePlayback() async {
    if (!_ready) return;
    if (_playing) {
      await _surface.pause();
    } else {
      await _surface.play();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_surface.pause());
    } else if (_playing) {
      unawaited(_surface.play());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _surface.pause();
    _surface.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AuryelColors.backgroundDeep,
        appBar: AppBar(
          title: Text(widget.displayTitle ?? widget.video.title),
          backgroundColor: AuryelColors.backgroundDeep,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _videoSurface(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.displayTitle ?? widget.video.title,
                    style: AuryelText.display(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.textCream,
                    ),
                  ),
                  if (widget.video.category.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.video.category,
                      style: AuryelText.body(color: AuryelColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _ready ? _togglePlayback : null,
                      icon: Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      ),
                      label: Text(_playing ? 'Mettre en pause' : 'Lire'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _videoSurface() {
    if (_failed) {
      return _message(
        'Cette vidéo est momentanément indisponible.',
        action: TextButton(onPressed: _load, child: const Text('Réessayer')),
      );
    }
    if (_loading || !_ready) {
      return const Center(
        child: CircularProgressIndicator(color: AuryelColors.goldLight),
      );
    }
    return _surface.buildView() ??
        _message('La vidéo n’a pas pu être affichée.');
  }

  Widget _message(String text, {Widget? action}) => DecoratedBox(
        decoration: BoxDecoration(
          color: AuryelColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ondemand_video_outlined,
                  color: AuryelColors.goldLight, size: 32),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              ?action,
            ],
          ),
        ),
      );
}

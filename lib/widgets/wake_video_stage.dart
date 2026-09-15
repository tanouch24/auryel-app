import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Lecteur unique du Réveil V2. Le fichier doit déjà être présent localement
/// avant l'ouverture de cet écran ; la piste audio du MP4 reste active.
class WakeVideoStage extends StatefulWidget {
  const WakeVideoStage({
    super.key,
    required this.file,
    this.onReady,
    this.onError,
  });

  final File file;
  final VoidCallback? onReady;
  final VoidCallback? onError;

  @override
  State<WakeVideoStage> createState() => WakeVideoStageState();
}

class WakeVideoStageState extends State<WakeVideoStage> {
  VideoPlayerController? _controller;

  bool get isReady => _controller?.value.isInitialized == true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(widget.file);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(1.0);
      if (!mounted) return;
      setState(() {});
      widget.onReady?.call();
      await controller.play();
    } catch (_) {
      if (mounted) widget.onError?.call();
    }
  }

  Future<void> stop() async {
    try {
      await _controller?.pause();
      await _controller?.seekTo(Duration.zero);
    } catch (_) {}
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final size = controller.value.size;
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

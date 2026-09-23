import 'dart:async';
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
    this.muted = false,
    this.autoplay = true,
  });

  final File file;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final bool muted;
  final bool autoplay;

  @override
  State<WakeVideoStage> createState() => WakeVideoStageState();
}

class WakeVideoStageState extends State<WakeVideoStage> {
  VideoPlayerController? _controller;
  Future<void>? _playbackOperation;
  bool _disposed = false;

  bool get isReady => _controller?.value.isInitialized == true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(widget.file);
      _controller = controller;
      await controller.initialize();
      if (_disposed || !mounted || !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0.0 : 1.0);
      if (_disposed || !mounted || !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      setState(() {});
      widget.onReady?.call();
      if (widget.autoplay) await play();
    } catch (_) {
      if (controller != null && identical(_controller, controller)) {
        _controller = null;
        try {
          await controller.dispose();
        } catch (_) {}
      }
      if (mounted) widget.onError?.call();
    }
  }

  Future<void> _enqueuePlayback(Future<void> Function() operation) {
    final previous = _playbackOperation ?? Future<void>.value();
    final next = previous.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } catch (_) {}
    });
    _playbackOperation = next;
    unawaited(
      next.then((_) {
        if (identical(_playbackOperation, next)) _playbackOperation = null;
      }),
    );
    return next;
  }

  Future<void> stop() => _enqueuePlayback(() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();
    await controller.seekTo(Duration.zero);
    if (mounted) setState(() {});
  });

  Future<void> play() => _enqueuePlayback(() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.play();
    if (mounted) setState(() {});
  });

  Future<void> pause() => _enqueuePlayback(() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.pause();
    if (mounted) setState(() {});
  });

  Future<void> togglePlayback() => _enqueuePlayback(() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  });

  bool get isPlaying => _controller?.value.isPlaying == true;

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    _controller = null;
    final pending = _playbackOperation;
    unawaited(() async {
      try {
        if (pending != null) await pending;
        await controller?.pause();
        await controller?.dispose();
      } catch (_) {}
    }());
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/relaxation_video.dart';
import '../theme/auryel_theme.dart';
import '../widgets/relaxation_video_background.dart';

/// Expérience immersive de la Bibliothèque : une seule page active à la fois,
/// navigation verticale et aucune mécanique sociale.
class RelaxationVideoFeedScreen extends StatefulWidget {
  const RelaxationVideoFeedScreen({
    super.key,
    required this.videos,
    this.initialIndex = 0,
    this.surfaceFactory,
  });

  final List<RelaxationVideo> videos;
  final int initialIndex;
  final RelaxationVideoSurface Function()? surfaceFactory;

  @override
  State<RelaxationVideoFeedScreen> createState() =>
      _RelaxationVideoFeedScreenState();
}

class _RelaxationVideoFeedScreenState extends State<RelaxationVideoFeedScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.videos.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.videos.length - 1),
  );
  late int _activeIndex = widget.videos.isEmpty
      ? 0
      : widget.initialIndex.clamp(0, widget.videos.length - 1);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) {
      return const Scaffold(
        backgroundColor: AuryelColors.backgroundDeep,
        body: Center(
          child: Text('Aucune vidéo n’est disponible pour le moment.'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AuryelColors.backgroundDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            onPageChanged: (index) => setState(() => _activeIndex = index),
            itemCount: widget.videos.length,
            itemBuilder: (context, index) => _ImmersiveVideoPage(
              key: ValueKey(widget.videos[index].videoUrl),
              video: widget.videos[index],
              active: index == _activeIndex,
              surfaceFactory: widget.surfaceFactory,
            ),
          ),
          _TopOverlay(
            onBack: () => Navigator.of(context).pop(),
            position: _activeIndex + 1,
            total: widget.videos.length,
          ),
        ],
      ),
    );
  }
}

class _TopOverlay extends StatelessWidget {
  const _TopOverlay({
    required this.onBack,
    required this.position,
    required this.total,
  });

  final VoidCallback onBack;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundButton(
            icon: Icons.arrow_back_rounded,
            label: 'Retour à la Bibliothèque',
            onPressed: onBack,
          ),
          const Spacer(),
          if (total > 1)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .32),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '$position / $total',
                  style: AuryelText.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textCream,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ImmersiveVideoPage extends StatefulWidget {
  const _ImmersiveVideoPage({
    super.key,
    required this.video,
    required this.active,
    this.surfaceFactory,
  });

  final RelaxationVideo video;
  final bool active;
  final RelaxationVideoSurface Function()? surfaceFactory;

  @override
  State<_ImmersiveVideoPage> createState() => _ImmersiveVideoPageState();
}

class _ImmersiveVideoPageState extends State<_ImmersiveVideoPage>
    with WidgetsBindingObserver {
  late final RelaxationVideoSurface _surface =
      widget.surfaceFactory?.call() ??
      VideoPlayerRelaxationSurface(muted: false);
  bool _loading = true;
  bool _ready = false;
  bool _playing = false;
  bool _failed = false;
  bool _resumeAfterLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_ImmersiveVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(_play());
      } else {
        _playing = false;
        unawaited(_surface.pause());
      }
    }
  }

  Future<void> _load() async {
    final ok = await _surface.load(widget.video.videoUrl);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      _loading = false;
      _ready = true;
    });
    if (widget.active) await _play();
  }

  Future<void> _play() async {
    if (!_ready) return;
    final started = await _surface.play();
    if (mounted) setState(() => _playing = started);
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_playing) {
      await _surface.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      await _play();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _resumeAfterLifecycle = _playing && widget.active;
      _playing = false;
      unawaited(_surface.pause());
    } else if (_resumeAfterLifecycle && widget.active) {
      _resumeAfterLifecycle = false;
      unawaited(_play());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_surface.pause());
    _surface.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: !_loading && _ready && !_failed
              ? _surface.buildView() ?? const SizedBox.shrink()
              : _fallback(),
        ),
      ),
      const IgnorePointer(child: _BottomShade()),
      Positioned(
        left: 24,
        right: 24,
        bottom: 34,
        child: _InfoOverlay(
          video: widget.video,
          playing: _playing,
          ready: _ready,
          progress: _progress,
          onToggle: _toggle,
        ),
      ),
    ],
  );

  double? get _progress {
    final surface = _surface;
    final value = surface is VideoPlayerRelaxationSurface
        ? surface.valueListenable?.value
        : null;
    final duration = value?.duration;
    if (value == null || duration == null || duration.inMilliseconds <= 0) {
      return null;
    }
    return (value.position.inMilliseconds / duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  Widget _fallback() {
    if (_failed) {
      return _CenterMessage(
        icon: Icons.cloud_off_outlined,
        text: 'Cette vidéo est momentanément indisponible.',
        action: TextButton(onPressed: _retry, child: const Text('Réessayer')),
      );
    }
    return const _CenterMessage(
      icon: Icons.waves_outlined,
      text: 'Préparation de ton moment…',
      loading: true,
    );
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    await _surface.load(widget.video.videoUrl);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ready = _surface.isReady;
      _failed = !_ready;
    });
    if (_ready && widget.active) await _play();
  }
}

class _InfoOverlay extends StatelessWidget {
  const _InfoOverlay({
    required this.video,
    required this.playing,
    required this.ready,
    required this.progress,
    required this.onToggle,
  });

  final RelaxationVideo video;
  final bool playing;
  final bool ready;
  final double? progress;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        video.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AuryelText.display(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AuryelColors.textCream,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        video.category.toLowerCase() == 'calm' ? 'Relaxation' : video.category,
        style: AuryelText.body(fontSize: 13, color: AuryelColors.textSecondary),
      ),
      const SizedBox(height: 14),
      if (progress != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: AuryelColors.textCream.withValues(alpha: .28),
            valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
          ),
        ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.center,
        child: _RoundButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: playing ? 'Mettre en pause' : 'Lire',
          onPressed: ready ? onToggle : null,
          large: true,
        ),
      ),
    ],
  );
}

class _BottomShade extends StatelessWidget {
  const _BottomShade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0xD9000000)],
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: Colors.black.withValues(alpha: .38),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(large ? 15 : 10),
          child: Icon(
            icon,
            color: AuryelColors.textCream,
            size: large ? 30 : 24,
          ),
        ),
      ),
    ),
  );
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.icon,
    required this.text,
    this.loading = false,
    this.action,
  });

  final IconData icon;
  final String text;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AuryelColors.backgroundDeep,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AuryelColors.goldLight, size: 48),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(color: AuryelColors.goldLight),
            ),
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}

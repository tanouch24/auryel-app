import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/relaxation_video.dart';

/// Fine abstraction du lecteur vidéo d'ambiance — un SEUL exemplaire par
/// [RelaxationVideoBackground]. Isolée pour être remplaçable en test (aucun
/// canal plateforme). La vidéo est TOUJOURS muette.
abstract class RelaxationVideoSurface {
  /// Charge et prépare [url] (streaming, en boucle, volume 0). Renvoie `true`
  /// si la vidéo est réellement prête à l'affichage. Toute erreur (404, format
  /// non supporté, timeout, réseau) -> `false`, sans exception.
  Future<bool> load(String url);

  Future<void> play();
  Future<void> pause();

  /// Widget de rendu de la frame courante (déjà en `cover`). `null` tant que la
  /// vidéo n'est pas prête ou si elle a échoué.
  Widget? buildView();

  bool get isReady;

  void dispose();
}

/// Implémentation réelle via `package:video_player`. Volume forcé à 0, lecture
/// en boucle, `BoxFit.cover`. En test (`MissingPluginException`) ou si la
/// source est illisible, [load] renvoie `false` sans jamais lever.
class VideoPlayerRelaxationSurface implements RelaxationVideoSurface {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<bool> load(String url) async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      _c = c;
      // Garde-fou : si l'init n'aboutit jamais (plugin absent, décodage KO).
      await c.initialize().timeout(const Duration(seconds: 8));
      if (!c.value.isInitialized || c.value.hasError) {
        await _safeDispose();
        return false;
      }
      await c.setVolume(0); // MUET — le son vient uniquement de l'audio MP3.
      await c.setLooping(true);
      _ready = true;
      return true;
    } catch (_) {
      await _safeDispose();
      return false;
    }
  }

  @override
  Future<void> play() async {
    try {
      await _c?.play();
    } catch (_) {
      /* non bloquant */
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _c?.pause();
    } catch (_) {
      /* non bloquant */
    }
  }

  @override
  Widget? buildView() {
    final c = _c;
    if (!_ready || c == null || !c.value.isInitialized) return null;
    final size = c.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width == 0 ? 1080 : size.width,
        height: size.height == 0 ? 1920 : size.height,
        child: VideoPlayer(c),
      ),
    );
  }

  Future<void> _safeDispose() async {
    _ready = false;
    try {
      await _c?.dispose();
    } catch (_) {
      /* ignore */
    }
    _c = null;
  }

  @override
  void dispose() {
    _ready = false;
    try {
      _c?.dispose();
    } catch (_) {
      /* ignore */
    }
    _c = null;
  }
}

/// Fond visuel d'ambiance pour l'écran de méditation.
///
///  - [video] `null` -> ne rend RIEN (le dégradé de l'écran reste visible) ;
///  - charge UNIQUEMENT la vidéo choisie (jamais tout le catalogue) ;
///  - [active] pilote lecture / pause (aligné sur l'état audio + cycle de vie) ;
///  - échec de chargement -> `SizedBox.shrink()` : fond statique, aucune erreur,
///    l'audio n'est jamais impacté (sous-système séparé) ;
///  - au `dispose`, le contrôleur vidéo est libéré.
class RelaxationVideoBackground extends StatefulWidget {
  const RelaxationVideoBackground({
    super.key,
    required this.video,
    required this.active,
    this.surfaceFactory,
    this.overlayOpacity = 0.62,
  });

  final RelaxationVideo? video;
  final bool active;

  /// Test uniquement : fabrique une [RelaxationVideoSurface] (aucun canal
  /// plateforme). `null` -> implémentation réelle `video_player`.
  final RelaxationVideoSurface Function()? surfaceFactory;

  /// Voile sombre par-dessus la vidéo (lisibilité du texte). 0 = aucun.
  final double overlayOpacity;

  @override
  State<RelaxationVideoBackground> createState() =>
      _RelaxationVideoBackgroundState();
}

class _RelaxationVideoBackgroundState extends State<RelaxationVideoBackground>
    with WidgetsBindingObserver {
  RelaxationVideoSurface? _surface;
  bool _failed = false;
  String? _loadedUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maybeLoad();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La vidéo suit le cycle de vie comme l'audio : suspendue hors premier
    // plan, reprise SEULEMENT si la séance est encore en lecture.
    final s = _surface;
    if (s == null || !s.isReady) return;
    if (state != AppLifecycleState.resumed) {
      unawaited(s.pause());
    } else if (widget.active) {
      unawaited(s.play());
    }
  }

  @override
  void didUpdateWidget(RelaxationVideoBackground old) {
    super.didUpdateWidget(old);
    if (widget.video?.videoUrl != old.video?.videoUrl) {
      _disposeSurface();
      _failed = false;
      _loadedUrl = null;
      _maybeLoad();
    } else if (widget.active != old.active) {
      _applyActive();
    }
  }

  Future<void> _maybeLoad() async {
    final v = widget.video;
    if (v == null || v.videoUrl == _loadedUrl) return;
    final surface =
        widget.surfaceFactory?.call() ?? VideoPlayerRelaxationSurface();
    _surface = surface;
    _loadedUrl = v.videoUrl;
    final ok = await surface.load(v.videoUrl);
    if (!mounted) {
      surface.dispose();
      return;
    }
    setState(() => _failed = !ok);
    if (ok) _applyActive();
  }

  void _applyActive() {
    final s = _surface;
    if (s == null || !s.isReady) return;
    if (widget.active) {
      unawaited(s.play());
    } else {
      unawaited(s.pause());
    }
  }

  void _disposeSurface() {
    _surface?.dispose();
    _surface = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeSurface();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _surface;
    final view = (widget.video == null || _failed) ? null : s?.buildView();
    if (view == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        view,
        if (widget.overlayOpacity > 0)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: widget.overlayOpacity),
            ),
          ),
      ],
    );
  }
}

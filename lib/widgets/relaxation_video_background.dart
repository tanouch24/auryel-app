import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/relaxation_video.dart';
import '../theme/auryel_theme.dart';

/// Fine abstraction du lecteur vidéo d'ambiance — un SEUL exemplaire par
/// [RelaxationVideoStage]. Isolée pour être remplaçable en test (aucun canal
/// plateforme). Le volume est choisi par l'hôte : les visuels d'ambiance des
/// méditations audio restent muets, tandis que le lecteur immersif peut lire
/// la piste native du MP4.
abstract class RelaxationVideoSurface {
  /// Charge et prépare [url] (streaming, en boucle, `mixWithOthers`).
  /// Renvoie `true` si la vidéo est réellement prête à l'affichage. Toute
  /// erreur (404, format non supporté, timeout, réseau) -> `false`, sans
  /// exception. NE TOUCHE JAMAIS le lecteur audio.
  Future<bool> load(String url);

  /// Démarre la lecture. Renvoie `true` quand la lecture a RÉELLEMENT
  /// commencé (confirmation effective), `false` sinon (pas de contrôleur
  /// prêt, échec plateforme). Sert de signal pour la mission « Prends ton
  /// temps » (voir [RelaxationVideoStage.onStarted]) — jamais pour l'audio.
  Future<bool> play();
  Future<void> pause();

  /// Widget de rendu de la frame courante (déjà en `cover`). `null` tant que la
  /// vidéo n'est pas prête ou si elle a échoué.
  Widget? buildView();

  bool get isReady;

  void dispose();
}

/// Capacité optionnelle : les surfaces qui peuvent exposer l'état natif du
/// lecteur permettent au feed immersif de détecter la fin du média. Les
/// doubles de test et les surfaces historiques n'ont pas à l'implémenter.
abstract class RelaxationVideoCompletionSurface
    implements RelaxationVideoSurface {
  ValueListenable<VideoPlayerValue>? get valueListenable;
}

/// Implémentation réelle via `package:video_player`.
///
///  - `VideoPlayerOptions(mixWithOthers: true)` : sur Android, le lecteur vidéo
///    ne demande PAS le focus audio exclusif -> l'audio MP3 (audioplayers) n'est
///    JAMAIS interrompu / dél-duck / mis en pause quand la vidéo démarre.
///  - le volume est configurable : muet pour les habillages audio historiques,
///    son natif pour le lecteur immersif.
///  - En test (`MissingPluginException`) ou source illisible : [load] -> `false`.
class VideoPlayerRelaxationSurface implements RelaxationVideoCompletionSurface {
  VideoPlayerRelaxationSurface({this.muted = true});

  final bool muted;
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  Future<bool> load(String url) async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _c = c;
      await c.initialize().timeout(const Duration(seconds: 8));
      if (!c.value.isInitialized || c.value.hasError) {
        await _safeDispose();
        return false;
      }
      await c.setVolume(muted ? 0.0 : 1.0);
      await c.setLooping(false);
      _ready = true;
      return true;
    } catch (_) {
      await _safeDispose();
      return false;
    }
  }

  @override
  Future<bool> play() async {
    final c = _c;
    if (c == null || !_ready) return false;
    try {
      await c.play();
      return true;
    } catch (_) {
      return false;
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

  @override
  ValueListenable<VideoPlayerValue>? get valueListenable => _c;

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

/// SCÈNE VIDÉO — élément PRINCIPAL de l'écran de méditation (plus un fond
/// décoratif). Rendue dans une zone dédiée dimensionnée par le parent
/// (`BoxFit.cover`, coins premium). La vidéo est **toujours muette** et
/// **totalement indépendante de l'audio** : ce widget n'a AUCUNE référence au
/// lecteur MP3.
///
///  - [video] `null` / échec / pas encore prête -> affiche [fallback] (même
///    empreinte, aucun saut de mise en page), l'audio n'est jamais impacté ;
///  - charge UNIQUEMENT la vidéo choisie ;
///  - [active] pilote lecture / pause de LA VIDÉO uniquement ;
///  - cycle de vie : arrière-plan -> pause vidéo ; retour -> reprise SI [active] ;
///  - au `dispose`, le `VideoPlayerController` est libéré.
class RelaxationVideoStage extends StatefulWidget {
  const RelaxationVideoStage({
    super.key,
    required this.video,
    required this.active,
    this.surfaceFactory,
    this.fallback,
    this.caption,
    this.onStarted,
    this.onFailed,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  final RelaxationVideo? video;
  final bool active;

  /// Arrondi de la scène. `BorderRadius.zero` pour un rendu PLEIN ÉCRAN
  /// bord-à-bord (lecteur immersif) ; la valeur par défaut couvre les
  /// usages existants en scène « carte » (coins premium).
  final BorderRadius borderRadius;

  /// Test uniquement : fabrique une [RelaxationVideoSurface] (aucun canal
  /// plateforme). `null` -> implémentation réelle `video_player`.
  final RelaxationVideoSurface Function()? surfaceFactory;

  /// Affiché quand aucune vidéo n'est rendue (absente, en cours de chargement,
  /// ou en échec). Occupe la même zone -> pas de saut visuel.
  final Widget? fallback;

  /// Légende posée en bas de la scène (titre de la méditation), sur un léger
  /// dégradé — présentation « lecteur média ».
  final String? caption;

  /// Appelé quand la vidéo vient RÉELLEMENT de démarrer sa lecture
  /// (confirmation effective, pas un simple tap). Sert de signal pour la
  /// mission « Prends ton temps » — ce widget n'a et n'aura jamais de
  /// référence à l'audio, il expose seulement le fait.
  final VoidCallback? onStarted;

  /// Appelé quand la vidéo choisie a définitivement échoué (chargement OU
  /// tentative de lecture). Purement informatif : ce widget ne décide
  /// d'aucun repli — l'hôte fait ce qu'il veut de ce signal (aucune mission
  /// n'y est plus rattachée : « Prends ton temps » n'écoute que [onStarted]).
  final VoidCallback? onFailed;

  @override
  State<RelaxationVideoStage> createState() => _RelaxationVideoStageState();
}

class _RelaxationVideoStageState extends State<RelaxationVideoStage>
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
    // Cycle de vie de LA VIDÉO uniquement — jamais l'audio.
    final s = _surface;
    if (s == null || !s.isReady) return;
    if (state != AppLifecycleState.resumed) {
      unawaited(s.pause());
    } else if (widget.active) {
      unawaited(s.play());
    }
  }

  @override
  void didUpdateWidget(RelaxationVideoStage old) {
    super.didUpdateWidget(old);
    // CHANGEMENT DE VISUEL : on remplace SEULEMENT le contrôleur vidéo.
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
    // PRÉCHARGEMENT (feed méditation) — si la surface fournie par
    // [RelaxationVideoStage.surfaceFactory] est DÉJÀ prête (chargée en avance
    // pendant que la page précédente jouait), on NE relance PAS un
    // chargement réseau : la frame déjà décodée est conservée telle quelle,
    // c'est tout l'intérêt du préchargement (démarrage quasi instantané).
    final ok = surface.isReady ? true : await surface.load(v.videoUrl);
    if (!mounted) {
      surface.dispose();
      return;
    }
    setState(() => _failed = !ok);
    if (ok) {
      _applyActive();
    } else {
      widget.onFailed?.call();
    }
  }

  void _applyActive() {
    final s = _surface;
    if (s == null || !s.isReady) return;
    if (widget.active) {
      unawaited(_playAndNotify(s));
    } else {
      unawaited(s.pause());
    }
  }

  Future<void> _playAndNotify(RelaxationVideoSurface s) async {
    final started = await s.play();
    if (!mounted) return;
    if (started) {
      widget.onStarted?.call();
    } else {
      // Chargée mais `play()` a échoué à démarrer réellement : même
      // traitement qu'un échec de chargement, pour ne jamais bloquer l'hôte
      // derrière une vidéo qui ne jouera pas.
      widget.onFailed?.call();
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

    if (view == null) {
      return widget.fallback ?? const SizedBox.expand();
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          view,
          // Léger dégradé bas -> lisibilité de la légende (présentation média).
          if (widget.caption != null && widget.caption!.isNotEmpty)
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
              ),
            ),
          if (widget.caption != null && widget.caption!.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Text(
                widget.caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AuryelText.display(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../data/intro_video_store.dart';
import '../theme/auryel_theme.dart';

/// Vidéo d'introduction Auryel — jouée UNE fois, avant le tout premier
/// onboarding (cf. [IntroGate]). Autoplay, plein écran, son actif, contrôles
/// masqués.
///
/// À la fin naturelle (détection robuste : `isCompleted` OU
/// `position >= duration` OU minuteur de secours), sur « Passer », ou en cas
/// d'erreur : on marque la vidéo « vue » puis on enchaîne sur [onDone] — une
/// seule navigation, jamais de blocage sur la dernière frame.
///
/// Rendu : la vidéo source est horizontale (720×416) et l'écran est portrait.
/// Pour éviter deux gros aplats haut/bas, on empile :
///   1. la vidéo agrandie en `cover` + flou fort + léger assombrissement (fond)
///   2. la vidéo entière en `contain`, ratio conservé (avant, jamais coupée)
class IntroVideoScreen extends StatefulWidget {
  const IntroVideoScreen({
    super.key,
    required this.onDone,
    this.store,
    this.assetPath = 'assets/videos/auryel_intro.mp4',
  });

  /// Appelé exactement une fois, après avoir marqué la vidéo comme vue.
  final VoidCallback onDone;

  final IntroVideoStore? store;
  final String assetPath;

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen> {
  late final IntroVideoStore _store = widget.store ?? IntroVideoStore();
  VideoPlayerController? _controller;

  /// Secours si l'init n'aboutit jamais (plugin absent en test, décodage KO).
  Timer? _initWatchdog;

  /// Secours si la fin de lecture n'émet aucun signal fiable (Android).
  Timer? _endTimer;

  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _initWatchdog = Timer(const Duration(seconds: 5), () {
      final c = _controller;
      if (!_finishing && (c == null || !c.value.isInitialized)) _finish();
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final c = VideoPlayerController.asset(widget.assetPath);
      _controller = c;
      c.addListener(_onTick);
      await c.initialize();
      await c.setLooping(false);
      await c.setVolume(1);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _initWatchdog?.cancel();
      // Minuteur de fin : durée réelle + marge. Se déclenche même si aucun
      // événement « terminé » n'arrive du plugin.
      _endTimer = Timer(
        c.value.duration + const Duration(milliseconds: 400),
        () {
          if (!_finishing) _finish();
        },
      );
      setState(() {});
      await c.play();
    } catch (_) {
      _finish();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (introPlaybackFinished(
      isCompleted: c.value.isCompleted,
      hasError: c.value.hasError,
      position: c.value.position,
      duration: c.value.duration,
    )) {
      _finish();
    }
  }

  /// Idempotent : marque la vidéo vue puis enchaîne, une seule fois.
  void _finish() {
    if (_finishing) return;
    _finishing = true;
    _initWatchdog?.cancel();
    _endTimer?.cancel();
    _controller?.removeListener(_onTick);
    try {
      unawaited(_controller?.pause().catchError((_) {}));
    } catch (_) {
      /* contrôleur non initialisé */
    }
    unawaited(_store.markSeen());
    // Enchaîner de façon FIABLE : quand la vidéo se termine, l'app peut être
    // totalement au repos -> `addPostFrameCallback` ne se déclenche jamais
    // (aucune frame planifiée). Un microtask, lui, s'exécute toujours, juste
    // après la pile d'appels courante (jamais en plein build : `_finish` vient
    // d'un Timer / listener / tap).
    Future<void>.microtask(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _initWatchdog?.cancel();
    _endTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final size = ready ? c.value.size : const Size(16, 9);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Immersif le temps de la vidéo ; réappliqué automatiquement au retour.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AuryelColors.backgroundDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AuryelColors.backgroundDeep,
        body: Container(
          decoration: const BoxDecoration(
            gradient: AuryelColors.backgroundGradient,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready) ...[
                // 1) FOND : vidéo agrandie (cover) + flou + assombrissement,
                //    pour que le haut/bas prolonge la vidéo au lieu de former
                //    deux gros rectangles sombres.
                _CoverVideo(controller: c, size: size),
                const ColoredBox(color: Color(0x33000000)),
                // 2) AVANT : vidéo entière, ratio conservé, jamais coupée.
                Center(
                  child: AspectRatio(
                    aspectRatio: size.width / size.height,
                    child: VideoPlayer(c),
                  ),
                ),
              ] else
                const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AuryelColors.goldLight,
                      ),
                    ),
                  ),
                ),
              // « Passer » — toujours au-dessus, sous la barre de statut.
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: AuryelColors.textCream,
                        backgroundColor: AuryelColors.backgroundDeep.withValues(
                          alpha: 0.4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        'Passer',
                        style: AuryelText.body(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textCream,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Détection PURE « la lecture est terminée » — testable sans plugin.
///
/// Robuste sur Android : ne se fie PAS à `!isPlaying` seul. Vrai si le plugin
/// signale `isCompleted`, si la tête de lecture a atteint la fin (dernière
/// frame), ou si le contrôleur est en erreur. Faux tant que la durée est nulle
/// (pas encore initialisé).
bool introPlaybackFinished({
  required bool isCompleted,
  required bool hasError,
  required Duration position,
  required Duration duration,
}) {
  if (hasError) return true;
  if (isCompleted) return true;
  if (duration <= Duration.zero) return false;
  return position >= duration - const Duration(milliseconds: 80);
}

/// Vidéo en fond : `cover` (remplit tout l'écran, déborde), légèrement
/// sur-dimensionnée puis floutée fort. Même contrôleur que la couche avant.
class _CoverVideo extends StatelessWidget {
  const _CoverVideo({required this.controller, required this.size});

  final VideoPlayerController controller;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: 30,
          sigmaY: 30,
          tileMode: TileMode.clamp,
        ),
        child: Transform.scale(
          scale: 1.12,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
  }
}

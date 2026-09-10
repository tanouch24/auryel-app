import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/wellbeing_api.dart';
import '../data/content_repository.dart';
import '../data/daily_mission_tracker.dart';
import '../data/meditation_audio.dart';
import '../data/meditation_catalog.dart';
import '../data/meditation_item.dart';
import '../data/relaxation_video.dart';
import '../data/relaxation_video_selector.dart';
import '../state/auth_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/main_nav_scope.dart';
import '../widgets/relaxation_video_background.dart';
import '../widgets/relaxation_visual_picker.dart';

/// Lecteur d'une séance « Ton Moment ». Ouvert depuis la bibliothèque
/// ([MeditationLibraryScreen]) avec une séance précise ([item]), ou sans
/// [item] -> rotation calendaire « Ton Moment du jour » (comportement
/// historique). Lecteur complet (lecture / pause / reprise / progression),
/// mission « Moment » validée UNIQUEMENT sur une écoute réellement aboutie
/// (fin naturelle ou ≥ 90 %). Un visuel d'ambiance MUET est choisi
/// automatiquement au lancement ; « Choisir le visuel » permet d'en
/// sélectionner un autre SANS jamais toucher à l'audio.
///
/// Aucune promesse médicale. Aucune récompense en temps de consultation.
///
/// Cycle de vie audio (une seule source audible dans Auryel) :
///  - on quitte l'onglet  -> pause ;
///  - app en arrière-plan  -> pause ;
///  - retour au premier plan -> AUCUNE reprise automatique ;
///  - jamais d'autoplay à l'ouverture.
class MeditationScreen extends StatefulWidget {
  const MeditationScreen({
    super.key,
    this.item,
    this.audioOverride,
    this.catalog = const MeditationCatalog(),
    this.now,
    this.missionTracker,
    this.wellbeingApi,
    this.videoSelector,
    this.videoSurfaceFactory,
  });

  /// Séance à jouer, choisie dans la bibliothèque. `null` -> l'écran retombe
  /// sur « Ton Moment du jour » (rotation calendaire, serveur -> cache ->
  /// embarqué), comportement historique inchangé.
  final MeditationItem? item;

  /// Test uniquement : lecteur injecté (aucun canal plateforme en test).
  final MeditationAudio? audioOverride;
  final MeditationCatalog catalog;
  final DateTime? now;
  final DailyMissionTracker? missionTracker;

  /// Sélecteur de vidéo d'ambiance (aléatoire injectable + anti-répétition).
  /// `null` -> instance par défaut. Injecté en test pour un choix déterministe.
  final RelaxationVideoSelector? videoSelector;

  /// Test uniquement : fabrique la surface vidéo (aucun canal plateforme).
  final RelaxationVideoSurface Function()? videoSurfaceFactory;

  /// Parcours bien-être : sync serveur de la mission `moment` (aucune trace
  /// serveur propre à la méditation). Injecté en test ; en production, lu via
  /// `AuthScope.of(context).wellbeingApi`. `null` -> sync ignorée (le tracker
  /// local reste la coche visible, hors ligne inclus).
  final WellbeingApi? wellbeingApi;

  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

enum _PlayStatus { idle, playing, paused, done, unavailable }

class _MeditationScreenState extends State<MeditationScreen>
    with WidgetsBindingObserver {
  late final MeditationAudio _audio =
      widget.audioOverride ?? AudioPlayersMeditationAudio();
  late final DailyMissionTracker _missions =
      widget.missionTracker ?? DailyMissionTracker();

  /// Séance affichée. Si [MeditationScreen.item] est fourni (ouverture depuis la
  /// bibliothèque), c'est lui — définitif. Sinon : catalogue EMBARQUÉ instantané
  /// puis remplacé une fois si le [ContentRepository] résout la séance du jour
  /// distante (serveur -> cache).
  late MeditationItem _item =
      widget.item ?? widget.catalog.momentOfDay(widget.now ?? DateTime.now());
  bool _contentResolved = false;

  late final RelaxationVideoSelector _videoSelector =
      widget.videoSelector ?? RelaxationVideoSelector();

  /// Catalogue distant des visuels d'ambiance résolu pour cette séance
  /// (serveur -> cache -> vide). Sert le sélecteur « Choisir le visuel » SANS
  /// initialiser aucun `VideoPlayerController` : seule la vidéo retenue est
  /// streamée. Vide -> bouton « Choisir le visuel » masqué, fond statique.
  List<RelaxationVideo> _availableVideos = const [];

  /// Vidéo d'ambiance choisie pour CETTE séance (une seule, préchargée à la
  /// demande). `null` = aucune vidéo compatible / catalogue vide -> fond
  /// statique. N'influe JAMAIS sur l'audio.
  RelaxationVideo? _video;

  final List<StreamSubscription<dynamic>> _subs = [];

  _PlayStatus _status = _PlayStatus.idle;
  Duration _elapsed = Duration.zero;
  Duration _total = Duration.zero;
  bool _onThisTab = true;
  bool _momentMarked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subs.add(_audio.onPosition.listen(_onPosition));
    _subs.add(
      _audio.onDuration.listen((d) {
        if (mounted) setState(() => _total = d);
      }),
    );
    _subs.add(_audio.onComplete.listen((_) => _onComplete()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _audio.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Résolution UNE fois de la séance du jour distante (serveur -> cache ->
    // embarqué). L'embarqué reste affiché tant que la résolution n'a pas
    // abouti ; si aucune séance n'est jouable, l'écran garde son état propre
    // (« bientôt disponible ») sans tenter de lire un asset manquant.
    if (!_contentResolved) {
      _contentResolved = true;
      final content = ContentScope.maybeOf(context);
      if (content != null) {
        if (widget.item != null) {
          // Séance fournie par la bibliothèque : on ne résout que le visuel.
          _resolveAmbianceVideo(content);
        } else {
          content
              .momentOfDay(widget.now ?? DateTime.now())
              .then((it) {
                if (it != null && mounted && it.id != _item.id) {
                  setState(() => _item = it);
                }
              })
              .whenComplete(() {
                if (mounted) _resolveAmbianceVideo(content);
              });
        }
      }
    }

    final idx = MainNavScope.maybeOf(context)?.currentIndex;
    final onTab = idx == null || idx == kTabMeditation;
    if (onTab == _onThisTab) return;
    _onThisTab = onTab;
    // On quitte l'onglet -> on suspend. On y revient -> on NE relance PAS.
    if (!onTab && _status == _PlayStatus.playing) _pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _status == _PlayStatus.playing) {
      _pause();
    }
    // Retour au premier plan : aucune reprise automatique (volontaire).
  }

  void _onPosition(Duration p) {
    if (!mounted) return;
    setState(() => _elapsed = p);
    // Complétion « significative » : ≥ 90 % de la durée connue.
    final total = _total.inMilliseconds > 0
        ? _total.inMilliseconds
        : _item.duration.inMilliseconds;
    if (total > 0 && p.inMilliseconds >= total * 0.9) {
      _markMomentDone();
    }
  }

  void _onComplete() {
    if (!mounted) return;
    setState(() {
      _status = _PlayStatus.done;
      if (_total > Duration.zero) _elapsed = _total;
    });
    _markMomentDone();
  }

  /// Idempotent : le tracker est déjà « une fois par jour », et [_momentMarked]
  /// évite de le ré-appeler à chaque tick au-delà de 90 %.
  Future<void> _markMomentDone() async {
    if (_momentMarked) return;
    _momentMarked = true;
    await _missions.markDone(DailyMissionTracker.moment);
    // PARCOURS BIEN-ÊTRE — la mission `moment` n'a AUCUNE trace serveur propre :
    // on l'enregistre (1 fois / jour côté serveur). Fire-and-forget, toutes les
    // erreurs absorbées : la coche locale reste la source d'affichage, la
    // méditation ne crédite jamais de temps par elle-même.
    unawaited(_syncServerMoment());
  }

  Future<void> _syncServerMoment() async {
    if (!mounted) return;
    final auth = AuthScope.maybeOf(context);
    final api = widget.wellbeingApi ?? auth?.wellbeingApi;
    if (api == null || auth == null) return;
    try {
      final token = await auth.currentToken();
      if (token == null || token.isEmpty) return;
      await api.recordMission(bearer: token, missionId: 'moment');
    } catch (_) {
      /* progression serveur non bloquante */
    }
  }

  /// Choisit UNE vidéo d'ambiance compatible avec la séance courante (au
  /// hasard, anti-répétition). Entièrement non bloquant : toute erreur laisse
  /// [_video] à `null` -> fond statique. L'audio n'est jamais concerné.
  Future<void> _resolveAmbianceVideo(ContentRepository content) async {
    try {
      final catalog = await content.relaxationVideos();
      if (!mounted) return;
      setState(() => _availableVideos = catalog);
      if (catalog.isEmpty) return;
      final picked = await _videoSelector.pick(
        catalog,
        meditationCategory: _item.category.name,
      );
      if (mounted && picked != null && _video == null) {
        setState(() => _video = picked);
      }
    } catch (_) {
      /* pas de vidéo -> fond statique, jamais bloquant */
    }
  }

  /// « Aléatoire » dans le sélecteur : re-tire un visuel compatible au hasard
  /// (anti-répétition conservée). Aucun impact audio.
  Future<void> _pickRandomVisual() async {
    if (_availableVideos.isEmpty) return;
    final picked = await _videoSelector.pick(
      _availableVideos,
      meditationCategory: _item.category.name,
    );
    if (mounted && picked != null) setState(() => _video = picked);
  }

  /// Choix manuel d'un visuel : on remplace UNIQUEMENT le visuel. L'audio
  /// (source, position, état lecture/pause) n'est jamais touché — le
  /// [RelaxationVideoBackground] dispose l'ancien contrôleur, charge le
  /// nouveau (volume 0, looping), et le démarre si l'audio joue.
  void _selectVisual(RelaxationVideo v) {
    if (_video?.slug == v.slug) return;
    setState(() => _video = v);
  }

  Future<void> _openVisualPicker() async {
    if (_availableVideos.isEmpty) return;
    final choice = await showRelaxationVisualPicker(
      context,
      videos: _availableVideos,
      currentSlug: _video?.slug,
    );
    if (choice == null || !mounted) return;
    if (choice.isRandom) {
      await _pickRandomVisual();
    } else if (choice.video != null) {
      _selectVisual(choice.video!);
    }
  }

  Future<void> _onPrimaryTap() async {
    switch (_status) {
      case _PlayStatus.idle:
      case _PlayStatus.unavailable:
        await _start();
      case _PlayStatus.playing:
        await _pause();
      case _PlayStatus.paused:
        await _resume();
      case _PlayStatus.done:
        await _start(); // rejouer depuis le début
    }
  }

  Future<void> _start() async {
    _elapsed = Duration.zero;
    // `playbackSource` = URL distante si exploitable, sinon chemin d'asset.
    // Une séance sans aucune source lisible -> `play` renvoie `false` -> état
    // « bientôt disponible » (jamais de tentative de lecture d'asset manquant).
    final ok = await _audio.play(_item.playbackSource);
    if (!mounted) return;
    setState(
      () => _status = ok ? _PlayStatus.playing : _PlayStatus.unavailable,
    );
  }

  Future<void> _pause() async {
    await _audio.pause();
    if (!mounted) return;
    setState(() => _status = _PlayStatus.paused);
  }

  Future<void> _resume() async {
    await _audio.resume();
    if (!mounted) return;
    setState(() => _status = _PlayStatus.playing);
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusText {
    switch (_status) {
      case _PlayStatus.idle:
        return 'Prends quelques minutes pour toi.';
      case _PlayStatus.playing:
        return 'Respire. Laisse la voix te guider.';
      case _PlayStatus.paused:
        return 'En pause — reprends quand tu veux.';
      case _PlayStatus.done:
        return 'Moment terminé. Reviens quand tu en as besoin.';
      case _PlayStatus.unavailable:
        return 'Ce moment arrive très bientôt en audio.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total > Duration.zero ? _total : _item.duration;
    final progress = total.inMilliseconds > 0
        ? (_elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final playing = _status == _PlayStatus.playing;

    // Hauteur de la SCÈNE VIDÉO : élément principal de l'écran, dimensionné
    // pour être immédiatement identifiable comme le média.
    final screenH = MediaQuery.sizeOf(context).height;
    final stageH = (screenH * 0.46).clamp(180.0, 440.0);

    final placeholder = _StagePlaceholder(
      category: _item.category,
      playing: playing,
    );

    final stage = SizedBox(
      key: const Key('meditation-video-stage'),
      height: stageH,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: AuryelColors.surface,
          border: Border.all(
            color: AuryelColors.goldLight.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: _video != null
              ? RelaxationVideoStage(
                  video: _video,
                  active: playing,
                  surfaceFactory: widget.videoSurfaceFactory,
                  caption: _item.title,
                  fallback: placeholder,
                )
              : placeholder,
        ),
      ),
    );

    final controls = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.item != null ? 'Méditation' : 'Ton Moment du jour',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _item.category.label.toUpperCase(),
            style: AuryelText.body(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AuryelColors.gold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AuryelText.display(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          if (_item.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _item.description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AuryelText.body(
                fontSize: 12,
                height: 1.35,
                color: AuryelColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AuryelColors.warmBorder.withValues(alpha: 0.6),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AuryelColors.goldLight,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _mmss(_elapsed),
                style: AuryelText.body(
                  fontSize: 11,
                  color: AuryelColors.textMuted,
                ),
              ),
              Text(
                _mmss(total),
                style: AuryelText.body(
                  fontSize: 11,
                  color: AuryelColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PlayButton(playing: playing, onTap: _onPrimaryTap),
          const SizedBox(height: 10),
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: AuryelText.body(fontSize: 12, color: AuryelColors.textMuted),
          ),
          // Action SECONDAIRE, discrète : ne concurrence jamais Play/Pause.
          // Masquée s'il n'y a aucun visuel distant disponible.
          if (_availableVideos.isNotEmpty) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _openVisualPicker,
              icon: const PhosphorIcon(
                PhosphorIconsRegular.image,
                size: 15,
                color: AuryelColors.goldLight,
              ),
              label: Text(
                'Choisir le visuel',
                style: AuryelText.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.goldLight,
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (Navigator.of(context).canPop())
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Retour',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: const PhosphorIcon(
                      PhosphorIconsRegular.arrowLeft,
                      size: 20,
                      color: AuryelColors.textMuted,
                    ),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AURYEL · MÉDITATION',
                    style: AuryelText.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.gold,
                      letterSpacing: 3.2,
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: stage,
            ),
            Expanded(child: controls),
          ],
        ),
      ),
    );
  }
}

/// État de la SCÈNE quand aucune vidéo n'est rendue (pas de visuel dispo, en
/// cours de chargement, ou échec). Même empreinte que la vidéo -> aucun saut.
/// L'audio n'est jamais concerné par cet état.
class _StagePlaceholder extends StatelessWidget {
  const _StagePlaceholder({required this.category, required this.playing});

  final MeditationCategory category;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Medallion(category: category, playing: playing),
            const SizedBox(height: 14),
            Text(
              'Visuel apaisant',
              style: AuryelText.body(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textMuted,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion({required this.category, required this.playing});

  final MeditationCategory category;
  final bool playing;

  IconData get _icon {
    switch (category) {
      case MeditationCategory.respiration:
        return PhosphorIconsRegular.wind;
      case MeditationCategory.detente:
        return PhosphorIconsRegular.leaf;
      case MeditationCategory.sommeil:
        return PhosphorIconsRegular.moonStars;
      case MeditationCategory.recentrage:
        return PhosphorIconsRegular.compass;
      case MeditationCategory.lacherPrise:
        return PhosphorIconsRegular.feather;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuryelColors.surfaceLight, AuryelColors.surface],
        ),
        border: Border.all(
          color: AuryelColors.goldLight.withValues(alpha: playing ? 0.85 : 0.4),
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: PhosphorIcon(_icon, size: 44, color: AuryelColors.goldLight),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Mettre en pause' : 'Lancer le moment',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuryelColors.goldGradient,
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 40,
              color: AuryelColors.backgroundDeep,
            ),
          ),
        ),
      ),
    );
  }
}

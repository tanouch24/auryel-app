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
import '../state/wellbeing_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/feed_page_scope.dart';
import '../widgets/main_nav_scope.dart';
import '../widgets/relaxation_video_background.dart';

/// Lecteur d'une séance « Ton Moment ». Ouvert depuis la bibliothèque
/// ([MeditationLibraryScreen]) avec une séance précise ([item]), ou sans
/// [item] -> rotation calendaire « Ton Moment du jour » (comportement
/// historique). Lecteur complet (lecture / pause / reprise / progression /
/// précédent / suivant).
///
/// MISSION « Prends ton temps » — règle produit définitive : validée
/// UNIQUEMENT quand une vidéo de relaxation commence RÉELLEMENT à être lue
/// (confirmation effective du démarrage vidéo, jamais au simple tap). Le
/// démarrage de l'audio, à lui seul, NE COCHE JAMAIS cette mission — aucun
/// repli. Si aucune vidéo ne peut démarrer (catalogue vide, hors ligne,
/// échec de chargement ou de lecture), la mission reste NON cochée pour la
/// séance. Un seul marquage par jour (idempotent), persistant.
///
/// Un visuel d'ambiance MUET est choisi automatiquement au lancement — TOUJOURS
/// automatique désormais (feed méditation) : aucune sélection manuelle.
///
/// Aucune promesse médicale. Aucune récompense en temps de consultation.
///
/// Cycle de vie audio (une seule source audible dans Auryel) :
///  - on quitte l'onglet  -> pause ;
///  - app en arrière-plan  -> pause ;
///  - retour au premier plan -> AUCUNE reprise automatique.
///
/// CORRECTIF UX FINAL — délai perçu au tap dans la bibliothèque : un tap sur
/// une fiche de [MeditationLibraryScreen] ouvre désormais l'écran avec
/// [autoplayOnOpen] à `true`, ce qui lance l'audio IMMÉDIATEMENT (dès
/// [State.initState], sans attendre le chargement complet du fichier —
/// `audioplayers` diffuse en flux). C'est l'UNIQUE façon d'obtenir un
/// autoplay à l'ouverture ; partout ailleurs (dont la rotation calendaire
/// « Ton Moment du jour »), le comportement historique « jamais d'autoplay »
/// reste strictement inchangé.
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
    this.initialVideo,
    this.videoResolvedExternally = false,
    this.autoplayOnOpen = false,
    this.showCatalogNavigation = true,
  });

  /// Séance à jouer, choisie dans la bibliothèque. `null` -> l'écran retombe
  /// sur « Ton Moment du jour » (rotation calendaire, serveur -> cache ->
  /// embarqué), comportement historique inchangé.
  final MeditationItem? item;

  /// CORRECTIF UX FINAL — `true` UNIQUEMENT depuis un tap explicite sur une
  /// fiche de [MeditationLibraryScreen] : lance l'audio IMMÉDIATEMENT à
  /// l'ouverture (dès [State.initState], sans attendre un premier tap sur
  /// Play), pour supprimer le temps mort perçu au tap dans la bibliothèque.
  /// `false` par défaut PARTOUT ailleurs (dont la rotation calendaire « Ton
  /// Moment du jour ») : comportement historique « jamais d'autoplay à
  /// l'ouverture » strictement inchangé pour ces cas.
  final bool autoplayOnOpen;

  /// FEED MÉDITATION — `false` UNIQUEMENT quand cet écran est une page du
  /// feed vertical ([MeditationFeedScreen]) : masque les boutons « précédent
  /// / suivant » (skip de catalogue), la navigation s'y fait exclusivement
  /// par swipe vertical, dans l'ordre mélangé anti-répétition du feed — les
  /// garder actifs permettrait de contourner cet ordre (retour possible à une
  /// séance déjà vue). `true` par défaut PARTOUT ailleurs (bibliothèque, «
  /// Ton Moment du jour ») : comportement historique inchangé.
  final bool showCatalogNavigation;

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

  /// CORRECTIF « lecture synchronisée » — visuel déjà choisi ET préchargé en
  /// avance par [MeditationFeedScreen] (avec une surface déjà prête fournie
  /// via [videoSurfaceFactory]) : utilisé directement, sans nouvelle
  /// sélection interne (qui redéclencherait un chargement réseau et
  /// annulerait tout l'intérêt du préchargement). `null` -> comportement
  /// historique : sélection + chargement automatiques via
  /// [ContentRepository] une fois l'écran monté.
  final RelaxationVideo? initialVideo;

  /// CORRECTIF « lecture synchronisée » — `true` UNIQUEMENT depuis le feed :
  /// le choix du visuel (avec ou sans vidéo utilisable au final) a déjà été
  /// tranché définitivement par [MeditationFeedScreen] (bornée par ses
  /// propres tentatives). Dans ce cas, cet écran ne relance JAMAIS sa propre
  /// résolution interne (`_resolveAmbianceVideo`) : un succès tardif de
  /// celle-ci ferait réapparaître une vidéo plusieurs secondes après que
  /// l'audio a démarré — exactement le bug corrigé ici. `false` par défaut
  /// PARTOUT ailleurs (bibliothèque, « Ton Moment du jour ») : comportement
  /// historique inchangé.
  final bool videoResolvedExternally;

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
  /// demande, ou fournie déjà prête via [MeditationScreen.initialVideo]).
  /// `null` = aucune vidéo compatible / catalogue vide -> fond statique.
  /// N'influe JAMAIS sur l'audio.
  late RelaxationVideo? _video = widget.initialVideo;

  /// Visuels ayant RÉELLEMENT échoué à charger/démarrer cette session — évite
  /// de retenter indéfiniment le même fichier cassé. Voir [_onVideoFailed] :
  /// un catalogue non vide ne doit JAMAIS laisser l'écran bloqué sur le repli
  /// statique si un AUTRE visuel du catalogue peut, lui, être lu.
  final Set<String> _failedVideoSlugs = {};
  int _videoRetryCount = 0;
  static const _maxVideoRetries = 2;

  final List<StreamSubscription<dynamic>> _subs = [];

  _PlayStatus _status = _PlayStatus.idle;
  Duration _elapsed = Duration.zero;
  Duration _total = Duration.zero;
  bool _onThisTab = true;
  bool _momentMarked = false;

  /// État « actif » de la VIDÉO — distinct de [_status] (état du MP3). Suit
  /// normalement le MP3 (démarre/pause avec lui), MAIS un changement de
  /// visuel (« Choisir le visuel ») force la vidéo à jouer IMMÉDIATEMENT,
  /// même si le MP3 est en pause ou n'a jamais démarré — sans jamais changer
  /// le MP3 (position, lecture/pause) : voir `_selectVisual`/
  /// `_pickRandomVisual`.
  bool _videoActive = false;

  /// Contrôles (en-tête, infos, progression, précédent/play/suivant, «
  /// Choisir le visuel ») — comportement de lecteur vidéo moderne : visibles
  /// à l'ouverture, disparaissent en fondu après [_controlsAutoHideDelay]
  /// sans interaction, un tap sur la vidéo bascule l'affichage. La vidéo,
  /// elle, reste TOUJOURS visible plein écran.
  bool _controlsVisible = true;
  Timer? _hideTimer;

  static const _controlsAutoHideDelay = Duration(seconds: 4);
  static const _controlsFadeDuration = Duration(milliseconds: 220);

  /// Catalogue ordonné pour précédent/suivant : liste distante résolue
  /// (même source que [MeditationLibraryScreen]) si disponible, sinon
  /// [MeditationCatalog.all] embarqué. Toujours utilisable, même hors ligne.
  List<MeditationItem> _catalogItems = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Repli embarqué immédiat -> précédent/suivant fonctionnent dès l'ouverture,
    // même hors ligne ; remplacé une fois si un catalogue distant résout.
    _catalogItems = widget.catalog.all;
    _subs.add(_audio.onPosition.listen(_onPosition));
    _subs.add(
      _audio.onDuration.listen((d) {
        if (mounted) setState(() => _total = d);
      }),
    );
    _subs.add(_audio.onComplete.listen((_) => _onComplete()));
    // Contrôles visibles à l'ouverture -> le délai d'auto-hide démarre tout
    // de suite, comme sur un vrai lecteur vidéo.
    _scheduleAutoHide();
    // CORRECTIF UX FINAL — lecture lancée IMMÉDIATEMENT quand demandé
    // explicitement ([autoplayOnOpen]), sans attendre le premier tap ni le
    // chargement complet du fichier (`audioplayers` diffuse en flux, aucun
    // téléchargement bloquant). Aucun `await` avant : cet appel ne retarde
    // jamais la navigation ni le premier rendu de l'écran, déjà terminés à ce
    // stade.
    if (widget.autoplayOnOpen) unawaited(_start());
  }

  @override
  void didUpdateWidget(covariant MeditationScreen old) {
    super.didUpdateWidget(old);
    // CORRECTIF UX « sans spinner ni replay manuel » — dans le feed, cette
    // page peut être construite AVANT que son visuel ne soit prêt (l'audio,
    // lui, démarre immédiatement quand même : jamais de tap requis). Le feed
    // reconstruit alors ce widget (MÊME clé) dès qu'un visuel devient
    // disponible : on le reprend ICI, réactivement — un simple champ `late`
    // ne l'aurait capturé qu'une fois, au tout premier montage, et un visuel
    // résolu après coup n'aurait alors plus jamais été repris.
    if (widget.videoResolvedExternally &&
        _video == null &&
        widget.initialVideo != null &&
        widget.initialVideo != old.initialVideo) {
      setState(() => _video = widget.initialVideo);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    // CORRECTIF « double dispose » — dans le feed, cet audio est CRÉÉ ET
    // POSSÉDÉ par `MeditationFeedScreen` (partagé via `audioOverride`,
    // réutilisé le temps que la page reste dans la fenêtre ±1) : lui seul le
    // dispose. Le disposer ICI EN PLUS aurait planté le lecteur réel
    // (`AudioPlayer`/`audioplayers`) une 2ᵉ fois — observé en conditions
    // réelles (Samsung) via des `PlatformException`/`AudioPlayer has been
    // disposed` non rattrapées. Seul l'audio créé PAR CET ÉCRAN LUI-MÊME
    // (usage historique hors feed, `audioOverride` absent) est disposé ici.
    if (widget.audioOverride == null) _audio.dispose();
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
          // Séance fournie par la bibliothèque : on ne résout que le visuel
          // — SAUF si le feed a déjà tranché (voir `videoResolvedExternally`).
          if (!widget.videoResolvedExternally) _resolveAmbianceVideo(content);
        } else {
          content
              .momentOfDay(widget.now ?? DateTime.now())
              .then((it) {
                if (it != null && mounted && it.id != _item.id) {
                  setState(() => _item = it);
                }
              })
              .whenComplete(() {
                if (mounted && !widget.videoResolvedExternally) {
                  _resolveAmbianceVideo(content);
                }
              });
        }
        _resolveCatalog(content);
      }
    }

    final idx = MainNavScope.maybeOf(context)?.currentIndex;
    final onTab = idx == null || idx == kTabMeditation;
    // FEED MÉDITATION — en plus de l'onglet, cette séance doit aussi être la
    // page ACTIVE du feed vertical (voir `FeedPageScope`) pour être
    // considérée « à l'écran ». Absent (écran ouvert seul, hors feed) ->
    // toujours actif : comportement historique inchangé.
    final feedScope = FeedPageScope.maybeOf(context);
    final onFeedPage = feedScope?.isActive ?? true;
    final onScreen = onTab && onFeedPage;
    if (onScreen == _onThisTab) return;
    _onThisTab = onScreen;
    if (!onScreen && _status == _PlayStatus.playing) {
      // On quitte l'onglet/la page -> on suspend.
      _pause();
    } else if (onScreen && feedScope != null) {
      // FEED MÉDITATION UNIQUEMENT — cette page (re)devient la page active du
      // feed (swipe de retour, ou activation différée d'une page déjà
      // préparée en voisine) : démarrage/reprise AUTOMATIQUE, à la différence
      // du comportement historique hors feed (jamais de reprise automatique
      // au simple retour au premier plan / à l'onglet, volontairement
      // inchangé ci-dessus quand `feedScope` est `null`).
      if (_status == _PlayStatus.idle || _status == _PlayStatus.unavailable) {
        unawaited(_start());
      } else if (_status == _PlayStatus.paused) {
        unawaited(_resume());
      }
    }
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
  }

  void _onComplete() {
    if (!mounted) return;
    setState(() {
      _status = _PlayStatus.done;
      if (_total > Duration.zero) _elapsed = _total;
      _videoActive = false;
    });
  }

  /// (Re)démarre le délai avant disparition des contrôles. Annule tout
  /// délai précédent — jamais deux timers en parallèle.
  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsAutoHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// Tap simple sur la vidéo : bascule l'affichage des contrôles. Ne touche
  /// JAMAIS à la vidéo ni à l'audio — uniquement l'interface superposée.
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleAutoHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// Toute interaction avec un contrôle (lecture, précédent/suivant, choix
  /// du visuel…) garde les contrôles visibles et relance le délai
  /// d'auto-hide — jamais de disparition en pleine interaction.
  void _keepControlsVisible() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleAutoHide();
  }

  /// SEUL déclencheur de la mission « Prends ton temps » : la vidéo vient
  /// RÉELLEMENT de démarrer sa lecture (confirmation effective du player
  /// vidéo). Le démarrage de l'audio, à lui seul, ne coche JAMAIS cette
  /// mission — si aucune vidéo ne peut démarrer (catalogue vide, hors ligne,
  /// échec de chargement ou de lecture), la mission reste NON cochée.
  void _onVideoStarted() => _markMomentDone();

  /// Le visuel choisi a échoué (chargement OU tentative de lecture) : on ne
  /// laisse JAMAIS l'écran bloqué sur le repli statique si le catalogue
  /// distant contient un AUTRE visuel valide — on retente automatiquement,
  /// dans la limite de [_maxVideoRetries] (jamais de boucle infinie si
  /// plusieurs fichiers sont cassés). Aucun impact sur le MP3 ; la mission
  /// « Prends ton temps » n'est de toute façon jamais déclenchée ici — seul
  /// un futur [_onVideoStarted] RÉEL sur le visuel de secours la validerait.
  void _onVideoFailed() {
    final failedSlug = _video?.slug;
    if (failedSlug != null) _failedVideoSlugs.add(failedSlug);
    if (!mounted || _videoRetryCount >= _maxVideoRetries) return;
    final candidates = _availableVideos
        .where((v) => !_failedVideoSlugs.contains(v.slug))
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final next = _videoSelector.choose(
      candidates,
      meditationCategory: _item.category.name,
    );
    if (next == null) return;
    _videoRetryCount++;
    setState(() => _video = next);
  }

  /// Idempotent : le tracker est déjà « une fois par jour », et [_momentMarked]
  /// évite de le ré-appeler à chaque tick au-delà de 90 %.
  Future<void> _markMomentDone() async {
    if (_momentMarked) return;
    _momentMarked = true;
    await _missions.markDone(DailyMissionTracker.moment);
    // PARCOURS BIEN-ÊTRE — enregistrement serveur (1 fois / jour, idempotent).
    // Fire-and-forget, toutes les erreurs absorbées : la coche locale reste
    // la source d'affichage immédiate, la méditation ne crédite jamais de
    // temps par elle-même.
    unawaited(_syncServerMoment());
  }

  /// AUDIT ACCUEIL/PARCOURS — passe PAR l'instance PARTAGÉE de
  /// [WellbeingController] quand elle est disponible (`WellbeingScope`,
  /// câblée dans main()) : sa `notifyListeners()` propage IMMÉDIATEMENT vers
  /// Accueil ET « Mon parcours bien-être », sans qu'aucun des deux n'ait
  /// besoin de rouvrir l'écran. Repli sur l'appel direct à [WellbeingApi]
  /// (comportement historique) UNIQUEMENT si aucun scope n'est câblé (tests
  /// isolés qui injectent [MeditationScreen.wellbeingApi] sans
  /// [WellbeingScope]).
  Future<void> _syncServerMoment() async {
    if (!mounted) return;
    final shared = WellbeingScope.maybeReadOf(context);
    if (shared != null) {
      try {
        await shared.recordMission('moment');
      } catch (_) {
        /* progression serveur non bloquante */
      }
      return;
    }
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

  /// Résout le catalogue distant (même source que [MeditationLibraryScreen])
  /// pour précédent/suivant. Non bloquant : le repli embarqué déjà posé dans
  /// [initState] reste utilisable tant que/si cette résolution échoue.
  Future<void> _resolveCatalog(ContentRepository content) async {
    try {
      final list = await content.meditations();
      if (!mounted || list.isEmpty) return;
      setState(() => _catalogItems = _dedupMeditations(list));
    } catch (_) {
      /* le repli embarqué reste utilisable */
    }
  }

  /// 1 AUDIO = 1 FICHE : même règle de déduplication que la bibliothèque
  /// (par `id`, puis titre), pour que précédent/suivant parcourent EXACTEMENT
  /// la même liste que ce que la bibliothèque a affiché.
  static List<MeditationItem> _dedupMeditations(List<MeditationItem> src) {
    final seen = <String>{};
    final out = <MeditationItem>[];
    for (final m in src) {
      final key = m.id.isNotEmpty ? m.id : m.title;
      if (seen.add(key)) out.add(m);
    }
    return out;
  }

  int get _currentIndex => _catalogItems.indexWhere((m) => m.id == _item.id);

  bool get _canGoPrevious => _currentIndex > 0;

  bool get _canGoNext =>
      _currentIndex >= 0 && _currentIndex < _catalogItems.length - 1;

  /// Change de séance SANS jamais toucher au visuel choisi (sauf nécessité
  /// technique réelle : aucune ici — le visuel vidéo reste le même). Réinitialise
  /// strictement l'AUDIO (nouvelle piste = nouvelle position à zéro) PUIS la
  /// démarre AUTOMATIQUEMENT : précédent/suivant doivent enchaîner comme un
  /// vrai lecteur, sans repasser par Play. Aucun changement à la mission
  /// « Prends ton temps » : elle reste déclenchée UNIQUEMENT par un démarrage
  /// vidéo réellement confirmé (cf. `_onVideoStarted`), jamais par ce
  /// démarrage audio en lui-même.
  Future<void> _loadCatalogItem(MeditationItem item) async {
    await _audio.stop();
    if (!mounted) return;
    setState(() {
      _item = item;
      _status = _PlayStatus.idle;
      _elapsed = Duration.zero;
      _total = Duration.zero;
    });
    final ok = await _audio.play(item.playbackSource);
    if (!mounted) return;
    setState(() {
      _status = ok ? _PlayStatus.playing : _PlayStatus.unavailable;
      if (ok) _videoActive = true;
    });
  }

  Future<void> _goPrevious() async {
    if (!_canGoPrevious) return;
    _keepControlsVisible();
    await _loadCatalogItem(_catalogItems[_currentIndex - 1]);
  }

  Future<void> _goNext() async {
    if (!_canGoNext) return;
    _keepControlsVisible();
    await _loadCatalogItem(_catalogItems[_currentIndex + 1]);
  }

  Future<void> _onPrimaryTap() async {
    _keepControlsVisible();
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
    // FEED MÉDITATION — l'autoplay (`autoplayOnOpen`) est déclenché dès
    // `initState`, avant que la vérification de page active n'ait eu lieu.
    // Si la page a été quittée entre-temps (swipe très rapide), on n'affiche
    // JAMAIS un état "en lecture" pour une page qui n'est plus à l'écran :
    // on coupe tout de suite (aucun double audio entre deux pages du feed).
    if (ok && !_onThisTab) {
      unawaited(_audio.pause());
      setState(() => _status = _PlayStatus.paused);
      return;
    }
    setState(() {
      _status = ok ? _PlayStatus.playing : _PlayStatus.unavailable;
      if (ok) _videoActive = true;
    });
    // AUCUN repli mission ici : le démarrage de l'audio, à lui seul, ne coche
    // JAMAIS « Prends ton temps ». Seul un démarrage vidéo RÉELLEMENT
    // confirmé le fait (cf. _onVideoStarted). Si aucune vidéo ne peut
    // démarrer, la mission reste non cochée pour cette séance.
  }

  Future<void> _pause() async {
    await _audio.pause();
    if (!mounted) return;
    setState(() {
      _status = _PlayStatus.paused;
      _videoActive = false;
    });
  }

  Future<void> _resume() async {
    await _audio.resume();
    if (!mounted) return;
    setState(() {
      _status = _PlayStatus.playing;
      _videoActive = true;
    });
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

    final placeholder = _StagePlaceholder(
      category: _item.category,
      playing: playing,
    );

    // VIDÉO PLEIN ÉCRAN — élément PRINCIPAL de TOUT L'ÉCRAN (façon lecteur
    // média immersif type YouTube en ergonomie, jamais en identité visuelle) :
    // bord-à-bord, derrière toute l'interface. `RelaxationVideoStage` recadre
    // déjà en `BoxFit.cover` (portrait ET paysage) ; `borderRadius: zero` -> ni
    // coin arrondi ni cadre, l'épure est le point de ce lot. Un fond noir
    // constant sert de rideau pendant le chargement -> jamais de flash blanc.
    // La vidéo reste TOUJOURS muette : le MP3 est la SEULE source audio, et ce
    // widget n'a aucune référence au lecteur audio.
    final video = Positioned.fill(
      key: const Key('meditation-video-stage'),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: _video != null
            ? RelaxationVideoStage(
                video: _video,
                active: _videoActive,
                surfaceFactory: widget.videoSurfaceFactory,
                fallback: placeholder,
                onStarted: _onVideoStarted,
                onFailed: _onVideoFailed,
                borderRadius: BorderRadius.zero,
              )
            : placeholder,
      ),
    );

    // Dégradé TRÈS léger : lisibilité du texte seulement, jamais un
    // assombrissement de la vidéo. Un peu plus soutenu tout en haut (header)
    // et tout en bas (infos + contrôles), transparent au centre. S'efface
    // avec les contrôles : contrôles masqués -> vidéo pure, sans overlay.
    final scrim = Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: _controlsFadeDuration,
          curve: Curves.easeOut,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x59000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x9E000000),
                ],
                stops: [0.0, 0.16, 0.52, 1.0],
              ),
            ),
          ),
        ),
      ),
    );

    // Capteur de tap « façon lecteur vidéo moderne » : sous les contrôles
    // (leurs propres boutons gardent la priorité au hit-test), au-dessus de
    // la vidéo/du dégradé. Un tap qui n'atterrit sur AUCUN bouton -> bascule
    // l'affichage des contrôles.
    final tapCatcher = Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
      ),
    );

    final header = Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _AutoHideLayer(
        visible: _controlsVisible,
        duration: _controlsFadeDuration,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
            child: Row(
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
                      color: Colors.white,
                    ),
                  )
                else
                  const SizedBox(width: 44),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'AURYEL · MÉDITATION',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuryelText.body(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 3.0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Seul l'or Auryel, en accent très discret : une simple
                      // ligne de texte, jamais de soulignement.
                      Text(
                        _item.category.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuryelText.body(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.goldLight,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
        ),
      ),
    );

    // BAS D'ÉCRAN — directement posé sur la vidéo : titre + phrase courte,
    // barre de progression fine, contrôles, « Choisir le visuel ». Aucune
    // carte, aucun fond opaque, aucun contour.
    final bottom = Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _AutoHideLayer(
        visible: _controlsVisible,
        duration: _controlsFadeDuration,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.display(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuryelText.body(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 20),
                _ThinProgressBar(progress: progress),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _mmss(_elapsed),
                      style: AuryelText.body(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      _mmss(total),
                      style: AuryelText.body(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: widget.showCatalogNavigation
                      ? [
                          _SkipButton(
                            key: const Key('meditation-previous-button'),
                            icon: Icons.skip_previous_rounded,
                            tooltip: 'Méditation précédente',
                            onTap: _canGoPrevious ? _goPrevious : null,
                          ),
                          const SizedBox(width: 26),
                          _PlayButton(playing: playing, onTap: _onPrimaryTap),
                          const SizedBox(width: 26),
                          _SkipButton(
                            key: const Key('meditation-next-button'),
                            icon: Icons.skip_next_rounded,
                            tooltip: 'Méditation suivante',
                            onTap: _canGoNext ? _goNext : null,
                          ),
                        ]
                      : [_PlayButton(playing: playing, onTap: _onPrimaryTap)],
                ),
                // « Choisir le visuel » SUPPRIMÉ (CORRECTIF « feed méditation
                // + réveil vocal ») : le visuel est désormais TOUJOURS choisi
                // automatiquement par le feed, jamais manuellement.
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [video, scrim, tapCatcher, header, bottom],
    );
  }
}

/// Enveloppe un bloc de contrôles (en-tête ou bas d'écran) avec le
/// comportement d'auto-hide : fondu simple et propre, et — quand masqué —
/// [IgnorePointer] pour que le tap traverse jusqu'au [GestureDetector] de la
/// vidéo en dessous (jamais de zone morte invisible qui bloquerait le tap de
/// réaffichage).
class _AutoHideLayer extends StatelessWidget {
  const _AutoHideLayer({
    required this.visible,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: Curves.easeOut,
          child: child,
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
    // NETTOYAGE VISUEL — plus aucun contour doré décoratif dans le lecteur :
    // ce médaillon (visible seulement en repli, sans vidéo) reste dans la
    // palette blanc/gris/noir translucide. Seul le libellé de catégorie de
    // l'en-tête garde l'or, en accent de texte très discret.
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
          color: Colors.white.withValues(alpha: playing ? 0.55 : 0.25),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: PhosphorIcon(
        _icon,
        size: 44,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}

/// Bouton central lecture/pause — sobre : disque blanc translucide (effet
/// « verre »), icône blanche, SANS contour ni remplissage doré. Nettement
/// plus grand que les boutons précédent/suivant (élément principal des
/// contrôles).
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
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.2,
              ),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 38,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton latéral précédent/suivant — plus petit que le bouton central,
/// design sobre (blanc / noir translucide, sans contour doré), désactivé
/// proprement aux extrémités du catalogue (jamais de crash, jamais d'action
/// fantôme). CHANGE UNIQUEMENT L'AUDIO (voir `_goPrevious`/`_goNext`) : ce
/// bouton n'a et n'aura jamais de référence au visuel affiché.
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: enabled ? 0.26 : 0.12),
            ),
            child: Icon(
              icon,
              size: 24,
              color: Colors.white.withValues(alpha: enabled ? 0.95 : 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre de progression fine et sobre : ligne blanche/grise, petit curseur —
/// remplace l'ancienne grosse barre dorée. Aucune promesse temporelle : les
/// temps affichés viennent du MP3 (voir l'appelant).
class _ThinProgressBar extends StatelessWidget {
  const _ThinProgressBar({required this.progress});

  /// 0.0 -> 1.0.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final x = (w * progress).clamp(0.0, w);
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                width: x,
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Positioned(
                left: (x - 4).clamp(0.0, w - 8 < 0 ? 0.0 : w - 8),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

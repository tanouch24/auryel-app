import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/content_repository.dart';
import '../data/feed_swipe_hint_store.dart';
import '../data/meditation_audio.dart';
import '../data/meditation_catalog.dart';
import '../data/meditation_feed_order.dart';
import '../data/meditation_item.dart';
import '../data/relaxation_video.dart';
import '../data/relaxation_video_selector.dart';
import '../theme/auryel_theme.dart';
import '../widgets/feed_page_scope.dart';
import '../widgets/relaxation_video_background.dart';
import 'meditation_library_screen.dart';
import 'meditation_screen.dart';

/// GROS LOT « feed méditation + réveil vocal » — nouvel onglet Méditation :
/// feed vertical plein écran (ergonomie TikTok/Reels, jamais l'identité
/// visuelle) où chaque page = 1 méditation ([MeditationScreen], une séance
/// audio + son visuel d'ambiance auto-sélectionné).
///
/// ORDRE : « sac mélangé » ([MeditationFeedOrder]) — tout le catalogue est
/// proposé une fois avant qu'une méditation ne revienne, jamais de répétition
/// immédiate à la jointure d'un tour au suivant. L'ordre grandit à la demande
/// (défilement en avant potentiellement infini) ; « précédent » reste
/// simplement borné à la 1ʳᵉ page.
///
/// CORRECTIF UX « sans spinner ni replay manuel » — deux bugs réels observés
/// sur Samsung ont motivé cette version :
///  1. un écran « Un instant… » (spinner) apparaissait trop souvent, parce
///     que la page ACTIVEMENT visée attendait la fin de sa propre
///     préparation vidéo avant de s'afficher ;
///  2. certaines vidéos n'apparaissaient JAMAIS et l'audio exigeait parfois
///     un second tap sur Play, parce qu'une page voisine (préconstruite
///     pendant que l'utilisateur est encore sur la précédente) capturait son
///     visuel une seule fois via un champ `late` — un visuel résolu APRÈS
///     coup (une fois le réseau revenu) n'était alors plus jamais repris.
///
/// Résolution : AUCUN écran d'attente séparé. Une page devient RÉELLEMENT
/// active (donc son [MeditationScreen] construit) dès qu'elle est visée —
/// l'audio démarre IMMÉDIATEMENT (jamais de tap requis), et son visuel
/// s'affiche dès qu'il est prêt : soit déjà là (cas courant, grâce au
/// [_VideoPool] pré-chargé en tâche de fond), soit rattrapé quelques
/// centaines de ms plus tard via [MeditationScreen.initialVideo] devenu
/// réactif (`didUpdateWidget`) — sans jamais réafficher un spinner ni
/// interrompre l'audio déjà en cours. En l'absence totale de visuel
/// disponible, l'écran retombe sur le fond calme DÉJÀ existant de
/// [MeditationScreen] (aucune nouveauté, aucun spinner : simple médaillon
/// statique) — jamais un texte « chargement ».
///
/// [_VideoPool] — un petit pool de vidéos DÉJÀ chargées et vérifiées
/// (indépendant de la méditation qui les consommera, ces visuels étant de
/// toute façon assignés au hasard) ; chaque candidat est tenté avec un
/// timeout COURT — trop lente ou cassée, elle est écartée pour la session
/// (jamais retentée) et remplacée immédiatement par une autre. Objectif :
/// avoir quasi toujours, sans attendre, un visuel prêt à consommer.
///
/// CONTRÔLEURS — seules les pages à ±1 de la page visée conservent un
/// [_FeedSlot] (donc un vrai lecteur audio + un vrai contrôleur vidéo) ; tout
/// slot hors de cette fenêtre est disposé -> jamais 50 lecteurs/contrôleurs
/// en mémoire, jamais tout le catalogue chargé d'avance.
///
/// BIBLIOTHÈQUE — reste accessible en permanence via le bouton « Toutes les
/// méditations » (coin supérieur), qui ouvre [MeditationLibraryScreen]
/// inchangée. Un tap explicite sur une fiche de la bibliothèque revient ICI
/// via [initialItem] : la séance choisie s'ouvre immédiatement en 1ʳᵉ page
/// avec autoplay, puis le swipe continue sur le reste du catalogue mélangé.
class MeditationFeedScreen extends StatefulWidget {
  const MeditationFeedScreen({
    super.key,
    this.initialItem,
    this.catalog = const MeditationCatalog(),
    this.feedOrder,
    this.hintStore = const FeedSwipeHintStore(),
    this.audioFactory,
    this.videoSurfaceFactory,
    this.videoSelector,
  });

  /// Séance à ouvrir immédiatement en 1ʳᵉ page (venant d'un tap explicite
  /// dans la bibliothèque). `null` -> 1ʳᵉ page = 1er élément du catalogue
  /// mélangé (ouverture normale de l'onglet Méditation).
  final MeditationItem? initialItem;

  /// Repli embarqué si aucun contenu distant n'est disponible.
  final MeditationCatalog catalog;

  /// Test uniquement : algorithme de mélange injectable (déterministe).
  final MeditationFeedOrder? feedOrder;

  /// Test uniquement : mémorisation de l'indication de swipe injectable.
  final FeedSwipeHintStore hintStore;

  /// Test uniquement : fabrique un lecteur audio par page (aucun canal
  /// plateforme en test). `null` -> chaque page utilise son lecteur réel par
  /// défaut ([MeditationAudio] concret).
  final MeditationAudio Function()? audioFactory;

  /// Test uniquement : fabrique la surface vidéo d'un candidat du pool
  /// (aucun canal plateforme en test).
  final RelaxationVideoSurface Function()? videoSurfaceFactory;

  /// Test uniquement : sélecteur de vidéo d'ambiance déterministe.
  final RelaxationVideoSelector? videoSelector;

  @override
  State<MeditationFeedScreen> createState() => _MeditationFeedScreenState();
}

/// Un visuel d'ambiance DÉJÀ chargé et vérifié, en attente d'être consommé
/// par une page du feed.
class _PooledVideo {
  _PooledVideo(this.video, this.surface);
  final RelaxationVideo video;
  final RelaxationVideoSurface surface;
}

/// État d'UNE page du feed. `video`/`surface` démarrent `null` et sont
/// assignés dès qu'un candidat du [_VideoPool] est disponible — que ce soit
/// AVANT ou APRÈS que la page ait déjà été construite (voir
/// [MeditationScreen.initialVideo], devenu réactif). Ce découplage total
/// entre « la page existe » et « son visuel est prêt » est précisément ce
/// qui permet à l'audio de démarrer sans jamais attendre la vidéo.
class _FeedSlot {
  _FeedSlot(this.item);

  final MeditationItem item;
  MeditationAudio? audio;
  RelaxationVideo? video;
  RelaxationVideoSurface? surface;
  bool disposed = false;

  void dispose() {
    if (disposed) return;
    disposed = true;
    audio?.dispose();
    surface?.dispose();
  }
}

class _MeditationFeedScreenState extends State<MeditationFeedScreen> {
  late final MeditationFeedOrder _feedOrder =
      widget.feedOrder ?? MeditationFeedOrder();
  late final RelaxationVideoSelector _videoSelector =
      widget.videoSelector ?? RelaxationVideoSelector();
  final PageController _pageController = PageController();

  bool _resolved = false;
  bool _loading = true;
  List<MeditationItem> _catalogItems = const [];
  final List<MeditationItem> _order = [];

  /// Page physiquement visée par le `PageView` — TOUJOURS la page active
  /// (plus de délai artificiel : voir la doc de la classe). Diffusée via
  /// [FeedPageScope] : c'est elle qui pilote démarrage/pause dans
  /// [MeditationScreen] (mécanisme inchangé des lots précédents).
  int _viewedIndex = 0;

  /// Préparation en avance des pages à ±1 de [_viewedIndex] — DÉCOUPLÉE de la
  /// construction des widgets `PageView`.
  final Map<int, _FeedSlot> _slots = {};

  // ---------------------------------------------------------------------
  // POOL DE VIDÉOS — un petit nombre de visuels déjà chargés d'avance,
  // indépendamment de la méditation qui les consommera.
  // ---------------------------------------------------------------------
  final List<_PooledVideo> _videoPool = [];

  /// Slugs écartés cette session (chargement trop lent ou en échec) —
  /// jamais retentés tant que l'écran vit, pour ne jamais boucler sur une
  /// vidéo cassée.
  final Set<String> _brokenVideoSlugs = {};

  bool _refillingPool = false;
  static const _kPoolTarget = 2;

  /// Délai COURT par candidat (préférer une autre vidéo déjà rapide plutôt
  /// que d'attendre — jamais plusieurs secondes d'attente visible).
  static const _kVideoCandidateTimeout = Duration(seconds: 2, milliseconds: 500);

  /// Borne la préparation audio de la même façon (réseau lent -> le `play()`
  /// normal, un peu plus lent, prendra simplement le relais à l'activation).
  static const _kAudioPrepareTimeout = Duration(seconds: 3);

  List<RelaxationVideo>? _videoCatalog;
  Future<List<RelaxationVideo>>? _videoCatalogFuture;

  bool _hintResolved = false;
  bool _showHint = false;

  /// `Future.timeout()` laisse son propre minuteur interne tourner tant que
  /// le future d'origine n'a réellement abouti — ni annulable ni visible de
  /// l'extérieur. Un lecteur RÉEL peut, en environnement de test (aucun
  /// canal plateforme), ne JAMAIS résoudre : le minuteur de secours géré ICI
  /// (annulé explicitement à [dispose]) évite un minuteur fantôme après la
  /// destruction de l'écran.
  final List<Timer> _ownTimers = [];

  Future<T> _withOwnTimeout<T>(
    Future<T> future,
    Duration duration,
    T Function() onTimeout,
  ) {
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(duration, () {
      _ownTimers.remove(timer);
      if (!completer.isCompleted) completer.complete(onTimeout());
    });
    _ownTimers.add(timer);
    future.then(
      (v) {
        if (timer.isActive) {
          timer.cancel();
          _ownTimers.remove(timer);
        }
        if (!completer.isCompleted) completer.complete(v);
      },
      onError: (Object e, StackTrace st) {
        if (timer.isActive) {
          timer.cancel();
          _ownTimers.remove(timer);
        }
        if (!completer.isCompleted) completer.completeError(e, st);
      },
    );
    return completer.future;
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final t in List<Timer>.of(_ownTimers)) {
      t.cancel();
    }
    _ownTimers.clear();
    for (final s in _slots.values) {
      s.dispose();
    }
    for (final c in _videoPool) {
      c.surface.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;

    final content = ContentScope.maybeOf(context);
    if (content == null) {
      _bootstrap(widget.catalog.all);
    } else {
      content
          .meditations()
          .then((list) {
            if (!mounted) return;
            _bootstrap(list.isEmpty ? widget.catalog.all : list);
          })
          .catchError((_) {
            if (!mounted) return;
            _bootstrap(widget.catalog.all);
          });
    }

    widget.hintStore.hasBeenShown().then((shown) {
      if (!mounted) return;
      setState(() {
        _hintResolved = true;
        _showHint = !shown;
      });
    });
  }

  void _bootstrap(List<MeditationItem> raw) {
    final items = _dedup(raw);
    final initial = widget.initialItem;
    final List<MeditationItem> ordered;
    if (initial != null && items.any((m) => m.id == initial.id)) {
      final rest = items.where((m) => m.id != initial.id).toList();
      ordered = [initial, ..._feedOrder.shuffle(rest)];
    } else if (initial != null) {
      // Séance choisie hors du catalogue résolu (ex. catalogue distant pas
      // encore synchronisé) : elle reste jouable en 1ʳᵉ page quand même.
      ordered = [initial, ..._feedOrder.shuffle(items)];
    } else {
      ordered = _feedOrder.shuffle(items);
    }
    if (!mounted) return;
    setState(() {
      _catalogItems = items;
      _order
        ..clear()
        ..addAll(ordered);
      _loading = false;
    });
    // Amorce le pool AVANT même la 1ʳᵉ préparation de page : dès que
    // possible, au moins un visuel est déjà prêt à être consommé.
    unawaited(_refillPoolIfNeeded());
    _ensureWindowPrepared();
  }

  /// 1 AUDIO = 1 FICHE : même règle de déduplication que la bibliothèque.
  static List<MeditationItem> _dedup(List<MeditationItem> src) {
    final seen = <String>{};
    final out = <MeditationItem>[];
    for (final m in src) {
      final key = m.id.isNotEmpty ? m.id : m.title;
      if (seen.add(key)) out.add(m);
    }
    return out;
  }

  /// Étend paresseusement l'ordre du feed (défilement en avant potentiellement
  /// infini) : à l'épuisement du tour courant, remélange le catalogue en
  /// entier pour le tour suivant, en évitant que le dernier élément du tour
  /// précédent redevienne le premier du nouveau (anti-répétition immédiate à
  /// la jointure). Opération pure/synchrone -> sûre à appeler depuis
  /// `itemBuilder`.
  MeditationItem? _itemAt(int i) {
    if (_catalogItems.isEmpty || i < 0) return null;
    while (_order.length <= i) {
      _order.addAll(
        _feedOrder.reshuffle(
          _catalogItems,
          _order.isNotEmpty ? _order.last : null,
        ),
      );
    }
    return _order[i];
  }

  Future<List<RelaxationVideo>> _resolveVideoCatalog() {
    final cached = _videoCatalog;
    if (cached != null) return Future.value(cached);
    return _videoCatalogFuture ??= () async {
      final content = ContentScope.maybeOf(context);
      if (content == null) return const <RelaxationVideo>[];
      try {
        final list = await content.meditationVideos();
        _videoCatalog = list;
        return list;
      } catch (_) {
        return const <RelaxationVideo>[];
      }
    }();
  }

  /// Reconstitue le pool jusqu'à [_kPoolTarget] candidats PRÊTS, PUIS
  /// distribue immédiatement tout candidat disponible aux slots encore sans
  /// visuel (qu'ils viennent d'être créés ou qu'ils attendaient déjà) — un
  /// slot ne réclame le pool qu'une fois à sa création ; c'est CE
  /// réapprovisionnement qui doit ensuite le servir dès qu'un candidat est
  /// prêt, sinon un slot resterait sans visuel pour toujours. Chaque
  /// tentative de chargement est bornée à [_kVideoCandidateTimeout] : trop
  /// lente -> écartée pour la session (jamais retentée), remplacée par une
  /// autre. Si TOUT le catalogue est cassé, abandonne proprement (le fond
  /// statique déjà existant de [MeditationScreen] prend le relais, jamais de
  /// boucle infinie).
  Future<void> _refillPoolIfNeeded() async {
    if (!_refillingPool) {
      _refillingPool = true;
      try {
        while (mounted && _videoPool.length < _kPoolTarget) {
          final catalog = await _resolveVideoCatalog();
          if (catalog.isEmpty) break;
          final avoid = {
            ..._brokenVideoSlugs,
            ..._videoPool.map((c) => c.video.slug),
          };
          final candidates = catalog
              .where((v) => !avoid.contains(v.slug))
              .toList(growable: false);
          if (candidates.isEmpty) {
            // Plus rien de neuf à proposer (tout cassé ou déjà dans le
            // pool) -> on abandonne proprement plutôt que de boucler.
            break;
          }
          // Pool générique (indépendant de toute méditation précise) : pas
          // de filtre de catégorie ici, `choose` retombe déjà sur tout le
          // catalogue si aucun visuel générique n'est disponible.
          final picked = _videoSelector.choose(
            candidates,
            meditationCategory: '',
          );
          if (picked == null) break;
          final surface =
              widget.videoSurfaceFactory?.call() ?? VideoPlayerRelaxationSurface();
          bool ok;
          try {
            ok = await _withOwnTimeout(
              surface.load(picked.videoUrl),
              _kVideoCandidateTimeout,
              () => false,
            );
          } catch (_) {
            ok = false;
          }
          if (!mounted) {
            surface.dispose();
            break;
          }
          if (ok) {
            _videoPool.add(_PooledVideo(picked, surface));
          } else {
            surface.dispose();
            _brokenVideoSlugs.add(picked.slug);
            developer.log(
              'Vidéo de relaxation écartée cette session '
              '(chargement trop lent ou en échec) : '
              '${picked.slug} — ${picked.videoUrl}',
              name: 'auryel.meditation_feed',
            );
          }
        }
      } finally {
        _refillingPool = false;
      }
    }
    if (!mounted) return;

    // Distribue tout candidat disponible aux slots (fenêtre courante) encore
    // sans visuel — dans l'ordre de la fenêtre, pour privilégier la page
    // visée puis ses voisines.
    var assigned = false;
    for (final i in _slots.keys.toList()..sort()) {
      if (_videoPool.isEmpty) break;
      final slot = _slots[i]!;
      if (slot.disposed || slot.video != null) continue;
      final c = _videoPool.removeAt(0);
      slot.video = c.video;
      slot.surface = c.surface;
      assigned = true;
    }
    if (assigned) {
      setState(() {});
      // Ce qui vient d'être consommé doit être remplacé sans attendre le
      // prochain déclencheur.
      unawaited(_refillPoolIfNeeded());
    }
  }

  /// Démarre (si nécessaire) la préparation du slot [i] : audio préparé SANS
  /// jouer (démarrage quasi instantané à l'activation), visuel réclamé au
  /// pool (immédiatement si un candidat est déjà prêt, sinon dès qu'il le
  /// devient — voir [_refillPoolIfNeeded]). N'a AUCUN effet si [i] est déjà
  /// préparé/en cours.
  void _prepare(int i) {
    if (_slots.containsKey(i)) return;
    final item = _itemAt(i);
    if (item == null) return;
    final slot = _FeedSlot(item);
    _slots[i] = slot;

    final audio = widget.audioFactory?.call() ?? AudioPlayersMeditationAudio();
    slot.audio = audio;
    if (item.hasPlayableSource) {
      unawaited(
        _withOwnTimeout(
          audio.prepare(item.playbackSource),
          _kAudioPrepareTimeout,
          () {},
        ).catchError((_) {}),
      );
    }

    if (_videoPool.isNotEmpty) {
      final c = _videoPool.removeAt(0);
      slot.video = c.video;
      slot.surface = c.surface;
    }
    unawaited(_refillPoolIfNeeded());
  }

  /// Garantit un [_FeedSlot] préparé pour {viewedIndex-1, viewedIndex,
  /// viewedIndex+1} et libère tout slot en dehors de cette fenêtre — jamais
  /// plus de 3 lecteurs/contrôleurs en mémoire, jamais tout le catalogue.
  void _ensureWindowPrepared() {
    final keep = {
      if (_viewedIndex > 0) _viewedIndex - 1,
      _viewedIndex,
      _viewedIndex + 1,
    };
    for (final i in keep) {
      _prepare(i);
    }
    final stale = _slots.keys.where((i) => !keep.contains(i)).toList();
    for (final i in stale) {
      _slots.remove(i)?.dispose();
    }
  }

  void _onPageChanged(int i) {
    setState(() => _viewedIndex = i);
    _ensureWindowPrepared();
    if (_showHint) {
      setState(() => _showHint = false);
      unawaited(widget.hintStore.markShown());
    }
  }

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MeditationLibraryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AuryelColors.goldLight),
        ),
      );
    }
    if (_catalogItems.isEmpty) {
      return _EmptyFeedState(onOpenLibrary: _openLibrary);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            key: const Key('meditation-feed-page-view'),
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) {
              final item = _itemAt(i);
              if (item == null) return const SizedBox.shrink();
              // Seules les pages à ±1 de la page VISÉE gardent un rendu réel
              // -> jamais 50 lecteurs/contrôleurs en mémoire.
              final withinWindow = (i - _viewedIndex).abs() <= 1;
              if (!withinWindow) return const ColoredBox(color: Colors.black);

              final slot = _slots[i];
              // CORRECTIF UX — la page est TOUJOURS construite (donc son
              // audio démarre TOUJOURS immédiatement dès qu'elle devient
              // active, jamais de tap requis) : AUCUN écran d'attente ici.
              // `initialVideo` peut être `null` au premier rendu -> l'écran
              // affiche alors son fond calme déjà existant (aucun spinner),
              // puis se met à jour tout seul dès qu'un visuel arrive (voir
              // `MeditationScreen.didUpdateWidget`).
              return FeedPageScope(
                pageIndex: i,
                activeIndex: _viewedIndex,
                child: MeditationScreen(
                  key: ValueKey('meditation-feed-item-$i'),
                  item: slot?.item ?? item,
                  // Vrai dès la 1ʳᵉ construction ACTIVE de cette page — pas
                  // seulement pour la toute 1ʳᵉ page du feed : une page
                  // fraîchement construite déjà active ne doit JAMAIS
                  // attendre un tap sur Play.
                  autoplayOnOpen: i == _viewedIndex,
                  showCatalogNavigation: false,
                  audioOverride: slot?.audio,
                  initialVideo: slot?.video,
                  videoResolvedExternally: true,
                  videoSurfaceFactory: slot?.surface != null
                      ? () => slot!.surface!
                      : widget.videoSurfaceFactory,
                  videoSelector: widget.videoSelector,
                ),
              );
            },
          ),
          _LibraryAccessButton(onTap: _openLibrary),
          if (_hintResolved) _SwipeHintOverlay(visible: _showHint),
        ],
      ),
    );
  }
}

/// Bouton d'accès permanent à la bibliothèque complète, posé en surimpression
/// (coin supérieur droit, sous la zone de titre du lecteur) sur chaque page
/// du feed.
class _LibraryAccessButton extends StatelessWidget {
  const _LibraryAccessButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 6, right: 10),
          child: Semantics(
            button: true,
            label: 'Toutes les méditations',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('meditation-feed-library-button'),
                onTap: onTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.listBullets,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indication de swipe — visible UNIQUEMENT au tout premier usage (voir
/// [FeedSwipeHintStore]), s'efface en fondu dès le premier vrai swipe et ne
/// revient jamais gêner ensuite. Ignore les taps (`IgnorePointer`) : ne
/// bloque jamais l'interaction avec la page en dessous.
class _SwipeHintOverlay extends StatelessWidget {
  const _SwipeHintOverlay({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 132,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            key: const Key('meditation-feed-swipe-hint'),
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 26,
                  color: Colors.white,
                ),
                Text(
                  'Fais glisser pour découvrir une autre méditation',
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Catalogue vide (aucune méditation nulle part, ni distante ni embarquée) :
/// jamais un écran cassé, un état calme qui laisse quand même ouvrir la
/// bibliothèque (repli identique).
class _EmptyFeedState extends StatelessWidget {
  const _EmptyFeedState({required this.onOpenLibrary});

  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    PhosphorIconsRegular.leaf,
                    size: 40,
                    color: AuryelColors.goldLight,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Les méditations arrivent très bientôt.',
                    textAlign: TextAlign.center,
                    style: AuryelText.body(
                      fontSize: 13,
                      color: AuryelColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

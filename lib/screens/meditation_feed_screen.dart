import 'dart:async';

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
/// CORRECTIF « lecture synchronisée » — le bug Samsung d'origine (l'audio de
/// la méditation suivante démarrait immédiatement au swipe, la vidéo
/// n'apparaissant que plusieurs secondes après) venait du fait que le
/// préchargement d'une page voisine dépendait de la construction paresseuse
/// du `PageView` (qui ne construit RÉELLEMENT une page qu'au moment où elle
/// entre dans le viewport, pas avant). La préparation (vidéo ET audio) est
/// désormais un état [_FeedSlot] géré PAR CE STATE, totalement DÉCOUPLÉ de la
/// construction des widgets : elle démarre dès que possible pendant que la
/// page précédente joue encore, indépendamment de ce que `PageView` a ou non
/// déjà construit.
///
/// Au swipe : si la page suivante est déjà « prête » (vidéo initialisée +
/// 1ʳᵉ frame disponible, audio préparé), l'activation démarre vidéo ET audio
/// ensemble (quasi simultané, jamais un `Future.delayed` arbitraire). Si elle
/// ne l'est pas encore (swipe très rapide avant la fin du préchargement), un
/// écran de transition calme s'affiche SANS AUCUN AUDIO tant que la page
/// n'est pas prête — jamais de son sans image.
///
/// CONTRÔLEURS — seules les pages à ±1 de la page consultée conservent un
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

  /// Test uniquement : fabrique la surface vidéo d'une page (aucun canal
  /// plateforme en test).
  final RelaxationVideoSurface Function()? videoSurfaceFactory;

  /// Test uniquement : sélecteur de vidéo d'ambiance déterministe.
  final RelaxationVideoSelector? videoSelector;

  @override
  State<MeditationFeedScreen> createState() => _MeditationFeedScreenState();
}

/// État de préparation d'UNE page du feed — préparé À L'AVANCE, pendant que
/// la page précédente joue encore, pour que vidéo ET audio démarrent
/// ENSEMBLE au moment où l'utilisateur y arrive. « Prêt » veut dire résolu
/// dans un sens ou dans l'autre : soit une vidéo a réellement fini de
/// s'initialiser (1ʳᵉ frame disponible), soit il est définitivement établi
/// qu'aucune vidéo utilisable n'existe pour cette page (fond statique) — dans
/// les deux cas, plus rien ne peut retarder l'activation de l'audio.
class _FeedSlot {
  _FeedSlot(this.item);

  final MeditationItem item;
  MeditationAudio? audio;
  RelaxationVideo? video;
  RelaxationVideoSurface? surface;

  bool audioReady = false;
  bool videoReady = false;
  bool disposed = false;

  bool get ready => audioReady && videoReady;

  final Completer<void> _readyCompleter = Completer<void>();
  Future<void> get onReady => _readyCompleter.future;

  void _maybeComplete() {
    if (ready && !_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  void markAudioReady() {
    audioReady = true;
    _maybeComplete();
  }

  void markVideoReady() {
    videoReady = true;
    _maybeComplete();
  }

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

  /// Page physiquement affichée par le `PageView` (mise à jour immédiatement
  /// au swipe). Sert UNIQUEMENT à décider quoi dessiner à chaque index.
  int _viewedIndex = 0;

  /// Page réellement ACTIVE (audio/vidéo en cours) — ne rejoint [_viewedIndex]
  /// qu'une fois son [_FeedSlot] prêt. Diffusée via [FeedPageScope] : c'est
  /// elle qui pilote démarrage/pause dans [MeditationScreen] (mécanisme
  /// inchangé du lot précédent).
  int _activeIndex = -1;

  static const _initialIndex = 0;

  /// Préparation en avance des pages à ±1 de [_viewedIndex] — DÉCOUPLÉE de la
  /// construction des widgets `PageView` (voir doc de la classe).
  final Map<int, _FeedSlot> _slots = {};

  List<RelaxationVideo>? _videoCatalog;
  Future<List<RelaxationVideo>>? _videoCatalogFuture;

  bool _hintResolved = false;
  bool _showHint = false;

  /// Borne NOTRE propre préparation audio (indépendante des délais internes,
  /// plus longs, du lecteur) — un réseau lent ne doit jamais faire traîner
  /// l'écran de transition au-delà du raisonnable.
  static const _kPrepareStepTimeout = Duration(seconds: 4);

  @override
  void dispose() {
    _pageController.dispose();
    for (final s in _slots.values) {
      s.dispose();
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
        final list = await content.relaxationVideos();
        _videoCatalog = list;
        return list;
      } catch (_) {
        return const <RelaxationVideo>[];
      }
    }();
  }

  /// Démarre (si nécessaire) la préparation du slot [i] : audio préparé SANS
  /// jouer, vidéo choisie et chargée d'avance (avec repli borné sur un AUTRE
  /// visuel si le 1er choisi est trop lent/cassé — jamais garder coûte que
  /// coûte une vidéo lente). N'a AUCUN effet si [i] est déjà préparé/en cours.
  Future<void> _prepare(int i) async {
    if (_slots.containsKey(i)) return;
    final item = _itemAt(i);
    if (item == null) return;
    final slot = _FeedSlot(item);
    _slots[i] = slot;

    // AUDIO — préparé sans jouer (voir `MeditationAudio.prepare`). Borné
    // NOUS-MÊMES (au lieu de dépendre du délai interne, plus long, du
    // lecteur) : un réseau lent ne doit jamais retarder l'activation de
    // plusieurs dizaines de secondes — passé ce délai, la page est quand même
    // considérée prête (un `play()` normal, un peu plus lent, prendra le
    // relais à l'activation, jamais bloquant).
    final audio = widget.audioFactory?.call() ?? AudioPlayersMeditationAudio();
    slot.audio = audio;
    if (item.hasPlayableSource) {
      unawaited(
        audio
            .prepare(item.playbackSource)
            .timeout(_kPrepareStepTimeout, onTimeout: () {})
            .then((_) {
              if (slot.disposed) return;
              slot.markAudioReady();
              _onSlotProgress();
            })
            .catchError((_) {
              if (slot.disposed) return;
              slot.markAudioReady();
              _onSlotProgress();
            }),
      );
    } else {
      slot.markAudioReady(); // rien à préparer -> résolu immédiatement
    }

    // VIDÉO — résolution + chargement anticipé.
    final catalog = await _resolveVideoCatalog();
    if (slot.disposed) return;
    if (catalog.isEmpty) {
      slot.markVideoReady(); // aucune vidéo dispo -> résolu (fond statique)
      _onSlotProgress();
      return;
    }

    // 2 tentatives (1er choix + 1 repli) : borne le pire cas à ~16 s de
    // réseau lent avant de considérer la page prête (fond statique le temps
    // que l'audio, lui, démarre) — jamais un écran de transition qui traîne
    // au-delà du raisonnable.
    const maxAttempts = 2;
    final tried = <RelaxationVideo>[];
    RelaxationVideo? candidate = await _videoSelector.pick(
      catalog,
      meditationCategory: item.category.name,
    );
    for (var attempt = 0; attempt < maxAttempts && candidate != null; attempt++) {
      if (slot.disposed) return;
      tried.add(candidate);
      final surface =
          widget.videoSurfaceFactory?.call() ?? VideoPlayerRelaxationSurface();
      final ok = await surface.load(candidate.videoUrl);
      if (slot.disposed) {
        surface.dispose();
        return;
      }
      if (ok) {
        slot.video = candidate;
        slot.surface = surface;
        break;
      }
      // Vidéo trop lente/cassée -> on PRÉFÈRE en essayer une autre déjà
      // disponible plutôt que de garder coûte que coûte celle-ci (sélection
      // PURE ici, sans toucher l'historique anti-répétition — seul un choix
      // RÉELLEMENT retenu y est inscrit, via `pick` ci-dessus).
      surface.dispose();
      final remaining = catalog
          .where((v) => !tried.any((t) => t.slug == v.slug))
          .toList(growable: false);
      candidate = _videoSelector.choose(
        remaining,
        meditationCategory: item.category.name,
      );
    }
    slot.markVideoReady(); // résolu : avec vidéo prête, ou définitivement sans
    _onSlotProgress();
  }

  /// Un slot vient de progresser (audio ou vidéo prêt) : si c'est celui de la
  /// page actuellement VISÉE et qu'il est maintenant complet, l'active — et
  /// dans tous les cas, notifie l'UI (l'écran de transition observe l'état
  /// des slots directement).
  void _onSlotProgress() {
    if (!mounted) return;
    setState(_syncActiveIndex);
  }

  /// Fait rejoindre [_activeIndex] à [_viewedIndex] dès que le slot visé est
  /// prêt — jamais avant. C'est CE passage qui déclenche, via
  /// [FeedPageScope], le démarrage synchronisé vidéo+audio de
  /// [MeditationScreen] (mécanisme de reprise/démarrage déjà en place).
  void _syncActiveIndex() {
    if (_slots[_viewedIndex]?.ready == true) {
      _activeIndex = _viewedIndex;
    }
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
      unawaited(_prepare(i));
    }
    final stale = _slots.keys.where((i) => !keep.contains(i)).toList();
    for (final i in stale) {
      _slots.remove(i)?.dispose();
    }
  }

  void _onPageChanged(int i) {
    setState(() {
      _viewedIndex = i;
      _syncActiveIndex();
    });
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
              // CORRECTIF « lecture synchronisée » — la page VISÉE n'est
              // rendue en lecteur réel QUE si son slot est prêt (vidéo
              // initialisée + audio préparé). Tant que ce n'est pas le cas :
              // transition calme, JAMAIS de son de cette page en attendant
              // (aucun `MeditationScreen` construit -> aucun `_start()`
              // possible pour elle).
              if (i == _viewedIndex && slot?.ready != true) {
                return const _PreparingTransition(
                  key: Key('meditation-feed-preparing'),
                );
              }

              return FeedPageScope(
                pageIndex: i,
                activeIndex: _activeIndex,
                child: MeditationScreen(
                  key: ValueKey('meditation-feed-item-$i'),
                  item: slot?.item ?? item,
                  autoplayOnOpen: i == _initialIndex,
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

/// Écran de transition affiché UNIQUEMENT pendant qu'une page visée n'est pas
/// encore prête (vidéo/audio en cours de préparation) — calme, jamais un
/// fond vide/noir brut, et surtout SANS AUCUN AUDIO tant qu'il est affiché.
class _PreparingTransition extends StatelessWidget {
  const _PreparingTransition({super.key});

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
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AuryelColors.goldLight,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Un instant…',
              style: AuryelText.body(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
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

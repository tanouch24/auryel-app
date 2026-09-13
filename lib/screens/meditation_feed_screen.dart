import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/content_repository.dart';
import '../data/feed_swipe_hint_store.dart';
import '../data/meditation_audio.dart';
import '../data/meditation_catalog.dart';
import '../data/meditation_feed_order.dart';
import '../data/meditation_item.dart';
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
/// CONTRÔLEURS — seules les pages à ±1 de la page active instancient un
/// [MeditationScreen] réel (donc un vrai lecteur audio + un vrai contrôleur
/// vidéo) ; toute autre page est un simple rectangle noir. Une page qui sort
/// de cette fenêtre est automatiquement disposée par Flutter (nouveau widget
/// non réel au même index) -> jamais 50 lecteurs/contrôleurs en mémoire.
///
/// AUTOPLAY / PAUSE — chaque [MeditationScreen] gère lui-même son
/// démarrage/pause via [FeedPageScope] (voir ce fichier et
/// `meditation_screen.dart`) : la page qui DEVIENT active démarre ou reprend
/// automatiquement, celle qui la quitte se met en pause. Une seule source
/// audio à la fois, garanti par construction (jamais deux pages « actives »
/// en même temps).
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
  /// défaut ([MeditationScreen.audioOverride] laissé `null`).
  final MeditationAudio Function()? audioFactory;

  /// Test uniquement : fabrique la surface vidéo d'une page (aucun canal
  /// plateforme en test).
  final RelaxationVideoSurface Function()? videoSurfaceFactory;

  /// Test uniquement : sélecteur de vidéo d'ambiance déterministe.
  final RelaxationVideoSelector? videoSelector;

  @override
  State<MeditationFeedScreen> createState() => _MeditationFeedScreenState();
}

class _MeditationFeedScreenState extends State<MeditationFeedScreen> {
  late final MeditationFeedOrder _feedOrder =
      widget.feedOrder ?? MeditationFeedOrder();
  final PageController _pageController = PageController();

  bool _resolved = false;
  bool _loading = true;
  List<MeditationItem> _catalogItems = const [];
  final List<MeditationItem> _order = [];

  int _current = 0;
  static const _initialIndex = 0;

  bool _hintResolved = false;
  bool _showHint = false;

  @override
  void dispose() {
    _pageController.dispose();
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
    if (_catalogItems.isEmpty) return null;
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

  void _onPageChanged(int i) {
    setState(() => _current = i);
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
              // Seules les pages à ±1 de la page active instancient un vrai
              // lecteur (audio + vidéo) -> jamais 50 contrôleurs en mémoire.
              final withinWindow = (i - _current).abs() <= 1;
              return FeedPageScope(
                pageIndex: i,
                activeIndex: _current,
                child: withinWindow
                    ? MeditationScreen(
                        key: ValueKey('meditation-feed-item-$i'),
                        item: item,
                        autoplayOnOpen: i == _initialIndex,
                        showCatalogNavigation: false,
                        audioOverride: widget.audioFactory?.call(),
                        videoSurfaceFactory: widget.videoSurfaceFactory,
                        videoSelector: widget.videoSelector,
                      )
                    : const ColoredBox(color: Colors.black),
              );
            },
          ),
          _LibraryAccessButton(onTap: _openLibrary),
          if (_hintResolved)
            _SwipeHintOverlay(visible: _showHint),
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

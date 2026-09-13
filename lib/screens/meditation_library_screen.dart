import 'package:flutter/material.dart';

import '../data/content_repository.dart';
import '../data/meditation_catalog.dart';
import '../data/meditation_item.dart';
import '../theme/auryel_theme.dart';
import 'meditation_screen.dart';

/// Onglet « Méditation » — la BIBLIOTHÈQUE. Une liste 100 % distante et
/// extensible : 1 entrée = 1 AUDIO, identifiée par `id` stable. Une méditation
/// n'apparaît JAMAIS plusieurs fois — les visuels d'ambiance (catalogue vidéo)
/// sont un système totalement séparé, choisi dans le lecteur.
///
/// Résolution : serveur -> cache local -> pack embarqué (via [ContentRepository]).
/// Sans [ContentScope] (tests hérités), la liste embarquée est utilisée.
/// Aucun plafond : 50 aujourd'hui, davantage demain, sans nouvelle version.
class MeditationLibraryScreen extends StatefulWidget {
  const MeditationLibraryScreen({
    super.key,
    this.catalog = const MeditationCatalog(),
  });

  /// Repli embarqué quand aucun contenu distant n'est disponible.
  final MeditationCatalog catalog;

  @override
  State<MeditationLibraryScreen> createState() =>
      _MeditationLibraryScreenState();
}

class _MeditationLibraryScreenState extends State<MeditationLibraryScreen> {
  bool _loading = true;
  bool _resolved = false;
  List<MeditationItem> _items = const [];

  /// Indication de défilement (flèche + texte court) : visible dès l'arrivée
  /// sur l'écran, s'efface dès qu'un VRAI scroll est détecté.
  final ScrollController _scrollController = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Seuil > 0 pour ignorer les micro-rebonds d'overscroll (pas une vraie
    // intention de défiler).
    final scrolled = _scrollController.offset > 12;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;

    final content = ContentScope.maybeOf(context);
    if (content == null) {
      setState(() {
        _items = _dedup(widget.catalog.all);
        _loading = false;
      });
      return;
    }
    content
        .meditations()
        .then((list) {
          if (!mounted) return;
          setState(() {
            _items = _dedup(list.isEmpty ? widget.catalog.all : list);
            _loading = false;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _items = _dedup(widget.catalog.all);
            _loading = false;
          });
        });
  }

  /// 1 AUDIO = 1 FICHE : dédoublonnage défensif par `id` (puis `slug`),
  /// indépendant du catalogue vidéo qui n'entre jamais ici.
  static List<MeditationItem> _dedup(List<MeditationItem> src) {
    final seen = <String>{};
    final out = <MeditationItem>[];
    for (final m in src) {
      final key = m.id.isNotEmpty ? m.id : m.title;
      if (seen.add(key)) out.add(m);
    }
    return out;
  }

  void _open(MeditationItem item) {
    // CORRECTIF UX FINAL — réaction immédiate au tap : le player s'ouvre et
    // lance l'audio tout de suite (voir `MeditationScreen.autoplayOnOpen`),
    // sans que l'utilisateur ait besoin d'un 2e tap sur Play.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeditationScreen(item: item, autoplayOnOpen: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: AuryelColors.backgroundGradient,
            ),
            child: SafeArea(
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                children: [
                  Text(
                    'AURYEL · MÉDITATION',
                    style: AuryelText.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.gold,
                      letterSpacing: 3.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bibliothèque',
                    style: AuryelText.display(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.textCream,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choisis un moment. Le visuel apaisant se met en place tout seul.',
                    style: AuryelText.body(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AuryelColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AuryelColors.goldLight,
                        ),
                      ),
                    )
                  else if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Center(
                        child: Text(
                          'Les méditations arrivent très bientôt.',
                          textAlign: TextAlign.center,
                          style: AuryelText.body(
                            fontSize: 13,
                            color: AuryelColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final m in _items) ...[
                      _MeditationCard(
                        key: ValueKey('med-${m.id}'),
                        item: m,
                        onTap: () => _open(m),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
          // Indication de défilement — bien visible à l'arrivée, discrète
          // (une pastille, pas une bannière), disparaît dès un vrai scroll.
          if (!_loading && _items.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _scrolled ? 0 : 1,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  child: const _ScrollHint(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Petite pastille « défiler pour en découvrir plus », premium et discrète —
/// flèche plus visible que le simple contenu de la liste, sans bannière.
class _ScrollHint extends StatelessWidget {
  const _ScrollHint();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            decoration: BoxDecoration(
              color: AuryelColors.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AuryelColors.warmBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // `Flexible` + ellipsis : jamais d'overflow, quelle que soit
                // la largeur d'écran ou la métrique de police disponible.
                Flexible(
                  child: Text(
                    'Découvrir les méditations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AuryelText.body(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AuryelColors.goldLight,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 26,
                  color: AuryelColors.goldLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeditationCard extends StatelessWidget {
  const _MeditationCard({super.key, required this.item, required this.onTap});

  final MeditationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AuryelColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AuryelColors.warmBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.category.label.toUpperCase(),
                      style: AuryelText.body(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.gold,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      style: AuryelText.display(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AuryelText.body(
                          fontSize: 11.5,
                          height: 1.35,
                          color: AuryelColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      item.durationLabel,
                      style: AuryelText.body(
                        fontSize: 11,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AuryelColors.goldGradient,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 24,
                  color: AuryelColors.backgroundDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

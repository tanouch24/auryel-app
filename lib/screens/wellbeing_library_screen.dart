import 'package:flutter/material.dart';

import '../api/wellbeing_ebooks_api.dart';
import '../data/content_repository.dart';
import '../data/relaxation_video.dart';
import '../data/wake_image_catalog.dart';
import '../data/wake_video.dart';
import '../state/wellbeing_ebooks_controller.dart';
import '../state/wellbeing_program_controller.dart';
import '../theme/auryel_theme.dart';
import 'ebook_reader_screen.dart';
import 'relaxation_video_player_screen.dart';

/// Bibliothèque Bien-être V1 : trois univers éditoriaux, sans mélange entre
/// exercices, vidéos de relaxation et lectures longues.
class WellbeingLibraryScreen extends StatefulWidget {
  const WellbeingLibraryScreen({super.key, this.ebooksController});

  final WellbeingEbooksController? ebooksController;

  @override
  State<WellbeingLibraryScreen> createState() => _WellbeingLibraryScreenState();
}

class _WellbeingLibraryScreenState extends State<WellbeingLibraryScreen>
    with SingleTickerProviderStateMixin {
  ContentRepository? _content;
  WellbeingEbooksController? _ebooks;
  WellbeingProgramController? _program;
  late Future<List<RelaxationVideo>> _videos;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_content != null) return;
    _content = ContentScope.maybeOf(context);
    _ebooks = widget.ebooksController ?? WellbeingEbooksScope.maybeOf(context);
    _program = WellbeingProgramScope.maybeOf(context);
    _videos = _loadVideos();
  }

  Future<List<RelaxationVideo>> _loadVideos() async {
    final remote = _content == null
        ? const <RelaxationVideo>[]
        : await _content!.relaxationVideos();
    final byUrl = <String, RelaxationVideo>{
      for (final video in remote) video.videoUrl: video,
    };
    // Le pilote Réveil est un vrai fichier R2 partagé : il devient une
    // méditation vidéo sans recopier le MP4 ni créer un contenu fictif.
    byUrl.putIfAbsent(
      WakeVideoCatalog.pilot.remoteUrl,
      () => RelaxationVideo(
        id: WakeVideoCatalog.pilot.id,
        slug: WakeVideoCatalog.pilot.id,
        title: 'Réveil Auryel',
        videoUrl: WakeVideoCatalog.pilot.remoteUrl,
        category: 'Ambiance du matin',
      ),
    );
    final videos = byUrl.values.toList();
    videos.sort((a, b) {
      if (a.id == WakeVideoCatalog.pilot.id) return -1;
      if (b.id == WakeVideoCatalog.pilot.id) return 1;
      return 0;
    });
    return videos;
  }

  void reloadVideos() => setState(() {
        _videos = _loadVideos();
      });

  List<WellbeingEbook> _availableEbooks() {
    final current = _ebooks?.ebooks ?? const <WellbeingEbook>[];
    if (current.isNotEmpty) return current;
    final legacy = _program?.state?.ebook;
    if (legacy == null || legacy.title.trim().isEmpty) return const [];
    return [
      WellbeingEbook(
        id: 0,
        slug: 'legacy-wellbeing-ebook',
        title: legacy.title,
        subtitle: legacy.subtitle,
        description: null,
        coverUrl: null,
        pdfUrl: legacy.pdfUrl,
        publicationDate: null,
        monthLabel: null,
        version: legacy.version,
        active: legacy.active,
        featured: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final listenable = Listenable.merge([
      _ebooks ?? _NoopListenable(),
      _program ?? _NoopListenable(),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque')),
      body: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                child: Text(
                  'Un moment pour toi.',
                  style: AuryelText.body(
                    fontSize: 15,
                    color: AuryelColors.textSecondary,
                  ),
                ),
              ),
              const _LibraryTabs(),
              const Expanded(
                child: TabBarView(
                  children: [
                    _ExercisesTab(),
                    _MeditationsTab(),
                    _EbooksTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryTabs extends StatelessWidget {
  const _LibraryTabs();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
            border: Border(
            bottom: BorderSide(color: AuryelColors.warmBorder.withValues(alpha: .8)),
          ),
        ),
        child: TabBar(
          labelColor: AuryelColors.goldLight,
          unselectedLabelColor: AuryelColors.textMuted,
          labelStyle: AuryelText.body(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: AuryelText.body(fontSize: 13),
          indicatorColor: AuryelColors.goldLight,
          indicatorWeight: 2,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Exercices'),
            Tab(text: 'Méditations'),
            Tab(text: 'Ebooks'),
          ],
        ),
      );
}

class _ExercisesTab extends StatelessWidget {
  const _ExercisesTab();

  @override
  Widget build(BuildContext context) => _EmptyUniverse(
        icon: Icons.self_improvement_outlined,
        eyebrow: 'EXERCICES',
        title: 'Des pratiques guidées arrivent bientôt.',
        message:
            'Nous préparons des formats courts pour respirer, relâcher la pression et retrouver ton rythme.',
      );
}

class _MeditationsTab extends StatelessWidget {
  const _MeditationsTab();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_WellbeingLibraryScreenState>();
    if (state == null) return const SizedBox.shrink();
    return FutureBuilder<List<RelaxationVideo>>(
      future: state._videos,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AuryelColors.goldLight),
          );
        }
        if (snapshot.hasError) {
          return _EmptyUniverse(
            icon: Icons.cloud_off_outlined,
            eyebrow: 'MÉDITATIONS',
            title: 'Les ambiances reviendront bientôt.',
            message: 'Vérifie ta connexion puis réessaie.',
            action: TextButton(
              onPressed: state.reloadVideos,
              child: const Text('Réessayer'),
            ),
          );
        }
        final videos = snapshot.data ?? const <RelaxationVideo>[];
        if (videos.isEmpty) {
          return const _EmptyUniverse(
            icon: Icons.movie_outlined,
            eyebrow: 'MÉDITATIONS',
            title: 'De nouvelles ambiances arrivent bientôt.',
            message: 'Aucune vidéo de relaxation n’est disponible pour le moment.',
          );
        }
        return _VideoGrid(videos: videos);
      },
    );
  }
}

class _VideoGrid extends StatelessWidget {
  const _VideoGrid({required this.videos});

  final List<RelaxationVideo> videos;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: AuryelColors.goldLight,
        onRefresh: () async {
          final state = context.findAncestorStateOfType<_WellbeingLibraryScreenState>();
          if (state == null) return;
          state.reloadVideos();
          await state._videos;
        },
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: .78,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) => _VideoCard(
            video: videos[index],
            index: index,
          ),
        ),
      );
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.index});

  final RelaxationVideo video;
  final int index;

  String get _title {
    final title = video.title.trim();
    if (RegExp(r'^relaxation-\d+$').hasMatch(title)) {
      return 'Ambiance apaisante';
    }
    return title.isEmpty ? 'Ambiance apaisante' : title;
  }

  String get _category => video.category.trim().toLowerCase() == 'calm'
      ? 'Relaxation'
      : video.category;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RelaxationVideoPlayerScreen(
              video: video,
              displayTitle: _title,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _thumbnail(video),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xB0000000)],
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 12,
                      bottom: 12,
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: Color(0xCCF4E6BC),
                        child: Icon(Icons.play_arrow_rounded,
                            color: AuryelColors.backgroundDeep, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AuryelText.body(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              _category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AuryelText.body(fontSize: 11, color: AuryelColors.textMuted),
            ),
          ],
        ),
      );

  Widget _thumbnail(RelaxationVideo item) {
    final thumbnail = item.thumbnailUrl;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return Image.network(
        thumbnail,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackThumbnail(),
      );
    }
    if (item.id == WakeVideoCatalog.pilot.id) {
      return Image.asset(
        'assets/images/wake/reveil_ocean_plage_aube_01.jpg',
        fit: BoxFit.cover,
      );
    }
      return Image.asset(
        wakeImageAssets[index % wakeImageAssets.length],
        fit: BoxFit.cover,
      );
  }

  Widget _fallbackThumbnail() => const ColoredBox(
        color: AuryelColors.surface,
        child: Center(
          child: Icon(Icons.waves_outlined,
              color: AuryelColors.goldLight, size: 38),
        ),
      );
}

class _EbooksTab extends StatelessWidget {
  const _EbooksTab();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_WellbeingLibraryScreenState>();
    final ebooks = state?._availableEbooks() ?? const <WellbeingEbook>[];
    if (ebooks.isEmpty) {
      return const _EmptyUniverse(
        icon: Icons.menu_book_outlined,
        eyebrow: 'EBOOKS',
        title: 'De nouvelles lectures arrivent bientôt.',
        message: 'La bibliothèque s’enrichira prochainement de guides Auryel.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio: .62,
      ),
      itemCount: ebooks.length,
      itemBuilder: (context, index) => _EbookCard(ebook: ebooks[index]),
    );
  }
}

class _EbookCard extends StatelessWidget {
  const _EbookCard({required this.ebook});

  final WellbeingEbook ebook;

  @override
  Widget build(BuildContext context) {
    final canRead = ebook.pdfUrl?.startsWith('http') == true;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: canRead
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EbookReaderScreen(
                    title: ebook.title,
                    url: ebook.pdfUrl!,
                  ),
                ),
              )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ebook.coverUrl?.isNotEmpty == true
                  ? Image.network(ebook.coverUrl!, fit: BoxFit.cover)
                  : const _BookCoverPlaceholder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(ebook.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AuryelText.body(fontSize: 14, fontWeight: FontWeight.w600)),
          if (ebook.subtitle.trim().isNotEmpty)
            Text(ebook.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AuryelText.body(fontSize: 11, color: AuryelColors.textMuted)),
        ],
      ),
    );
  }
}

class _BookCoverPlaceholder extends StatelessWidget {
  const _BookCoverPlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AuryelColors.surface,
          border: Border.all(color: AuryelColors.warmBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Icon(Icons.menu_book_outlined,
              color: AuryelColors.goldLight, size: 44),
        ),
      );
}

class _EmptyUniverse extends StatelessWidget {
  const _EmptyUniverse({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 54, 28, 32),
        children: [
          Icon(icon, color: AuryelColors.goldLight, size: 42),
          const SizedBox(height: 22),
          Text(
            eyebrow,
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AuryelColors.gold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AuryelText.display(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AuryelText.body(color: AuryelColors.textSecondary, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      );
}

class _NoopListenable extends ChangeNotifier {}

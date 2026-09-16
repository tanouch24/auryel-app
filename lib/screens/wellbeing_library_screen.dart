import 'package:flutter/material.dart';

import '../api/wellbeing_ebooks_api.dart';
import '../data/content_repository.dart';
import '../data/relaxation_video.dart';
import '../state/wellbeing_ebooks_controller.dart';
import '../state/wellbeing_program_controller.dart';
import '../theme/auryel_theme.dart';
import 'ebook_reader_screen.dart';
import 'relaxation_video_feed_screen.dart';

/// Bibliothèque Bien-être V1 : trois univers éditoriaux, sans mélange entre
/// exercices, vidéos de relaxation et lectures longues.
class WellbeingLibraryScreen extends StatefulWidget {
  const WellbeingLibraryScreen({super.key, this.ebooksController});

  final WellbeingEbooksController? ebooksController;

  @override
  State<WellbeingLibraryScreen> createState() => _WellbeingLibraryScreenState();
}

class _WellbeingLibraryScreenState extends State<WellbeingLibraryScreen> {
  WellbeingEbooksController? _ebooks;
  WellbeingProgramController? _program;
  late Future<List<RelaxationVideo>> _videos;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ebooks != null) return;
    _ebooks = widget.ebooksController ?? WellbeingEbooksScope.maybeOf(context);
    _program = WellbeingProgramScope.maybeOf(context);
    final content = ContentScope.maybeOf(context);
    _videos = content?.meditationVideos() ??
        Future.value(const <RelaxationVideo>[]);
  }

  Future<void> openMeditations() async {
    final videos = await _videos;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RelaxationVideoFeedScreen(videos: videos),
      ),
    );
  }

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
              _LibraryTabs(onMeditations: openMeditations),
              Expanded(
                child: TabBarView(
                  children: [
                    const _ExercisesTab(),
                    _MeditationsPreview(onOpen: openMeditations),
                    _EbooksTab(ebooks: _availableEbooks()),
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
  const _LibraryTabs({required this.onMeditations});

  final VoidCallback onMeditations;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: AuryelColors.warmBorder.withValues(alpha: .8),
        ),
      ),
    ),
    child: TabBar(
      onTap: (index) {
        if (index == 1) onMeditations();
      },
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
  Widget build(BuildContext context) => const _EmptyUniverse(
    icon: Icons.self_improvement_outlined,
    eyebrow: 'EXERCICES',
    title: 'Des pratiques guidées arrivent bientôt.',
    message: 'Nous préparons des formats courts pour respirer, relâcher la pression et retrouver ton rythme.',
  );
}

class _MeditationsPreview extends StatelessWidget {
  const _MeditationsPreview({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 52, 24, 32),
    children: [
      const Icon(
        Icons.play_circle_outline,
        color: AuryelColors.goldLight,
        size: 48,
      ),
      const SizedBox(height: 20),
      Text(
        'MÉDITATIONS',
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
        'Entre dans ton espace de relaxation.',
        textAlign: TextAlign.center,
        style: AuryelText.display(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      Text(
        'Des vidéos immersives pour ralentir, respirer et laisser la journée s’apaiser.',
        textAlign: TextAlign.center,
        style: AuryelText.body(color: AuryelColors.textSecondary, height: 1.5),
      ),
      const SizedBox(height: 26),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Ouvrir l’expérience'),
        ),
      ),
    ],
  );
}

class _EbooksTab extends StatelessWidget {
  const _EbooksTab({required this.ebooks});

  final List<WellbeingEbook> ebooks;

  @override
  Widget build(BuildContext context) {
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
                builder: (_) =>
                    EbookReaderScreen(title: ebook.title, url: ebook.pdfUrl!),
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
          Text(
            ebook.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AuryelText.body(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (ebook.subtitle.trim().isNotEmpty)
            Text(
              ebook.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AuryelText.body(
                fontSize: 11,
                color: AuryelColors.textMuted,
              ),
            ),
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
      child: Icon(
        Icons.menu_book_outlined,
        color: AuryelColors.goldLight,
        size: 44,
      ),
    ),
  );
}

class _EmptyUniverse extends StatelessWidget {
  const _EmptyUniverse({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String message;

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
    ],
  );
}

class _NoopListenable extends ChangeNotifier {}

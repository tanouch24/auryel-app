import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/content_repository.dart';
import '../data/meditation_catalog.dart';
import '../data/meditation_item.dart';
import '../api/wellbeing_ebooks_api.dart';
import '../state/wellbeing_ebooks_controller.dart';
import '../state/wellbeing_program_controller.dart';
import '../theme/auryel_theme.dart';
import 'ebook_reader_screen.dart';
import 'meditation_feed_screen.dart';

/// Bibliothèque Bien-être unique, dérivée uniquement des contenus disponibles.
class WellbeingLibraryScreen extends StatefulWidget {
  const WellbeingLibraryScreen({super.key, this.ebooksController});

  final WellbeingEbooksController? ebooksController;

  @override
  State<WellbeingLibraryScreen> createState() => _WellbeingLibraryScreenState();
}

class _WellbeingLibraryScreenState extends State<WellbeingLibraryScreen> {
  List<MeditationItem> _meditations = const [];
  bool _loading = true;
  Object? _error;
  String _filter = 'Tout';
  ContentRepository? _content;
  WellbeingEbooksController? _ebooks;
  WellbeingProgramController? _program;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_content != null) return;
    _content = ContentScope.maybeOf(context);
    _ebooks = widget.ebooksController ?? WellbeingEbooksScope.maybeOf(context);
    _program = WellbeingProgramScope.maybeOf(context);
    _loadMeditations();
  }

  Future<void> _loadMeditations() async {
    try {
      final items = _content != null
          ? await _content!.meditations()
          : const MeditationCatalog().all;
      final playable = <MeditationItem>[];
      for (final item in items) {
        if (await _isPlayable(item)) playable.add(item);
      }
      if (!mounted) return;
      setState(() {
        _meditations = _dedup(playable);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<bool> _isPlayable(MeditationItem item) async {
    final source = item.playbackSource;
    if (source.startsWith('http://') || source.startsWith('https://')) return true;
    if (source.isEmpty) return false;
    try {
      await rootBundle.load('assets/$source');
      return true;
    } catch (_) {
      return false;
    }
  }

  static List<MeditationItem> _dedup(List<MeditationItem> items) {
    final seen = <String>{};
    return [for (final item in items) if (seen.add(item.id)) item];
  }

  List<WellbeingEbook> _availableEbooks(
    WellbeingEbooksController? controller,
  ) {
    final current = controller?.ebooks ?? const <WellbeingEbook>[];
    if (current.isNotEmpty) return current;

    // The released backend may still expose the existing ebook through the
    // legacy program response while the dedicated catalog is empty. Reuse
    // that real server content without surfacing the 30-day program UX.
    final legacy = WellbeingProgramScope.maybeReadOf(context)?.state?.ebook;
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

  List<String> get _filters {
    final values = <String>['Tout'];
    if (_meditations.isNotEmpty) values.add('Méditations');
    for (final item in _meditations) {
      if (!values.contains(item.category.label)) values.add(item.category.label);
    }
    if (_availableEbooks(_ebooks).isNotEmpty) values.add('Ebooks');
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final ebookController = _ebooks;
    final programController = _program;
    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          ebookController ?? _NoopListenable(),
          programController ?? _NoopListenable(),
        ]),
        builder: (context, _) {
          final ebooks = _availableEbooks(ebookController);
          final filters = _filters;
          final selected = filters.contains(_filter) ? _filter : 'Tout';
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                'Des moments pour ralentir, comprendre et prendre soin de toi.',
                style: AuryelText.body(color: AuryelColors.textSecondary),
              ),
              const SizedBox(height: 18),
              _filterBar(filters, selected),
              const SizedBox(height: 18),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null && _meditations.isEmpty && ebooks.isEmpty)
                _errorState()
              else if (_visibleCount(ebooks, selected) == 0)
                _emptyState()
              else ...[
                if (_showMeditations(selected)) ...[
                  _sectionTitle('Méditations'),
                  ..._meditations
                      .where((item) => _showMeditation(item, selected))
                      .map(_meditationCard),
                ],
                if (_showEbooks(ebooks, selected)) ...[
                  _sectionTitle('Ebooks'),
                  ...ebooks.map(_ebookCard),
                ],
              ],
              if (ebookController?.error != null && ebooks.isEmpty)
                _inlineError(ebookController!),
            ],
          );
        },
      ),
    );
  }

  Widget _filterBar(List<String> filters, String selected) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final value in filters) ...[
              ChoiceChip(
                label: Text(value),
                selected: selected == value,
                onSelected: (_) => setState(() => _filter = value),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(title, style: AuryelText.display(fontSize: 20, fontWeight: FontWeight.w600)),
      );

  Widget _meditationCard(MeditationItem item) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(item.title),
          subtitle: Text('${item.category.label} · ${item.durationLabel}\n${item.description}'),
          trailing: const Icon(Icons.play_circle_outline),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MeditationFeedScreen(initialItem: item)),
          ),
        ),
      );

  Widget _ebookCard(WellbeingEbook ebook) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: _cover(ebook.coverUrl),
          title: Text(ebook.title),
          subtitle: Text(ebook.subtitle),
          trailing: ebook.pdfUrl?.isNotEmpty == true
              ? const Icon(Icons.menu_book_outlined)
              : const Icon(Icons.lock_outline),
          onTap: ebook.pdfUrl?.isNotEmpty == true
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EbookReaderScreen(title: ebook.title, url: ebook.pdfUrl!),
                    ),
                  )
              : null,
        ),
      );

  Widget _cover(String? url) => SizedBox(
        width: 48,
        height: 64,
        child: url?.isNotEmpty == true
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _coverFallback()),
              )
            : _coverFallback(),
      );

  Widget _coverFallback() => DecoratedBox(
        decoration: BoxDecoration(color: AuryelColors.surfaceLight, borderRadius: BorderRadius.circular(6)),
        child: const Icon(Icons.menu_book_outlined, color: AuryelColors.goldLight),
      );

  Widget _inlineError(WellbeingEbooksController controller) => Row(
        children: [
          const Expanded(child: Text('Les ebooks sont momentanément indisponibles.')),
          TextButton(onPressed: controller.refresh, child: const Text('Réessayer')),
        ],
      );

  Widget _errorState() => Center(
        child: Column(
          children: [
            const Text('La bibliothèque est momentanément indisponible.'),
            TextButton(onPressed: _loadMeditations, child: const Text('Réessayer')),
          ],
        ),
      );

  Widget _emptyState() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: Text('De nouveaux contenus arrivent bientôt.')),
      );

  bool _showMeditations(String filter) => filter == 'Tout' || filter == 'Méditations' || _meditations.any((m) => m.category.label == filter);
  bool _showMeditation(MeditationItem item, String filter) => filter == 'Tout' || filter == 'Méditations' || item.category.label == filter;
  bool _showEbooks(List<WellbeingEbook> ebooks, String filter) => ebooks.isNotEmpty && (filter == 'Tout' || filter == 'Ebooks');
  int _visibleCount(List<WellbeingEbook> ebooks, String filter) => (_showEbooks(ebooks, filter) ? ebooks.length : 0) + (_showMeditations(filter) ? _meditations.where((m) => _showMeditation(m, filter)).length : 0);
}

class _NoopListenable extends ChangeNotifier {}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/wellbeing_program_api.dart';
import '../api/wellbeing_ebooks_api.dart';
import '../state/wellbeing_program_controller.dart';
import '../state/wellbeing_ebooks_controller.dart';
import '../theme/auryel_theme.dart';
import 'consultation_screen.dart';

class WellbeingProgramScreen extends StatefulWidget {
  const WellbeingProgramScreen({super.key, this.controller});

  final WellbeingProgramController? controller;

  @override
  State<WellbeingProgramScreen> createState() => _WellbeingProgramScreenState();
}

class _WellbeingProgramScreenState extends State<WellbeingProgramScreen> {
  WellbeingProgramController? _controller;
  bool _reminderAsked = false;
  bool _refreshRequested = false;

  WellbeingProgramController? get _program =>
      widget.controller ??
      _controller ??
      WellbeingProgramScope.maybeOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= WellbeingProgramScope.maybeOf(context);
    final controller = _program;
    if (controller != null && controller.state == null && !_refreshRequested) {
      _refreshRequested = true;
      controller.refresh();
    }
  }

  Future<void> _start() async {
    final controller = _program;
    if (controller == null) return;
    await controller.start();
    if (!mounted || controller.state?.started != true || _reminderAsked) return;
    _reminderAsked = true;
    final enabled = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Un rappel quotidien ?'),
        content: const Text(
          'Souhaites-tu recevoir un rappel quotidien pour tes 5 actions ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Pas maintenant'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui, me rappeler'),
          ),
        ],
      ),
    );
    if (enabled != null) await controller.setReminder(enabled);
  }

  Future<void> _openEbook(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _program;
    final ebooks = WellbeingEbooksScope.maybeOf(context);
    if (controller == null) {
      return _scaffold(_intro(null, const []));
    }
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        if (ebooks case final ebookController) ebookController,
      ]),
      builder: (context, _) {
        if (controller.loading && controller.state == null) {
          return _scaffold(const Center(child: CircularProgressIndicator()));
        }
        if (controller.error != null && controller.state == null) {
          return _scaffold(Center(child: _error(controller)));
        }
        final state = controller.state;
        if (state == null || !state.started) {
          return _scaffold(_intro(controller, ebooks?.ebooks ?? const []));
        }
        if (state.completed) {
          return _scaffold(_completed(state, ebooks?.ebooks ?? const []));
        }
        return _scaffold(_active(controller, state, ebooks));
      },
    );
  }

  Widget _intro(
    WellbeingProgramController? controller,
    List<WellbeingEbook> ebooks,
  ) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _title('Mon programme Bien-être'),
      const SizedBox(height: 18),
      const Text(
        'Pendant 30 jours, Auryel t’accompagne avec 5 petites actions quotidiennes pour prendre davantage soin de toi.',
      ),
      const SizedBox(height: 18),
      _librarySection(ebooks),
      const SizedBox(height: 18),
      const Text(
        'Je m’engage à prendre soin de moi pendant 30 jours.',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      const Text(
        'Pas besoin d’être parfait. Une journée incomplète n’annule pas le programme : reprendre le lendemain suffit.',
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: controller == null || controller.busy ? null : _start,
        child: const Text('Commencer mon programme'),
      ),
    ],
  );

  Widget _active(
    WellbeingProgramController controller,
    WellbeingProgramState state,
    WellbeingEbooksController? ebooksController,
  ) {
    final today = state.today!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _title('Mon programme Bien-être'),
        const SizedBox(height: 8),
        Text(
          'Jour ${today.dayNumber} sur 30',
          style: AuryelText.display(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textCream,
          ),
        ),
        Text(
          '${today.completedCount} sur 5 aujourd’hui',
          style: const TextStyle(color: AuryelColors.textMuted),
        ),
        if (today.completed) ...[
          const SizedBox(height: 8),
          const Text(
            'Programme du jour terminé ✓',
            style: TextStyle(color: AuryelColors.goldLight),
          ),
        ],
        const SizedBox(height: 12),
        ...today.actions
            .take(5)
            .map((action) => _actionCard(controller, action)),
        const SizedBox(height: 10),
        _librarySection(ebooksController?.ebooks ?? const []),
        if (ebooksController?.error != null) _libraryError(ebooksController!),
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          _error(controller),
        ],
      ],
    );
  }

  Widget _actionCard(
    WellbeingProgramController controller,
    WellbeingProgramAction action,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: action.completed,
            onChanged: action.completed || controller.busy
                ? null
                : (_) => controller.completeAction(
                    action.dayNumber,
                    action.actionSlot,
                  ),
            title: Text(
              action.text,
              style: TextStyle(
                decoration: action.completed
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConsultationScreen(
                  pendingContext:
                      'J’aimerais parler avec toi du conseil Bien-être du jour : ${action.text}',
                ),
              ),
            ),
            child: const Text('En parler à mon conseiller'),
          ),
        ],
      ),
    ),
  );

  Widget _completed(
    WellbeingProgramState state,
    List<WellbeingEbook> ebooks,
  ) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _title('30 jours pour prendre soin de toi ✓'),
      const SizedBox(height: 16),
      const Text(
        'Tu n’avais pas besoin d’être parfait. Tu avais simplement besoin de commencer, puis de recommencer.',
      ),
      const SizedBox(height: 22),
      Text(
        '${state.summary.daysWithActions} journées avec au moins 1 action réalisée',
      ),
      Text('${state.summary.totalActions} actions réalisées'),
      const SizedBox(height: 12),
      const Text('Programme terminé'),
      const SizedBox(height: 24),
      _librarySection(ebooks),
    ],
  );

  Widget _librarySection(List<WellbeingEbook> ebooks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Bibliothèque Auryel'),
      const SizedBox(height: 4),
      const Text('Des guides offerts pour prendre soin de toi.'),
      const SizedBox(height: 10),
      if (ebooks.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Ton premier guide arrive bientôt.'),
          ),
        )
      else
        ...ebooks.map(_ebookCard),
    ],
  );

  Widget _ebookCard(WellbeingEbook ebook) {
    final pdfUrl = ebook.pdfUrl?.trim();
    final coverUrl = ebook.coverUrl?.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              height: 88,
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _coverPlaceholder(),
                      ),
                    )
                  : _coverPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ebook.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(ebook.subtitle),
                  if (ebook.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      ebook.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (pdfUrl != null && pdfUrl.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _openEbook(pdfUrl),
                        child: const Text('Lire l’ebook'),
                      ),
                    )
                  else
                    const Text(
                      'Disponible prochainement',
                      style: TextStyle(color: AuryelColors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => DecoratedBox(
    decoration: BoxDecoration(
      color: AuryelColors.surfaceLight,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.menu_book_outlined, color: AuryelColors.goldLight),
  );

  Widget _libraryError(WellbeingEbooksController controller) => Row(
    children: [
      const Expanded(
        child: Text('La bibliothèque est momentanément indisponible.'),
      ),
      TextButton(onPressed: controller.refresh, child: const Text('Réessayer')),
    ],
  );

  Widget _error(WellbeingProgramController controller) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Le programme est momentanément indisponible.'),
      TextButton(onPressed: controller.refresh, child: const Text('Réessayer')),
    ],
  );

  Widget _title(String text) => Text(
    text,
    style: AuryelText.display(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: AuryelColors.textCream,
    ),
  );

  Widget _scaffold(Widget body) => Scaffold(appBar: AppBar(), body: body);
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/wellbeing_program_api.dart';
import '../state/wellbeing_program_controller.dart';
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

  Future<void> _openEbook(WellbeingProgramEbook ebook) async {
    final url = ebook.pdfUrl?.trim();
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _program;
    if (controller == null) {
      return _scaffold(_intro(null));
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.loading && controller.state == null) {
          return _scaffold(const Center(child: CircularProgressIndicator()));
        }
        if (controller.error != null && controller.state == null) {
          return _scaffold(Center(child: _error(controller)));
        }
        final state = controller.state;
        if (state == null || !state.started) {
          return _scaffold(_intro(controller));
        }
        if (state.completed) return _scaffold(_completed(state));
        return _scaffold(_active(controller, state));
      },
    );
  }

  Widget _intro(WellbeingProgramController? controller) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _title('Mon programme Bien-être'),
      const SizedBox(height: 18),
      const Text(
        'Pendant 30 jours, Auryel t’accompagne avec 5 petites actions quotidiennes pour prendre davantage soin de toi.',
      ),
      const SizedBox(height: 18),
      _ebookCard(
        const WellbeingProgramEbook(
          title: '30 jours pour prendre soin de soi',
          subtitle: 'Le petit guide Bien-être Auryel',
          pdfUrl: null,
          version: 1,
          active: true,
        ),
      ),
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
        _ebookCard(state.ebook),
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

  Widget _completed(WellbeingProgramState state) => ListView(
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
    ],
  );

  Widget _ebookCard(WellbeingProgramEbook ebook) => Card(
    child: ListTile(
      title: Text(ebook.title),
      subtitle: Text(ebook.subtitle),
      trailing: ebook.pdfUrl?.trim().isNotEmpty == true
          ? TextButton(
              onPressed: () => _openEbook(ebook),
              child: const Text('Ouvrir mon ebook offert'),
            )
          : const Text('Offert'),
    ),
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

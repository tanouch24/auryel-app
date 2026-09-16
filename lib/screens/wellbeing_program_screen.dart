import 'package:flutter/material.dart';

import '../data/content_repository.dart';
import '../data/daily_thought.dart';
import '../state/consultation_controller.dart';
import '../state/wellbeing_ebooks_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/auryel_banner.dart';
import 'consultation_screen.dart';
import 'wellbeing_library_screen.dart';

/// Bien-être V1 : un contenu éditorial utile aujourd'hui, puis une
/// bibliothèque claire. Le programme historique reste hors du parcours actif.
class WellbeingProgramScreen extends StatefulWidget {
  const WellbeingProgramScreen({super.key});

  @override
  State<WellbeingProgramScreen> createState() => _WellbeingProgramScreenState();
}

class _WellbeingProgramScreenState extends State<WellbeingProgramScreen> {
  DailyThought? _thought;
  Object? _error;
  bool _loading = true;
  ContentRepository? _content;
  DailyThoughtRepository? _embeddedThoughts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_content != null) return;
    _content = ContentScope.maybeOf(context);
    _embeddedThoughts = _content == null ? DailyThoughtRepository() : null;
    _loadToday();
  }

  Future<void> _loadToday() async {
    try {
      final thought = _content != null
          ? await _content!.thoughtFor(DateTime.now())
          : await _embeddedThoughts!.thoughtFor(DateTime.now());
      if (!mounted) return;
      setState(() {
        _thought = thought;
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

  void _openConsultation() {
    final thought = _thought;
    if (thought == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConsultationScreen(
          pendingContext:
              'J’aimerais parler avec toi de la pensée du jour : ${thought.phrase}\n\n${thought.interpretation}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ebooks = WellbeingEbooksScope.maybeOf(context);
    return TickerMode(
      // V1 Bien-être n'a pas d'animation persistante. Le ticker reste
      // désactivé afin qu'un RefreshIndicator monté hors écran ne conserve
      // pas de callback après une navigation/transition.
      enabled: false,
      child: _scaffold(
        RefreshIndicator(
          onRefresh: _loadToday,
          color: AuryelColors.goldLight,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            Text(
              'BIEN-ÊTRE',
              style: AuryelText.body(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AuryelColors.gold,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Aujourd’hui',
              style: AuryelText.display(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const SizedBox(
                height: 230,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null || _thought == null)
              _errorState()
            else ...[
              _todayCard(_thought!),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _openConsultation,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('En parler à mon conseiller'),
                ),
              ),
            ],
            const SizedBox(height: 28),
            _libraryEntry(ebooks),
          ],
        ),
          ),
        ),
    );
  }

  Widget _todayCard(DailyThought thought) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: AuryelColors.goldLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RÉFLEXION DU JOUR',
                    style: AuryelText.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AuryelColors.gold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                thought.phrase,
                style: AuryelText.display(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                thought.interpretation,
                style: AuryelText.body(
                  fontSize: 14,
                  height: 1.55,
                  color: AuryelColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _libraryEntry(WellbeingEbooksController? ebooks) {
    final count = ebooks?.ebooks.length ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WellbeingLibraryScreen(ebooksController: ebooks),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            children: [
              const Icon(
                Icons.menu_book_outlined,
                color: AuryelColors.goldLight,
                size: 27,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bibliothèque',
                      style: AuryelText.display(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? 'Méditations et guides à découvrir'
                          : '$count guide${count > 1 ? 's' : ''} · méditations disponibles',
                      style: AuryelText.body(
                        fontSize: 12.5,
                        color: AuryelColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 17,
                color: AuryelColors.goldLight,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState() => Column(
        children: [
          const Text('Le contenu du jour est momentanément indisponible.'),
          TextButton(onPressed: _loadToday, child: const Text('Réessayer')),
        ],
      );

  Widget _scaffold(Widget body) {
    final consultation = ConsultationScope.maybeReadOf(context);
    final banner = consultation == null
        ? const SizedBox.shrink()
        : ListenableBuilder(
            listenable: consultation,
            builder: (context, _) => AuryelBanner(
              isPremium: consultation.quota?.isPremium,
            ),
          );
    return Scaffold(
      appBar: AppBar(),
      body: Column(children: [Expanded(child: body), banner]),
    );
  }
}

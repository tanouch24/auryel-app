import 'package:flutter/material.dart';

import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'advisor_selection_screen.dart';

const _feedbackChoices = [
  'C’est assez juste',
  'Pas vraiment',
  'Je ne sais pas encore',
];

/// Étape 3/5 — « Parle-moi un peu de toi ». Portrait personnalisé SIMULÉ : le
/// texte affiché vient uniquement de `state.portraitData` (jamais codé en dur
/// ici) afin que le vrai serveur puisse le remplacer au Temps 2 sans toucher
/// cet écran. Le retour de l'utilisateur alimente la mémoire du conseiller.
class PortraitScreen extends StatefulWidget {
  const PortraitScreen({super.key});

  @override
  State<PortraitScreen> createState() => _PortraitScreenState();
}

class _PortraitScreenState extends State<PortraitScreen> {
  String? _choice;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _continue() {
    final note = _noteController.text.trim();
    final feedback = [
      ?_choice,
      if (note.isNotEmpty) note,
    ].join(' — ');
    final state = AuryelStateScope.of(context);
    // Ne pas écraser un retour déjà donné par un vide (retour arrière).
    if (feedback.isNotEmpty) {
      state.setPortraitFeedback(feedback);
    } else if (state.portraitFeedback == null ||
        state.portraitFeedback!.isEmpty) {
      state.setPortraitFeedback('Aucun retour');
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdvisorSelectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portraitText = AuryelStateScope.of(context).portraitData ?? '';
    return OnboardingScaffold(
      step: 3,
      totalSteps: 5,
      title: 'Parle-moi un peu de toi',
      subtitle: 'Voilà ce que je perçois déjà — dis-moi si je me trompe.',
      ctaLabel: 'Continuer',
      onCta: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AuryelColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AuryelColors.warmBorder),
            ),
            child: Text(
              portraitText,
              style: AuryelText.display(
                fontSize: 18,
                fontStyle: FontStyle.italic,
                height: 1.5,
                color: AuryelColors.textCream,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Dis-moi si je me trompe',
            style: AuryelText.display(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _feedbackChoices.map((choice) {
              final selected = choice == _choice;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _choice = choice),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AuryelColors.gold.withValues(alpha: 0.14)
                          : AuryelColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AuryelColors.gold
                            : AuryelColors.warmBorder,
                        width: selected ? 1.3 : 1,
                      ),
                    ),
                    child: Text(
                      choice,
                      style: AuryelText.body(
                        fontSize: 12.5,
                        color: selected
                            ? AuryelColors.goldLight
                            : AuryelColors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            maxLines: 2,
            style: AuryelText.body(fontSize: 14, color: AuryelColors.textCream),
            cursorColor: AuryelColors.gold,
            decoration: InputDecoration(
              hintText: 'Précise si tu veux (facultatif)',
              hintStyle: AuryelText.body(
                fontSize: 14,
                color: AuryelColors.textMuted,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AuryelColors.warmBorder),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AuryelColors.gold, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

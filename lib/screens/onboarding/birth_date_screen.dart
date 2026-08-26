import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'portrait_screen.dart';

const _mockPortraitText =
    'Tu sembles avancer avec beaucoup d’intuition, mais tu as parfois besoin de '
    'comprendre les choses jusqu’au bout avant de vraiment lâcher prise. Tu '
    'accordes beaucoup d’importance aux liens sincères et tu ressens vite '
    'lorsqu’une situation manque de clarté.';

/// Étape 3/5 — date de naissance. Ne génère aucune prédiction : la valeur
/// sert plus tard au portrait, à la numérologie et au contexte du conseiller.
class BirthDateScreen extends StatefulWidget {
  const BirthDateScreen({super.key});

  @override
  State<BirthDateScreen> createState() => _BirthDateScreenState();
}

class _BirthDateScreenState extends State<BirthDateScreen> {
  DateTime? _picked;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _picked ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'DATE DE NAISSANCE',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AuryelColors.gold,
              onPrimary: AuryelColors.backgroundDeep,
              surface: AuryelColors.surface,
              onSurface: AuryelColors.textCream,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AuryelColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (result != null) setState(() => _picked = result);
  }

  void _continue() {
    final date = _picked;
    if (date == null) return;
    final state = AuryelStateScope.of(context);
    state.setBirthDate(date);
    // Texte simulé — stocké dans portraitData, pas codé en dur dans l'écran
    // suivant, pour que le vrai serveur puisse remplacer la valeur au Temps 2.
    state.setPortraitData(_mockPortraitText);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PortraitScreen()));
  }

  String _format(DateTime d) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 3,
      totalSteps: 5,
      title: 'Quelle est ta date de naissance ?',
      subtitle: 'Elle nourrira ton portrait et certains éclairages plus tard.',
      ctaLabel: 'Continuer',
      ctaEnabled: _picked != null,
      onCta: _continue,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: AuryelColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _picked != null
                    ? AuryelColors.gold.withValues(alpha: 0.5)
                    : AuryelColors.warmBorder,
              ),
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsThin.calendarBlank,
                  size: 22,
                  color: AuryelColors.gold,
                ),
                const SizedBox(width: 14),
                Text(
                  _picked == null ? 'Choisir une date' : _format(_picked!),
                  style: AuryelText.body(
                    fontSize: 15,
                    color: _picked == null
                        ? AuryelColors.textMuted
                        : AuryelColors.textCream,
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

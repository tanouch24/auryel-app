import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/birth_date_parser.dart';
import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'portrait_screen.dart';

const _mockPortraitText =
    'Tu sembles avancer avec beaucoup d’intuition, mais tu as parfois besoin de '
    'comprendre les choses jusqu’au bout avant de vraiment lâcher prise. Tu '
    'accordes beaucoup d’importance aux liens sincères et tu ressens vite '
    'lorsqu’une situation manque de clarté.';

/// Étape 2/5 — date de naissance en SAISIE LIBRE. Aucune prédiction : la valeur
/// nourrit plus tard le portrait, la numérologie et le contexte du conseiller.
///
/// Le champ texte est le mode principal ; le calendrier reste accessible en
/// option secondaire (petite icône), jamais imposé. La normalisation est
/// déléguée à [parseBirthDate] (testé à part).
///
/// RÈGLE 18+ (J2) : Auryel est réservé aux 18 ans ou plus. C'est ICI que la
/// règle est appliquée à la création de compte — une date valide mais < 18 ans
/// ([meetsMinimumAge] == false) laisse « Continuer » désactivé et affiche
/// [kMinimumAgeMessage] ; l'onboarding ne peut pas se terminer.
class BirthDateScreen extends StatefulWidget {
  const BirthDateScreen({super.key});

  @override
  State<BirthDateScreen> createState() => _BirthDateScreenState();
}

class _BirthDateScreenState extends State<BirthDateScreen> {
  final _controller = TextEditingController();
  DateTime? _parsed;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    // Préremplissage lisible d'une date déjà connue (retour arrière / reprise).
    final existing = AuryelStateScope.of(context).birthDate;
    if (existing != null) {
      _controller.text = formatBirthDateFr(existing);
      _parsed = parseBirthDate(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _parsed = parseBirthDate(value));
  }

  /// Date valide MAIS âge < 18 : on distingue ce cas de « date illisible » pour
  /// afficher le bon message.
  bool get _tooYoung => _parsed != null && !meetsMinimumAge(_parsed!);

  Future<void> _pickFromCalendar() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _parsed ?? DateTime(now.year - 25),
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
    if (result == null) return;
    // On repasse par le champ texte pour rester cohérent (une seule source).
    _controller.text = formatBirthDateFr(result);
    setState(() => _parsed = parseBirthDate(_controller.text));
  }

  void _continue() {
    final date = _parsed;
    // Refus propre : date absente/illisible OU âge < 18 ans. On n'écrit rien
    // dans l'état, on ne navigue pas -> l'onboarding ne peut pas se terminer.
    if (date == null || !meetsMinimumAge(date)) return;
    final state = AuryelStateScope.of(context);
    state.setBirthDate(date);
    // Texte simulé — stocké dans portraitData, pas codé en dur dans l'écran
    // suivant, pour que le vrai serveur puisse remplacer la valeur au Temps 2.
    // On ne l'écrase PAS si un portrait a déjà été produit (reprise / retour).
    if (state.portraitData == null || state.portraitData!.isEmpty) {
      state.setPortraitData(_mockPortraitText);
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PortraitScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final raw = _controller.text.trim();
    final showError = raw.isNotEmpty && _parsed == null;

    return OnboardingScaffold(
      step: 2,
      totalSteps: 5,
      title: 'Quelle est ta date de naissance ?',
      subtitle: 'Écris-la comme tu veux, par exemple 17 mai 2000.',
      ctaLabel: 'Continuer',
      ctaEnabled: _parsed != null && !_tooYoung,
      onCta: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.datetime,
                  style: AuryelText.display(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: AuryelColors.gold,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _continue(),
                  decoration: InputDecoration(
                    hintText: 'jj/mm/aaaa',
                    hintStyle: AuryelText.display(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: AuryelColors.textMuted,
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AuryelColors.warmBorder),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: AuryelColors.gold,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              // Option secondaire — jamais obligatoire.
              IconButton(
                tooltip: 'Choisir dans le calendrier',
                onPressed: _pickFromCalendar,
                icon: PhosphorIcon(
                  PhosphorIconsThin.calendarBlank,
                  size: 22,
                  color: AuryelColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_tooYoung)
            Text(
              kMinimumAgeMessage,
              style: AuryelText.body(
                fontSize: 13,
                height: 1.4,
                color: AuryelColors.textSecondary,
              ),
            )
          else if (_parsed != null)
            Text(
              '${formatBirthDateFr(_parsed!)} ✓',
              style: AuryelText.body(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            )
          else if (showError)
            Text(
              'Vérifie ta date de naissance',
              style: AuryelText.body(
                fontSize: 13,
                color: AuryelColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

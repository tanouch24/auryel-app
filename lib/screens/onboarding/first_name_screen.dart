import 'package:flutter/material.dart';

import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'birth_date_screen.dart';

/// Étape 1/6 — prénom. Le choix du conseiller reste disponible dans l'app,
/// mais ne bloque plus la création du compte.
class FirstNameScreen extends StatefulWidget {
  const FirstNameScreen({super.key});

  @override
  State<FirstNameScreen> createState() => _FirstNameScreenState();
}

class _FirstNameScreenState extends State<FirstNameScreen> {
  final _controller = TextEditingController();
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    // Préremplissage d'une valeur déjà saisie (retour arrière, reprise
    // d'onboarding). On n'écrase jamais avec du vide.
    final existing = AuryelStateScope.of(context).firstName;
    if (existing != null && existing.trim().isNotEmpty) {
      _controller.text = existing;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    AuryelStateScope.of(context).setFirstName(name);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BirthDateScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 1,
      totalSteps: 6,
      showBack: false,
      title: 'Comment veux-tu qu’on t’appelle ?',
      ctaLabel: 'Continuer',
      ctaEnabled: _controller.text.trim().isNotEmpty,
      onCta: _continue,
      child: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: AuryelText.display(fontSize: 22, fontWeight: FontWeight.w500),
        cursorColor: AuryelColors.gold,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _continue(),
        decoration: InputDecoration(
          hintText: 'Ton prénom',
          hintStyle: AuryelText.display(
            fontSize: 22,
            fontWeight: FontWeight.w500,
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../theme/auryel_theme.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'email_auth_screen.dart';

/// Étape 5/5 — création de compte.
///
/// « Continuer avec email » lance l'auth RÉELLE (OTP backend, cf.
/// [EmailAuthScreen]). Apple / Google restent affichés mais NE simulent plus
/// aucune connexion : ils informent que le canal n'est pas encore disponible
/// (F1 ne couvre que l'email).
class AccountCreationScreen extends StatelessWidget {
  const AccountCreationScreen({super.key});

  void _openEmailAuth(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
    );
  }

  void _notAvailable(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider arrive bientôt. Continue avec ton email.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 5,
      totalSteps: 5,
      title: 'Sauvegarde ton espace',
      subtitle: 'Pour retrouver ton conseiller et tes échanges.',
      child: Column(
        children: [
          _AuthButton(
            icon: PhosphorIconsFill.appleLogo,
            label: 'Continuer avec Apple',
            onTap: () => _notAvailable(context, 'Apple'),
          ),
          const SizedBox(height: 12),
          _AuthButton(
            icon: PhosphorIconsBold.googleLogo,
            label: 'Continuer avec Google',
            onTap: () => _notAvailable(context, 'Google'),
          ),
          const SizedBox(height: 12),
          _AuthButton(
            icon: PhosphorIconsRegular.envelopeSimple,
            label: 'Continuer avec email',
            onTap: () => _openEmailAuth(context),
          ),
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final PhosphorIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
            decoration: BoxDecoration(
              color: AuryelColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AuryelColors.warmBorder),
            ),
            child: Row(
              children: [
                PhosphorIcon(icon, size: 20, color: AuryelColors.goldLight),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: AuryelText.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AuryelColors.textCream,
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

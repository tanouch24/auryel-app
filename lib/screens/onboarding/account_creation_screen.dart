import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../state/auryel_state.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/main_nav_shell.dart';
import '../../widgets/onboarding_scaffold.dart';

/// Étape 5/5 — création de compte SIMULÉE. Les 3 boutons sont VISUELS
/// UNIQUEMENT : aucun Firebase Auth, aucun Sign in with Apple/Google réel,
/// aucun mot de passe. N'importe lequel simule une authentification réussie,
/// génère un `userId` factice (`temp_<...>`, jamais l'email) et clôt
/// l'onboarding. Cette structure pourra être remplacée par l'auth réelle
/// au Temps 2 sans retoucher l'écran.
class AccountCreationScreen extends StatefulWidget {
  const AccountCreationScreen({super.key});

  @override
  State<AccountCreationScreen> createState() => _AccountCreationScreenState();
}

class _AccountCreationScreenState extends State<AccountCreationScreen> {
  bool _loading = false;

  Future<void> _simulateAuth() async {
    if (_loading) return;
    setState(() => _loading = true);
    await AuryelStateScope.of(context).completeOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 5,
      totalSteps: 5,
      title: 'Sauvegarde ton espace',
      subtitle: 'Pour retrouver ton conseiller et tes échanges.',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AuryelColors.gold),
              ),
            )
          : Column(
              children: [
                _AuthButton(
                  icon: PhosphorIconsFill.appleLogo,
                  label: 'Continuer avec Apple',
                  onTap: _simulateAuth,
                ),
                const SizedBox(height: 12),
                _AuthButton(
                  icon: PhosphorIconsBold.googleLogo,
                  label: 'Continuer avec Google',
                  onTap: _simulateAuth,
                ),
                const SizedBox(height: 12),
                _AuthButton(
                  icon: PhosphorIconsRegular.envelopeSimple,
                  label: 'Continuer avec email',
                  onTap: _simulateAuth,
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

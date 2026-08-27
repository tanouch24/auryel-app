import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../state/auth_controller.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'otp_code_screen.dart';

/// Étape 5a — saisie de l'email. Déclenche `POST /api/auth/request-code`
/// puis pousse l'écran de saisie du code. Auth RÉELLE (remplace le faux
/// bouton "Continuer avec email").
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _valid => _emailRe.hasMatch(_controller.text.trim());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();
    if (!_valid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthScope.of(context).requestCode(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtpCodeScreen(email: email)),
      );
    } on ApiNetworkException {
      _fail('Connexion impossible. Vérifie ta connexion et réessaie.');
    } on ApiException {
      _fail('Impossible d’envoyer le code pour l’instant. Réessaie plus tard.');
    } catch (_) {
      _fail('Une erreur est survenue. Réessaie.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 5,
      totalSteps: 5,
      title: 'Ton adresse email',
      subtitle: 'On t’envoie un code à 6 chiffres pour sécuriser ton espace.',
      ctaLabel: _loading ? 'Envoi…' : 'Recevoir mon code',
      ctaEnabled: _valid && !_loading,
      onCta: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: AuryelText.display(fontSize: 20, fontWeight: FontWeight.w500),
            cursorColor: AuryelColors.gold,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'toi@exemple.com',
              hintStyle: AuryelText.display(
                fontSize: 20,
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
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

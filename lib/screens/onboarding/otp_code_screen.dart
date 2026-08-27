import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../state/auryel_state.dart';
import '../../state/auth_controller.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/main_nav_shell.dart';
import '../../widgets/onboarding_scaffold.dart';

/// Étape 5b — saisie du code à 6 chiffres. Vérifie via
/// `POST /api/auth/verify-code`, stocke le jeton (flutter_secure_storage via
/// le repository), confirme via `GET /api/account`, puis clôt l'onboarding
/// local avec le VRAI `user_id` et entre dans l'app.
class OtpCodeScreen extends StatefulWidget {
  const OtpCodeScreen({super.key, required this.email});

  final String email;

  @override
  State<OtpCodeScreen> createState() => _OtpCodeScreenState();
}

class _OtpCodeScreenState extends State<OtpCodeScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _error;

  bool get _valid => _controller.text.trim().length == 6;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_valid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = AuthScope.of(context);
    final state = AuryelStateScope.of(context);
    try {
      await auth.verifyCode(widget.email, _controller.text.trim());
      // Auth OK (jeton stocké). Clôt l'onboarding local avec le vrai user_id
      // s'il a pu être récupéré (sinon fallback interne du state).
      await state.completeOnboarding(userId: auth.account?.userId);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavShell()),
        (route) => false,
      );
    } on ApiUnauthorizedException {
      _fail('Code incorrect ou expiré. Redemande un code.');
    } on ApiException {
      _fail('Code incorrect ou expiré.');
    } on ApiNetworkException {
      _fail('Connexion impossible. Réessaie dans un instant.');
    } catch (_) {
      _fail('Une erreur est survenue. Réessaie.');
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await AuthScope.of(context).requestCode(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau code envoyé.')),
      );
    } catch (_) {
      _fail('Impossible de renvoyer le code pour l’instant.');
    } finally {
      if (mounted) setState(() => _resending = false);
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
      title: 'Entre ton code',
      subtitle: 'Envoyé à ${widget.email}.',
      ctaLabel: _loading ? 'Vérification…' : 'Valider',
      ctaEnabled: _valid && !_loading,
      onCta: _verify,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_loading,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AuryelText.display(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 10,
            ),
            cursorColor: AuryelColors.gold,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: AuryelText.display(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
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
          const SizedBox(height: 20),
          TextButton(
            onPressed: _loading || _resending ? null : _resend,
            child: Text(
              _resending ? 'Envoi…' : 'Renvoyer le code',
              style: AuryelText.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

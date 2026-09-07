import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../state/auryel_state.dart';
import '../../state/auth_controller.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/main_nav_shell.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'first_name_screen.dart';

/// Connexion AUTH V2 — email + mot de passe, AUCUN code OTP.
///
/// Écran de retour : splash (session absente / expirée), déconnexion, 401
/// rencontré en cours d'usage, ou lien « J'ai déjà un compte » depuis la
/// création. En cas de succès : jeton stocké (comme avant), onboarding local
/// marqué terminé, entrée dans l'app.
///
/// Cas legacy : un ancien compte créé par code OTP n'a pas encore de mot de
/// passe -> le backend répond 409 `password_not_set`. On l'explique sans jargon
/// et on propose un SEAM « Définir mon mot de passe » — l'endpoint public
/// correspondant n'existe pas encore côté backend (cf. rapport). On ne relance
/// JAMAIS l'OTP en douce.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _loading = false;
  String? _error;
  bool _needsPasswordSetup = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _formValid =>
      _emailRe.hasMatch(_emailCtrl.text.trim()) &&
      _passwordCtrl.text.isNotEmpty;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formValid || _loading) return;
    FocusScope.of(context).unfocus();
    final auth = AuthScope.of(context);
    final state = AuryelStateScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
      _needsPasswordSetup = false;
    });
    try {
      await auth.loginWithPassword(_emailCtrl.text.trim(), _passwordCtrl.text);
      _passwordCtrl.clear(); // le mot de passe n'est plus nécessaire
      if (!mounted) return;
      // CHANGEMENT DE COMPTE : si un AUTRE utilisateur se connecte sur cet
      // appareil (userId authentifié ≠ userId local), on efface l'identité
      // locale de l'utilisateur précédent (prénom / conseiller / DOB) — jamais
      // affichée au nouvel utilisateur. Même utilisateur -> on conserve.
      final newUserId = auth.account?.userId;
      final oldUserId = state.userId;
      if (newUserId != null &&
          oldUserId != null &&
          oldUserId != newUserId &&
          !oldUserId.startsWith('temp_')) {
        await state.forgetLocalIdentity();
        if (!mounted) return;
      }
      await state.completeOnboarding(userId: newUserId);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavShell()),
        (route) => false,
      );
    } on ApiUnauthorizedException {
      _fail('Email ou mot de passe incorrect.');
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.code == 'password_not_set') {
        _passwordCtrl.clear();
        _fail(
          'Ton compte Auryel existe déjà, mais aucun mot de passe n’y est '
          'encore associé.',
          needsPasswordSetup: true,
        );
      } else if (e.statusCode == 429) {
        _fail(
          'Trop de tentatives. Patiente quelques minutes avant de réessayer.',
        );
      } else if (e.statusCode == 503) {
        _fail(
          'Service temporairement indisponible. Réessaie dans quelques '
          'instants.',
        );
      } else {
        _fail('Connexion impossible pour le moment. Réessaie.');
      }
    } on ApiNetworkException {
      _fail('Connexion impossible. Vérifie ta connexion et réessaie.');
    } catch (_) {
      _fail('Une erreur est survenue. Réessaie.');
    }
  }

  void _fail(String message, {bool needsPasswordSetup = false}) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
      _needsPasswordSetup = needsPasswordSetup;
    });
  }

  void _goCreateAccount() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const FirstNameScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 5,
      totalSteps: 5,
      title: 'Bon retour',
      subtitle: 'Connecte-toi avec ton email et ton mot de passe.',
      ctaLabel: _loading ? 'Connexion…' : 'Se connecter',
      ctaEnabled: _formValid && !_loading,
      onCta: _submit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthEmailField(
            controller: _emailCtrl,
            enabled: !_loading,
            onChanged: () => setState(() => _error = null),
            onSubmitted: _passwordFocus.requestFocus,
          ),
          const SizedBox(height: 22),
          AuthPasswordField(
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            enabled: !_loading,
            obscure: _obscure,
            newPassword: false,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
            onChanged: () => setState(() => _error = null),
            onSubmitted: _submit,
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
          if (_needsPasswordSetup) ...[
            const SizedBox(height: 12),
            AuthSecondaryLink(
              label: 'Définir mon mot de passe',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'La définition d’un mot de passe pour les anciens comptes '
                      'arrive très bientôt.',
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 18),
          AuthSecondaryLink(
            label: 'Créer un compte',
            onTap: _loading ? null : _goCreateAccount,
          ),
        ],
      ),
    );
  }
}

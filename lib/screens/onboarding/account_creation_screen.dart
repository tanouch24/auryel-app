import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../state/auryel_state.dart';
import '../../state/auth_controller.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/advisors_carousel.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/onboarding_scaffold.dart';
import '../auryel_experience_screen.dart';
import 'email_auth_screen.dart';

/// Étape 5/5 — création de compte AUTH V2 : email + mot de passe, AUCUN code OTP.
///
/// Succès `POST /api/app/auth/register` -> jeton stocké (comme avant) ->
/// `PATCH /api/app/profile` (guide + prénom + date issus de l'onboarding local)
/// -> `completeOnboarding` + entrée dans l'app. On ne clôt l'onboarding QUE si
/// le PATCH réussit (sinon 1re consultation avec `guide=selena` par défaut).
///
/// Apple / Google : traités dans un lot séparé (non affichés ici).
class AccountCreationScreen extends StatefulWidget {
  const AccountCreationScreen({super.key});

  @override
  State<AccountCreationScreen> createState() => _AccountCreationScreenState();
}

enum _Phase { form, syncing, syncRetry, syncBlocked }

class _AccountCreationScreenState extends State<AccountCreationScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  _Phase _phase = _Phase.form;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// `true` sur 409 email_taken -> on propose « Se connecter ».
  bool _emailTaken = false;

  static const _minPassword = 8;
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _formValid =>
      _emailRe.hasMatch(_emailCtrl.text.trim()) &&
      _passwordCtrl.text.length >= _minPassword;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _register() async {
    if (!_formValid || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _emailTaken = false;
    });
    final auth = AuthScope.of(context);
    final password = _passwordCtrl.text;
    try {
      await auth.registerWithPassword(_emailCtrl.text.trim(), password);
      _passwordCtrl.clear(); // le mot de passe n'est plus nécessaire
    } on ApiUnauthorizedException {
      return _failForm('Une erreur est survenue. Réessaie.');
    } on ApiException catch (e) {
      if (e.statusCode == 400 && e.code == 'invalid_email') {
        return _failForm('Adresse email invalide.');
      }
      if (e.statusCode == 400 && e.code == 'weak_password') {
        return _failForm(
          'Le mot de passe doit contenir au moins 8 caractères.',
        );
      }
      if (e.statusCode == 409 && e.code == 'email_taken') {
        return _failForm(
          'Un compte existe déjà avec cette adresse email.',
          emailTaken: true,
        );
      }
      if (e.statusCode == 429) {
        return _failForm(
          'Trop de tentatives. Patiente quelques minutes avant de réessayer.',
        );
      }
      if (e.statusCode == 503) {
        return _failForm(
          'Service temporairement indisponible. Réessaie dans '
          'quelques instants.',
        );
      }
      return _failForm('Création impossible pour le moment. Réessaie.');
    } on ApiNetworkException {
      return _failForm(
        'Connexion impossible. Vérifie ta connexion et réessaie.',
      );
    } catch (_) {
      return _failForm('Une erreur est survenue. Réessaie.');
    }
    // Authentifié -> synchro du profil onboarding.
    await _runSync();
  }

  /// Identique à l'ancien flux OTP : PATCH profil, puis clôture d'onboarding
  /// UNIQUEMENT sur succès. Rejouable si réseau/5xx, bloquant si donnée locale
  /// manquante (edge — l'onboarding remplit tout avant l'étape 5).
  Future<void> _runSync() async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.syncing;
      _busy = true;
      _error = null;
    });
    final auth = AuthScope.of(context);
    final state = AuryelStateScope.of(context);

    final advisor = advisorByNameOrNull(state.selectedAdvisor);
    final prenom = (state.firstName ?? '').trim();
    final birth = state.birthDate;
    if (advisor == null || prenom.isEmpty || birth == null) {
      return _failSync(
        _Phase.syncBlocked,
        'Ton profil d’onboarding est incomplet. Reviens en arrière pour le '
        'compléter avant de continuer.',
      );
    }

    final outcome = await auth.syncProfile(
      guide: advisor.guideKey,
      prenom: prenom,
      dateNaissance: _isoDate(birth),
    );
    if (!mounted) return;

    switch (outcome) {
      case ProfileSyncOutcome.ok:
        // Compte créé + profil synchronisé : on clôt l'onboarding local, puis
        // on présente l'expérience Auryel UNE fois (elle enchaîne ensuite sur
        // l'Accueil via « Découvrir Auryel »).
        await state.completeOnboarding(userId: auth.account?.userId);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuryelExperienceScreen()),
          (route) => false,
        );
      case ProfileSyncOutcome.unauthorized:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
          (route) => false,
        );
      case ProfileSyncOutcome.retryable:
        _failSync(
          _Phase.syncRetry,
          'La synchronisation de ton profil a échoué. Vérifie ta connexion '
          'puis réessaie.',
        );
    }
  }

  void _failForm(String message, {bool emailTaken = false}) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.form;
      _busy = false;
      _error = message;
      _emailTaken = emailTaken;
    });
  }

  void _failSync(_Phase phase, String message) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _busy = false;
      _error = message;
    });
  }

  void _goLogin() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EmailAuthScreen()));
  }

  // --- CTA selon la phase ------------------------------------------------
  String get _ctaLabel {
    switch (_phase) {
      case _Phase.form:
        return _busy ? 'Création…' : 'Créer mon compte';
      case _Phase.syncing:
        return 'Synchronisation…';
      case _Phase.syncRetry:
        return 'Réessayer';
      case _Phase.syncBlocked:
        return 'Revenir en arrière';
    }
  }

  bool get _ctaEnabled {
    switch (_phase) {
      case _Phase.form:
        return _formValid && !_busy;
      case _Phase.syncing:
        return false;
      case _Phase.syncRetry:
      case _Phase.syncBlocked:
        return true;
    }
  }

  void _onCta() {
    switch (_phase) {
      case _Phase.form:
        _register();
      case _Phase.syncing:
        break;
      case _Phase.syncRetry:
        _runSync();
      case _Phase.syncBlocked:
        Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 5,
      totalSteps: 5,
      title: 'Ton compte',
      subtitle: 'Pour retrouver ton conseiller et tes échanges.',
      ctaLabel: _ctaLabel,
      ctaEnabled: _ctaEnabled,
      onCta: _onCta,
      child: _phase == _Phase.form ? _formBody() : _statusBody(),
    );
  }

  Widget _formBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthEmailField(
          controller: _emailCtrl,
          enabled: !_busy,
          onChanged: () => setState(() => _error = null),
          onSubmitted: _passwordFocus.requestFocus,
        ),
        const SizedBox(height: 22),
        AuthPasswordField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          enabled: !_busy,
          obscure: _obscure,
          newPassword: true,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          onChanged: () => setState(() => _error = null),
          onSubmitted: _register,
        ),
        const SizedBox(height: 8),
        Text(
          'Au moins 8 caractères.',
          style: AuryelText.body(fontSize: 11.5, color: AuryelColors.textMuted),
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
        if (_emailTaken) ...[
          const SizedBox(height: 8),
          AuthSecondaryLink(
            label: 'Se connecter',
            onTap: _busy ? null : _goLogin,
          ),
        ],
        const SizedBox(height: 14),
        AuthSecondaryLink(
          label: 'J’ai déjà un compte',
          onTap: _busy ? null : _goLogin,
        ),
      ],
    );
  }

  Widget _statusBody() {
    final syncing = _phase == _Phase.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (syncing) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AuryelColors.gold,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                syncing
                    ? 'On prépare ton espace…'
                    : 'On n’a pas pu finaliser ton profil.',
                style: AuryelText.body(
                  fontSize: 14,
                  color: AuryelColors.textCream,
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: AuryelText.body(
              fontSize: 12.5,
              color: AuryelColors.goldLight,
            ),
          ),
        ],
      ],
    );
  }
}

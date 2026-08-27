import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../state/auryel_state.dart';
import '../../state/auth_controller.dart';
import '../../theme/auryel_theme.dart';
import '../../widgets/advisors_carousel.dart';
import '../../widgets/main_nav_shell.dart';
import '../../widgets/onboarding_scaffold.dart';
import 'email_auth_screen.dart';

enum _Phase {
  /// Saisie du code à 6 chiffres.
  code,

  /// Code vérifié, jeton stocké : synchro du profil onboarding en cours.
  syncing,

  /// Synchro échouée mais rejouable (réseau / 5xx) — jeton conservé.
  syncRetry,

  /// Donnée d'onboarding obligatoire manquante — impossible de synchroniser,
  /// l'utilisateur doit revenir en arrière compléter le parcours.
  syncBlocked,
}

/// Étape 5b — saisie du code à 6 chiffres.
///
/// Flux : `verify-code` (jeton stocké + `GET /api/account`) ->
/// `PATCH /api/app/profile` (guide + prénom + date de naissance issus de
/// l'onboarding local). `completeOnboarding` + entrée dans l'app UNIQUEMENT si
/// le PATCH réussit — sinon on ne veut pas d'une 1re consultation avec
/// `guide=selena` par défaut.
class OtpCodeScreen extends StatefulWidget {
  const OtpCodeScreen({super.key, required this.email});

  final String email;

  @override
  State<OtpCodeScreen> createState() => _OtpCodeScreenState();
}

class _OtpCodeScreenState extends State<OtpCodeScreen> {
  final _controller = TextEditingController();
  _Phase _phase = _Phase.code;
  bool _busy = false;
  bool _resending = false;
  String? _error;

  bool get _valid => _controller.text.trim().length == 6;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _verify() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AuthScope.of(context);
    try {
      await auth.verifyCode(widget.email, _controller.text.trim());
    } on ApiUnauthorizedException {
      return _failCode('Code incorrect ou expiré. Redemande un code.');
    } on ApiException {
      return _failCode('Code incorrect ou expiré.');
    } on ApiNetworkException {
      return _failCode('Connexion impossible. Réessaie dans un instant.');
    } catch (_) {
      return _failCode('Une erreur est survenue. Réessaie.');
    }
    // Authentifié : on enchaîne sur la synchro du profil.
    await _runSync();
  }

  Future<void> _runSync() async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.syncing;
      _busy = true;
      _error = null;
    });

    final auth = AuthScope.of(context);
    final state = AuryelStateScope.of(context);

    // 6. Validation locale — aucune synchro partielle silencieuse.
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
        // Seulement ici : on clôt l'onboarding local avec le vrai user_id.
        await state.completeOnboarding(userId: auth.account?.userId);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavShell()),
          (route) => false,
        );
      case ProfileSyncOutcome.unauthorized:
        // Session invalidée (jeton déjà purgé par AuthController) -> login.
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

  Future<void> _resend() async {
    if (_resending || _busy) return;
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
      _failCode('Impossible de renvoyer le code pour l’instant.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _failCode(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.code;
      _busy = false;
      _error = message;
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

  // --- CTA selon la phase --------------------------------------------------
  String get _ctaLabel {
    switch (_phase) {
      case _Phase.code:
        return _busy ? 'Vérification…' : 'Valider';
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
      case _Phase.code:
        return _valid && !_busy;
      case _Phase.syncing:
        return false;
      case _Phase.syncRetry:
      case _Phase.syncBlocked:
        return true;
    }
  }

  void _onCta() {
    switch (_phase) {
      case _Phase.code:
        _verify();
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
      title: 'Entre ton code',
      subtitle: 'Envoyé à ${widget.email}.',
      ctaLabel: _ctaLabel,
      ctaEnabled: _ctaEnabled,
      onCta: _onCta,
      child: _phase == _Phase.code ? _codeBody() : _statusBody(),
    );
  }

  Widget _codeBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
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
            style: AuryelText.body(fontSize: 12.5, color: AuryelColors.goldLight),
          ),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: _busy || _resending ? null : _resend,
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
    );
  }

  Widget _statusBody() {
    final syncing = _phase == _Phase.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (syncing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AuryelColors.gold,
                ),
              ),
            if (syncing) const SizedBox(width: 12),
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
            style: AuryelText.body(fontSize: 12.5, color: AuryelColors.goldLight),
          ),
        ],
      ],
    );
  }
}

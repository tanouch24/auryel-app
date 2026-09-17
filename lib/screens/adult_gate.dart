import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/birth_date_parser.dart';
import '../state/auth_controller.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../state/profile_restore.dart';
import '../theme/auryel_theme.dart';
import '../startup_trace.dart';
import '../widgets/gold_button.dart';
import '../widgets/main_nav_shell.dart';
import 'onboarding/email_auth_screen.dart';

/// VERROU 18+ — porte OBLIGATOIRE entre une session authentifiée/restaurée et
/// le contenu principal ([MainNavShell]).
///
/// Aucun utilisateur authentifié n'atteint [MainNavShell] tant que l'app n'a
/// pas établi qu'il a 18 ans ou plus. Couvre : restauration de session au
/// lancement, login email, retour après fermeture, changement de compte,
/// profil ancien / partiellement rempli.
///
/// Ordre :
///   1. session authentifiée (assurée par les écrans qui poussent ce gate)
///   2. date de naissance connue et EXPLOITABLE (chemin rapide si le profil
///      local complet du bon compte la porte déjà — validée à l'onboarding ou
///      par une synchro serveur antérieure)
///   3. sinon : `GET /api/app/profile` fait autorité
///   4. âge calculé par date civile exacte ([computeAge])
///   5. seulement si ≥ 18 -> [MainNavShell]
///
/// FAIL CLOSED : profil injoignable (réseau / 5xx) -> écran d'erreur
/// (« Réessayer » / « Se déconnecter »), JAMAIS [MainNavShell] par défaut.
/// Aucun flash de [MainNavShell] avant validation : l'état initial n'est jamais
/// `allowed` sans preuve.
class AdultGate extends StatefulWidget {
  const AdultGate({super.key, this.clock, this.forceServerCheck = false});

  /// Fige « aujourd'hui » pour les tests de dates limites.
  final DateTime Function()? clock;

  /// `true` quand ce gate est ouvert EN RÉACTION à un refus serveur 403
  /// (`age_verification_required` / `adult_required`) : on SAUTE le chemin
  /// rapide « DOB locale adulte » et on refait autorité serveur
  /// (`GET /api/app/profile`) pour router vers `needsDob` ou `minor` selon
  /// ce que le backend connaît réellement.
  final bool forceServerCheck;

  @override
  State<AdultGate> createState() => _AdultGateState();
}

enum _Phase { checking, allowed, needsDob, minor, error }

class _AdultGateState extends State<AdultGate> {
  _Phase _phase = _Phase.checking;
  bool _started = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Après la 1re frame : les scopes sont résolubles, et on évite un
    // setState pendant le build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  Future<void> _evaluate() async {
    if (!mounted) return;
    StartupTrace.mark('adult-gate/evaluate');
    final state = AuryelStateScope.of(context);
    final now = _now();

    // Chemin rapide — une DOB locale exploitable ET adulte suffit : elle a été
    // validée à l'onboarding (≥18 imposé) ou par une synchro serveur d'une
    // valeur ISO valide. Aucun appel réseau, aucun flash. SAUTÉ quand le gate
    // est ouvert suite à un 403 serveur ([forceServerCheck]) : la vérité vient
    // alors de `GET /api/app/profile`, pas de l'état local.
    final local = state.birthDate;
    if (!widget.forceServerCheck &&
        isUsableBirthDate(local, now: now) &&
        meetsMinimumAge(local!, now: now)) {
      _to(_Phase.allowed);
      StartupTrace.mark('adult-gate/local-dob-allowed');
      return;
    }

    _to(_Phase.checking);
    final auth = AuthScope.of(context);
    final restore = await auth.fetchServerProfile();
    if (!mounted) return;

    switch (restore.outcome) {
      case ProfileRestoreOutcome.unauthorized:
        _toLogin();
        return;
      case ProfileRestoreOutcome.retryable:
        _to(_Phase.error); // FAIL CLOSED
        return;
      case ProfileRestoreOutcome.ok:
        final profile = restore.profile;
        if (profile != null) {
          await applyServerProfileToState(state, profile);
          if (!mounted) return;
        }
        final dob = profile?.birthDateOrNull;
        if (!isUsableBirthDate(dob, now: now)) {
          // absente, non ISO, incohérente ou future -> correction obligatoire.
          _to(_Phase.needsDob);
        } else if (meetsMinimumAge(dob!, now: now)) {
          _to(_Phase.allowed);
          StartupTrace.mark('adult-gate/server-dob-allowed');
        } else {
          _to(_Phase.minor);
        }
    }
  }

  void _to(_Phase p) {
    if (mounted && _phase != p) setState(() => _phase = p);
  }

  void _toLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  Future<void> _logout() async {
    final auth = AuthScope.of(context);
    await auth.logout();
    if (!mounted) return;
    // AUDIT ABONNEMENT — vide le statut Premium/quota connu AVANT de router
    // vers la connexion : le prochain compte à se connecter sur cet appareil
    // ne doit jamais voir, même un instant, le Premium de l'ancien compte.
    ConsultationScope.maybeReadOf(context)?.reset();
    _toLogin();
  }

  /// Enregistrement d'une DOB corrigée depuis l'écran « Vérification de l'âge ».
  /// L'appelant a DÉJÀ vérifié `meetsMinimumAge` côté client ; ici on
  /// persiste (PATCH), on recharge le profil serveur, on recalcule, et on
  /// route.
  Future<_DobSaveResult> _saveDob(DateTime date) async {
    final auth = AuthScope.of(context);
    final state = AuryelStateScope.of(context);
    final iso = _isoDate(date);
    final outcome = await auth.syncProfileFields(dateNaissance: iso);
    if (!mounted) return _DobSaveResult.gone;
    switch (outcome) {
      case ProfileSyncOutcome.unauthorized:
        _toLogin();
        return _DobSaveResult.gone;
      case ProfileSyncOutcome.retryable:
        return _DobSaveResult.retry;
      case ProfileSyncOutcome.ok:
        state.setBirthDate(date);
        if (!mounted) return _DobSaveResult.gone;
        // « recharger le profil » : on refait autorité serveur puis on
        // ré-évalue (couvre le cas où le serveur porterait une autre valeur).
        await _evaluate();
        return _DobSaveResult.done;
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.allowed:
        return const MainNavShell();
      case _Phase.checking:
        return const _GateScaffold(child: _Checking());
      case _Phase.needsDob:
        return _GateScaffold(
          child: _AgeVerificationView(
            now: _now(),
            onSave: _saveDob,
            onTooYoung: () => _to(_Phase.minor),
          ),
        );
      case _Phase.minor:
        return _GateScaffold(
          child: _MinorBlockedView(onLogout: _logout, onDelete: _confirmDelete),
        );
      case _Phase.error:
        return _GateScaffold(
          child: _GateErrorView(onRetry: _evaluate, onLogout: _logout),
        );
    }
  }

  // --- Suppression de compte depuis l'écran mineur (optionnelle) ----------
  Future<void> _confirmDelete() async {
    final auth = AuthScope.of(context);
    if (!auth.accountDeletionAvailable) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Supprimer mon compte ?',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Ton compte Auryel et les données associées seront supprimés selon '
          'notre politique de confidentialité. Cette action est irréversible.',
          style: AuryelText.body(fontSize: 13.5, color: AuryelColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Annuler',
              style: AuryelText.body(color: AuryelColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Supprimer',
              style: AuryelText.body(
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final outcome = await auth.deleteAccount();
    if (!mounted) return;
    switch (outcome) {
      case AccountDeletionOutcome.ok:
      case AccountDeletionOutcome.unauthorized:
        _toLogin();
      case AccountDeletionOutcome.unavailable:
      case AccountDeletionOutcome.retryable:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Suppression impossible pour le moment. Réessaie plus tard.',
            ),
          ),
        );
    }
  }
}

enum _DobSaveResult { done, retry, gone }

// ===========================================================================
// Chrome commun — fond Auryel, pas de flèche retour (aucun contournement).
// ===========================================================================
class _GateScaffold extends StatelessWidget {
  const _GateScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Aucun contournement de l'écran mineur / vérification par le bouton
      // retour Android : le gate ne peut pas être « fermé ».
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: AuryelColors.backgroundGradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AuryelColors.gold,
        ),
      ),
    );
  }
}

// ===========================================================================
// Vérification de l'âge — saisie / correction de la date de naissance.
// ===========================================================================
class _AgeVerificationView extends StatefulWidget {
  const _AgeVerificationView({
    required this.now,
    required this.onSave,
    required this.onTooYoung,
  });

  final DateTime now;
  final Future<_DobSaveResult> Function(DateTime date) onSave;
  final VoidCallback onTooYoung;

  @override
  State<_AgeVerificationView> createState() => _AgeVerificationViewState();
}

class _AgeVerificationViewState extends State<_AgeVerificationView> {
  final _controller = TextEditingController();
  DateTime? _parsed;
  bool _busy = false;
  String? _error;

  bool get _tooYoung =>
      _parsed != null && !meetsMinimumAge(_parsed!, now: widget.now);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _parsed = parseBirthDate(value, now: widget.now);
      _error = null;
    });
  }

  Future<void> _pickFromCalendar() async {
    final now = widget.now;
    final result = await showDatePicker(
      context: context,
      initialDate: _parsed ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'DATE DE NAISSANCE',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
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
      ),
    );
    if (result == null) return;
    _controller.text = formatBirthDateFr(result);
    setState(() => _parsed = parseBirthDate(_controller.text, now: widget.now));
  }

  Future<void> _continue() async {
    final date = _parsed;
    if (date == null || !isUsableBirthDate(date, now: widget.now)) {
      setState(() => _error = 'Vérifie ta date de naissance.');
      return;
    }
    if (!meetsMinimumAge(date, now: widget.now)) {
      widget.onTooYoung();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await widget.onSave(date);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == _DobSaveResult.retry) {
      setState(
        () => _error =
            'Enregistrement impossible. Vérifie ta connexion et réessaie.',
      );
    }
    // done / gone -> le gate a déjà changé de phase / route.
  }

  @override
  Widget build(BuildContext context) {
    final raw = _controller.text.trim();
    final showParseHint = raw.isNotEmpty && _parsed == null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Vérification de l’âge',
            style: AuryelText.display(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textCream,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            kMinimumAgeMessage,
            style: AuryelText.body(
              fontSize: 13.5,
              height: 1.5,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Date de naissance',
            style: AuryelText.body(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AuryelColors.gold,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_busy,
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
                    enabledBorder: const UnderlineInputBorder(
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
              IconButton(
                tooltip: 'Choisir dans le calendrier',
                onPressed: _busy ? null : _pickFromCalendar,
                icon: const PhosphorIcon(
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
          else if (showParseHint)
            Text(
              'Vérifie ta date de naissance',
              style: AuryelText.body(
                fontSize: 13,
                color: AuryelColors.textMuted,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
          const SizedBox(height: 28),
          AuryelGoldButton(
            label: _busy ? 'Enregistrement…' : 'Continuer',
            onTap: _continue,
            enabled: _parsed != null && !_tooYoung && !_busy,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Utilisateur mineur — accès refusé, aucune ouverture de l'app.
// ===========================================================================
class _MinorBlockedView extends StatelessWidget {
  const _MinorBlockedView({required this.onLogout, required this.onDelete});

  final VoidCallback onLogout;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.maybeOf(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(
              PhosphorIconsRegular.shieldWarning,
              size: 34,
              color: AuryelColors.goldLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Accès réservé aux adultes',
              textAlign: TextAlign.center,
              style: AuryelText.display(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              kMinimumAgeMessage,
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 13.5,
                height: 1.5,
                color: AuryelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            AuryelGoldButton(label: 'Se déconnecter', onTap: onLogout),
            if (auth?.accountDeletionAvailable ?? false) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onDelete,
                child: Text(
                  'Supprimer mon compte',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Erreur de vérification — FAIL CLOSED (jamais MainNavShell).
// ===========================================================================
class _GateErrorView extends StatelessWidget {
  const _GateErrorView({required this.onRetry, required this.onLogout});

  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PhosphorIcon(
              PhosphorIconsRegular.cloudSlash,
              size: 34,
              color: AuryelColors.goldLight,
            ),
            const SizedBox(height: 16),
            Text(
              'Vérification impossible',
              textAlign: TextAlign.center,
              style: AuryelText.display(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AuryelColors.textCream,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Nous n’avons pas pu vérifier ton âge pour le moment. Vérifie ta '
              'connexion et réessaie.',
              textAlign: TextAlign.center,
              style: AuryelText.body(
                fontSize: 13.5,
                height: 1.5,
                color: AuryelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            AuryelGoldButton(label: 'Réessayer', onTap: onRetry),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onLogout,
              child: Text(
                'Se déconnecter',
                style: AuryelText.body(
                  fontSize: 12.5,
                  color: AuryelColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

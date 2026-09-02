import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/account_service.dart';
import '../data/daily_like_store.dart';
import '../data/daily_share_tracker.dart';
import '../state/auth_controller.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../state/purchase_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import '../widgets/daily_message_sheet.dart';
import '../widgets/gold_button.dart';
import 'advisor_chooser_screen.dart';
import 'bibliotheque_screen.dart';
import 'onboarding/email_auth_screen.dart';
import 'premium_screen.dart';

/// B10 — « Mon espace » : ouvert depuis l'icône profil de l'accueil (jamais un
/// 5e onglet). Écran scrollable, DA Auryel (fond sombre, or, cartes fines).
///
/// Rien d'inventé : toutes les valeurs viennent de sources réelles déjà
/// présentes (AuryelState, AuthController, ConsultationController, Purchase
/// Controller, DailyLikeStore, DailyShareTracker). La récompense 30 j et la
/// suppression de compte n'ont PAS d'endpoint backend -> affichées « en
/// préparation », aucune action réelle.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _likedMessages = 0;
  int _likedTarot = 0;
  int _shareDays = 0;
  bool _savingBirthDate = false;

  @override
  void initState() {
    super.initState();
    _loadCounters();
  }

  Future<void> _loadCounters() async {
    try {
      final lm = await DailyLikeStore().likedDaysCount();
      final lt = await DailyLikeStore(bucket: 'tarot').likedDaysCount();
      final sd = await DailyShareTracker().sharedDaysCount();
      if (mounted) {
        setState(() {
          _likedMessages = lm;
          _likedTarot = lt;
          _shareDays = sd;
        });
      }
    } catch (_) {
      /* compteurs à 0 par défaut */
    }
  }

  Future<void> _logout() async {
    final auth = AuthScope.maybeOf(context);
    await auth?.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Supprimer mon compte ?',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Cette action supprimera définitivement ton compte et tes données.',
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
              'Supprimer mon compte',
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
    try {
      await const AccountService().deleteAccount();
    } on AccountDeletionUnavailable {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La suppression de compte sera bientôt disponible. '
            'Aucune donnée n’a été touchée.',
          ),
        ),
      );
    }
  }

  /// §8-§10 — ouvre EXACTEMENT la feuille « Message du jour » de B8
  /// (interprétation, « j'aime », génération des 3 variantes, partage natif).
  /// Aucun second générateur. Au retour on rafraîchit les compteurs (le
  /// partage a pu incrémenter les jours).
  Future<void> _openPublication() async {
    await showDailyMessageSheet(context);
    if (mounted) await _loadCounters();
  }

  /// §4 — édition du prénom via `PATCH /api/app/profile` (API réelle). L'état
  /// local n'est mis à jour qu'APRÈS un succès backend — aucune divergence.
  Future<void> _editName() async {
    final state = AuryelStateScope.of(context);
    final auth = AuthScope.maybeOf(context);
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditNameSheet(
        initialValue: state.firstName ?? '',
        submit: (value) async {
          if (auth == null) return ProfileSyncOutcome.retryable;
          return auth.syncProfileFields(prenom: value);
        },
      ),
    );
    if (saved == null || !mounted) return;
    await state.applyIdentityEdit(firstName: saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prénom mis à jour.')),
    );
  }

  /// §5 — édition de la date de naissance : on réutilise le `showDatePicker`
  /// thémé déjà employé à l'onboarding, puis `PATCH /api/app/profile`
  /// (`date_naissance` en ISO `YYYY-MM-DD`, format backend inchangé).
  Future<void> _editBirthDate() async {
    if (_savingBirthDate) return;
    final state = AuryelStateScope.of(context);
    final auth = AuthScope.maybeOf(context);
    final now = DateTime.now();
    final current = state.birthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 25),
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
    if (picked == null || !mounted) return;
    setState(() => _savingBirthDate = true);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = auth == null
        ? ProfileSyncOutcome.retryable
        : await auth.syncProfileFields(dateNaissance: _isoDate(picked));
    if (!mounted) return;
    setState(() => _savingBirthDate = false);
    if (outcome == ProfileSyncOutcome.ok) {
      await state.applyIdentityEdit(birthDate: picked);
      messenger.showSnackBar(
        const SnackBar(content: Text('Date de naissance mise à jour.')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome == ProfileSyncOutcome.unauthorized
                ? 'Session expirée. Reconnecte-toi pour modifier tes informations.'
                : 'Impossible d’enregistrer pour le moment. Réessaie.',
          ),
        ),
      );
    }
  }

  static String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final state = AuryelStateScope.of(context);
    final auth = AuthScope.maybeOf(context);
    final consultation = ConsultationScope.maybeReadOf(context);
    final purchase = PurchaseScope.maybeOf(context);

    final firstName = (state.firstName ?? '').trim();
    final email = auth?.account?.email ?? '';
    final advisor = advisorByNameOrNull(state.selectedAdvisor);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(firstName: firstName, email: email),
                const SizedBox(height: 22),
                if (advisor != null) ...[
                  _AdvisorSection(advisor: advisor),
                  const SizedBox(height: 16),
                ],
                _TimeSection(consultation: consultation),
                const SizedBox(height: 16),
                _SubscriptionSection(
                  consultation: consultation,
                  purchase: purchase,
                ),
                const SizedBox(height: 16),
                _JourneySection(
                  likedMessages: _likedMessages,
                  likedTarot: _likedTarot,
                  shareDays: _shareDays,
                ),
                const SizedBox(height: 16),
                _RewardsSection(
                  shareDays: _shareDays,
                  onGenerate: _openPublication,
                ),
                const SizedBox(height: 16),
                _AccountSection(
                  firstName: firstName,
                  email: email,
                  birthDate: state.birthDate,
                  onEditName: _editName,
                  onEditBirthDate: _savingBirthDate ? null : _editBirthDate,
                ),
                const SizedBox(height: 16),
                _PrivacySection(onDelete: _confirmDelete),
                const SizedBox(height: 22),
                _LogoutButton(onTap: _logout),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// En-tête
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.firstName, required this.email});

  final String firstName;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const PhosphorIcon(
              PhosphorIconsRegular.arrowLeft,
              size: 20,
              color: AuryelColors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Mon espace',
          style: AuryelText.display(fontSize: 26, fontWeight: FontWeight.w600),
        ),
        if (firstName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            firstName,
            style: AuryelText.body(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AuryelColors.goldLight,
            ),
          ),
        ],
        if (email.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            email,
            style: AuryelText.body(fontSize: 12, color: AuryelColors.textMuted),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Carte de section réutilisable
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final PhosphorIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                PhosphorIcon(icon!, size: 15, color: AuryelColors.gold),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  softWrap: true,
                  style: AuryelText.body(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mon conseiller
// ---------------------------------------------------------------------------

class _AdvisorSection extends StatelessWidget {
  const _AdvisorSection({required this.advisor});

  final AdvisorInfo advisor;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Mon conseiller',
      icon: PhosphorIconsRegular.sparkle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AuryelColors.goldGradient,
                ),
                child: ClipOval(
                  child: Image.asset(advisor.assetPath, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      advisor.name,
                      style: AuryelText.display(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      advisor.specialty,
                      style: AuryelText.body(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.gold,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      advisor.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AuryelText.body(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _LinkRow(
            label: 'Changer de conseiller',
            icon: PhosphorIconsRegular.arrowsLeftRight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdvisorChooserScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mon temps de consultation
// ---------------------------------------------------------------------------

class _TimeSection extends StatelessWidget {
  const _TimeSection({required this.consultation});

  final ConsultationController? consultation;

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    final total = c == null ? 0 : c.remaining.inSeconds;
    final t = c?.time;
    return _Section(
      title: 'Mon temps de consultation',
      icon: PhosphorIconsRegular.hourglass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temps disponible',
            style: AuryelText.body(
              fontSize: 11,
              color: AuryelColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            ConsultationController.formatTotalTime(total),
            style: AuryelText.display(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
          if (t != null) ...[
            const SizedBox(height: 12),
            if (t.firstFreeRemainingSeconds > 0)
              _TimeRow(
                'Heure offerte',
                ConsultationController.formatTotalTime(
                  t.firstFreeRemainingSeconds,
                ),
              ),
            if (t.premiumRemainingSeconds > 0)
              _TimeRow(
                'Temps Premium',
                ConsultationController.formatTotalTime(
                  t.premiumRemainingSeconds,
                ),
              ),
            if (t.purchasedRemainingSeconds > 0)
              _TimeRow(
                'Temps acheté',
                ConsultationController.formatTotalTime(
                  t.purchasedRemainingSeconds,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: AuryelText.body(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mon abonnement
// ---------------------------------------------------------------------------

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({
    required this.consultation,
    required this.purchase,
  });

  final ConsultationController? consultation;
  final PurchaseController? purchase;

  @override
  Widget build(BuildContext context) {
    final premium = consultation?.quota?.isPremium ?? false;
    final periodEnd = consultation?.quota?.periodEnd;
    final canRestore = purchase?.canRestore ?? false;

    return _Section(
      title: 'Mon abonnement',
      icon: PhosphorIconsRegular.crown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Auryel Premium',
            style: AuryelText.display(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (premium) ...[
            Text(
              'Actif',
              style: AuryelText.body(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
            if (periodEnd != null) ...[
              const SizedBox(height: 2),
              Text(
                'Renouvellement le ${_fmtDate(periodEnd)}',
                style: AuryelText.body(
                  fontSize: 12,
                  color: AuryelColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _LinkRow(
              label: 'Gérer mon abonnement',
              icon: PhosphorIconsRegular.gear,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
              ),
            ),
          ] else ...[
            Text(
              '8 h de consultation par mois',
              style: AuryelText.body(
                fontSize: 12.5,
                color: AuryelColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '7,99 €/mois',
              style: AuryelText.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
            const SizedBox(height: 12),
            _LinkRow(
              label: 'S’abonner',
              icon: PhosphorIconsRegular.arrowRight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
              ),
            ),
          ],
          if (canRestore) ...[
            const SizedBox(height: 6),
            _LinkRow(
              label: 'Restaurer mes achats',
              icon: PhosphorIconsRegular.arrowClockwise,
              onTap: () => purchase?.restorePurchases(),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mon parcours
// ---------------------------------------------------------------------------

class _JourneySection extends StatelessWidget {
  const _JourneySection({
    required this.likedMessages,
    required this.likedTarot,
    required this.shareDays,
  });

  final int likedMessages;
  final int likedTarot;
  final int shareDays;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Mon parcours',
      icon: PhosphorIconsRegular.compass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatRow(
            '$likedMessages message${likedMessages > 1 ? 's' : ''} aimé'
            '${likedMessages > 1 ? 's' : ''}',
            PhosphorIconsRegular.heart,
          ),
          _StatRow(
            '$likedTarot tirage${likedTarot > 1 ? 's' : ''} aimé'
            '${likedTarot > 1 ? 's' : ''}',
            PhosphorIconsRegular.cardsThree,
          ),
          _StatRow(
            '$shareDays jour${shareDays > 1 ? 's' : ''} de partage',
            PhosphorIconsRegular.shareNetwork,
          ),
          const SizedBox(height: 8),
          _LinkRow(
            label: 'Voir mes tirages',
            icon: PhosphorIconsRegular.arrowRight,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const BibliothequeScreen(showBackButton: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.icon);

  final String label;
  final PhosphorIconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          PhosphorIcon(icon, size: 14, color: AuryelColors.textMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: AuryelText.body(
              fontSize: 13,
              color: AuryelColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mes récompenses
// ---------------------------------------------------------------------------

class _RewardsSection extends StatelessWidget {
  const _RewardsSection({
    required this.shareDays,
    required this.onGenerate,
  });

  final int shareDays;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final capped = shareDays > 30 ? 30 : shareDays;
    return _Section(
      title: 'Mes récompenses',
      icon: PhosphorIconsRegular.gift,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Génère ta publication',
            style: AuryelText.display(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Partage ton message du jour sur tes réseaux.',
            style: AuryelText.body(
              fontSize: 11.5,
              height: 1.4,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '30 jours de partage = 1 h de consultation offerte.',
            style: AuryelText.body(
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: capped / 30,
              minHeight: 6,
              backgroundColor: AuryelColors.warmBorder,
              valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$capped / 30 jours',
            style: AuryelText.body(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(height: 12),
          AuryelGoldButton(
            label: 'Générer ma publication',
            onTap: onGenerate,
          ),
          const SizedBox(height: 8),
          Text(
            'Reviens chaque jour : au bout de 30 jours de partage, ton heure '
            'de consultation est créditée. Activation de la récompense bientôt '
            'disponible.',
            style: AuryelText.body(
              fontSize: 10.5,
              height: 1.4,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Parrainage',
            style: AuryelText.display(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '+1 h de consultation quand un filleul s’abonne.',
            style: AuryelText.body(
              fontSize: 11.5,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _Pill(text: 'À venir'),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AuryelColors.gold.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          text,
          style: AuryelText.body(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mon compte
// ---------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.firstName,
    required this.email,
    required this.birthDate,
    required this.onEditName,
    required this.onEditBirthDate,
  });

  final String firstName;
  final String email;
  final DateTime? birthDate;
  final VoidCallback onEditName;

  /// `null` pendant l'enregistrement d'une nouvelle date (double-tap bloqué,
  /// petit indicateur affiché à la place du crayon).
  final VoidCallback? onEditBirthDate;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Mon compte',
      icon: PhosphorIconsRegular.userCircle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Kv(
            'Prénom',
            firstName.isEmpty ? '—' : firstName,
            onEdit: onEditName,
          ),
          _Kv('Email', email.isEmpty ? '—' : email),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'La modification de l’email sera bientôt disponible.',
              style: AuryelText.body(
                fontSize: 10.5,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
          _Kv(
            'Date de naissance',
            birthDate == null ? '—' : _fmtDate(birthDate!),
            onEdit: onEditBirthDate,
            busy: onEditBirthDate == null,
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.onEdit, this.busy = false});

  final String k;
  final String v;

  /// Quand non nul, un crayon « Modifier » est ajouté en fin de ligne.
  final VoidCallback? onEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            k,
            style: AuryelText.body(
              fontSize: 12.5,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: AuryelText.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AuryelColors.textSecondary,
              ),
            ),
          ),
          if (busy) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AuryelColors.goldLight),
              ),
            ),
            const SizedBox(width: 12),
          ] else if (onEdit != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onEdit,
              tooltip: 'Modifier',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const PhosphorIcon(
                PhosphorIconsRegular.pencilSimple,
                size: 15,
                color: AuryelColors.gold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confidentialité et données
// ---------------------------------------------------------------------------

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Confidentialité et données',
      icon: PhosphorIconsRegular.shieldCheck,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LinkRow(
            label: 'Supprimer mon compte',
            icon: PhosphorIconsRegular.trash,
            onTap: onDelete,
          ),
          const SizedBox(height: 6),
          Text(
            'La suppression définitive sera disponible prochainement.',
            style: AuryelText.body(
              fontSize: 11,
              color: AuryelColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Déconnexion
// ---------------------------------------------------------------------------

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: const PhosphorIcon(
          PhosphorIconsRegular.signOut,
          size: 16,
          color: AuryelColors.textMuted,
        ),
        label: Text(
          'Se déconnecter',
          style: AuryelText.body(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AuryelColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ligne navigable réutilisable
// ---------------------------------------------------------------------------

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final PhosphorIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              PhosphorIcon(icon, size: 14, color: AuryelColors.goldLight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AuryelText.body(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AuryelColors.goldLight,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const PhosphorIcon(
                PhosphorIconsRegular.caretRight,
                size: 12,
                color: AuryelColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

// ---------------------------------------------------------------------------
// Feuille « Modifier mon prénom » (§4)
// ---------------------------------------------------------------------------

/// Bottom sheet minimal : champ prérempli + Annuler / Enregistrer. Le PATCH
/// backend est lancé DEPUIS la feuille (via [submit]) pour pouvoir afficher un
/// chargement discret, bloquer le double-tap et montrer une erreur propre sans
/// fermer. En cas de succès, on referme en renvoyant la valeur ; l'appelant
/// applique alors l'état local (aucun faux succès, aucune divergence).
class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initialValue, required this.submit});

  final String initialValue;
  final Future<ProfileSyncOutcome> Function(String value) submit;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final outcome = await widget.submit(value);
    if (!mounted) return;
    switch (outcome) {
      case ProfileSyncOutcome.ok:
        Navigator.of(context).pop(value);
      case ProfileSyncOutcome.unauthorized:
        setState(() {
          _saving = false;
          _error =
              'Session expirée. Reconnecte-toi pour modifier tes informations.';
        });
      case ProfileSyncOutcome.retryable:
        setState(() {
          _saving = false;
          _error = 'Impossible d’enregistrer pour le moment. Réessaie.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AuryelColors.warmBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            18,
            24,
            18 + media.viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Modifier mon prénom',
                style: AuryelText.display(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                style: AuryelText.display(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: AuryelColors.gold,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: 'Ton prénom',
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
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AuryelText.body(
                    fontSize: 12,
                    color: AuryelColors.goldLight,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        'Annuler',
                        style: AuryelText.body(color: AuryelColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AuryelGoldButton(
                      label: _saving ? 'Enregistrement…' : 'Enregistrer',
                      enabled: !_saving,
                      onTap: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/memory_api.dart';
import '../config/legal_texts.dart';
import '../data/app_review_service.dart';
import '../data/birth_date_parser.dart';
import '../data/daily_like_store.dart';
import '../data/daily_share_tracker.dart';
import '../data/daily_thought.dart';
import '../data/legal_link_launcher.dart';
import '../data/share_reward_repository.dart';
import '../data/subscription_manager.dart';
import '../state/auth_controller.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../state/purchase_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import '../widgets/ai_transparency_note.dart';
import '../widgets/auryel_wordmark.dart';
import '../widgets/meta_consent_tile.dart';
import '../widgets/daily_message_sheet.dart';
import '../widgets/gold_button.dart';
import 'advisor_chooser_screen.dart';
import 'auryel_experience_screen.dart';
import 'bibliotheque_screen.dart';
import 'wellbeing_journey_screen.dart';
import 'legal_document_screen.dart';
import 'notification_settings_screen.dart';
import 'onboarding/email_auth_screen.dart';
import 'premium_screen.dart';
import 'support_screen.dart';

/// B10 — « Mon espace » : ouvert depuis l'icône profil de l'accueil (jamais un
/// 5e onglet). Écran scrollable, DA Auryel (fond sombre, or, cartes fines).
///
/// Rien d'inventé : toutes les valeurs viennent de sources réelles déjà
/// présentes (AuryelState, AuthController, ConsultationController, Purchase
/// Controller, DailyLikeStore, DailyShareTracker). La récompense 30 j et la
/// suppression de compte n'ont PAS d'endpoint backend -> affichées « en
/// préparation », aucune action réelle.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.thoughtRepository,
    this.showBackButton = true,
    this.subscriptionManager,
    this.reviewService,
  });

  /// Injecté par les tests ; en production la source est le pack local
  /// `assets/pensees/`.
  final DailyThoughtRepository? thoughtRepository;

  /// Test uniquement : sinon [defaultSubscriptionManager].
  final SubscriptionManager? subscriptionManager;

  /// `false` quand l'écran est monté DANS la bottom navigation (onglet « Mon
  /// compte ») : pas de flèche retour inutile. `true` (défaut) quand il est
  /// poussé comme écran secondaire (icône profil de l'Accueil).
  final bool showBackButton;

  /// Test uniquement : sinon [InAppReviewService] (boîte de notation native).
  final AppReviewService? reviewService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DailyThoughtRepository _thoughts =
      widget.thoughtRepository ?? DailyThoughtRepository();
  int _likedMessages = 0;
  int _likedTarot = 0;
  int _shareDays = 0;
  bool _savingBirthDate = false;

  late final AppReviewService _review =
      widget.reviewService ?? InAppReviewService();
  bool _rating = false;

  /// Progression partage SERVEUR (`GET /api/app/rewards/share-progress`) — fait
  /// autorité quand disponible ; sinon on retombe sur le cache local
  /// [_shareDays]. Aucun endpoint inventé : `RewardsApi` porte déjà cette route.
  int? _serverShareCount;
  int _shareTarget = 30;
  bool _serverShareRequested = false;

  /// Éligibilité Memory (`GET /api/app/memory/progress`) — lecture seule,
  /// source de vérité serveur. `null` tant qu'indisponible (endpoint absent,
  /// réseau, pas de session) : le bloc Memory n'affiche alors que la règle.
  MemoryProgress? _memoryProgress;

  @override
  void initState() {
    super.initState();
    _loadCounters();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Une seule tentative de lecture serveur par montage (besoin du scope Auth).
    if (_serverShareRequested) return;
    _serverShareRequested = true;
    _loadServerShareProgress();
    _loadMemoryProgress();
  }

  /// Lecture SEULE de l'éligibilité Memory. Aucun effet de bord : ne joue
  /// aucune partie, ne crédite rien. Indisponible -> `_memoryProgress` reste
  /// `null` et le bloc affiche seulement la règle.
  Future<void> _loadMemoryProgress() async {
    final auth = AuthScope.maybeOf(context);
    final api = auth?.memoryApi;
    if (auth == null || api == null) return;
    try {
      final token = await auth.currentToken();
      if (token == null || token.isEmpty || !mounted) return;
      final progress = await api.getProgress(token);
      if (!mounted) return;
      setState(() => _memoryProgress = progress);
    } catch (_) {
      /* bloc Memory affiché sans état d'éligibilité */
    }
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

  /// Lecture SEULE de la progression serveur (`count` / `target`). Ne crédite
  /// rien, ne modifie aucun quota. En cas d'indisponibilité (endpoint absent,
  /// réseau, 5xx, 401, pas de session), `loadProgress()` renvoie `null` et
  /// l'affichage reste sur le cache local.
  Future<void> _loadServerShareProgress() async {
    final auth = AuthScope.maybeOf(context);
    if (auth == null) return;
    final repo = ShareRewardRepository(
      api: auth.rewardsApi,
      tokenProvider: auth.currentToken,
    );
    final progress = await repo.loadProgress();
    if (progress == null || !mounted) return;
    setState(() {
      _serverShareCount = progress.count;
      _shareTarget = progress.target;
    });
  }

  void _openSupport() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SupportScreen()));
  }

  /// « Noter l'appli » — VOLONTAIRE (tap explicite). Ouvre la boîte de
  /// notation native ; jamais de pop-up automatique, aucun review gating,
  /// aucune récompense, aucun wording « 5 étoiles ». `requestReview()` ne
  /// garantit pas l'apparition de la boîte : ce n'est pas une erreur.
  Future<void> _rateApp() async {
    if (_rating) return;
    setState(() => _rating = true);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await _review.rate();
    if (!mounted) return;
    setState(() => _rating = false);
    if (outcome == AppReviewOutcome.unavailable) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('La notation n’est pas disponible pour le moment.'),
        ),
      );
    }
  }

  Future<void> _logout() async {
    final auth = AuthScope.maybeOf(context);
    await auth?.logout();
    if (!mounted) return;
    // AUDIT ABONNEMENT — vide le statut Premium/quota connu AVANT de router
    // vers la connexion : le prochain compte à se connecter sur cet appareil
    // ne doit jamais voir, même un instant, le Premium de l'ancien compte.
    ConsultationScope.maybeReadOf(context)?.reset();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
      (route) => false,
    );
  }

  bool _deleting = false;

  /// B10 — suppression RÉELLE du compte, en 2 confirmations (dialogue clair +
  /// saisie de « SUPPRIMER » pour écarter le tap accidentel).
  ///
  /// Rien n'est purgé localement AVANT un succès serveur (cf.
  /// [AuthController.deleteAccount]). Sur échec réseau/5xx : session conservée,
  /// message d'erreur, réessai possible. Sur succès : retour au parcours non
  /// authentifié, aucun ancien utilisateur conservé dans l'état Flutter.
  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final auth = AuthScope.maybeOf(context);
    final state = AuryelStateScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuryelColors.surface,
        title: Text(
          'Supprimer mon compte ?',
          style: AuryelText.display(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Cette action supprimera ton compte Auryel et les données associées '
          'selon notre politique de confidentialité. Cette action est '
          'irréversible.',
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
    if (step1 != true || !mounted) return;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(),
    );
    if (step2 != true || !mounted) return;

    if (auth == null || !auth.accountDeletionAvailable) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'La suppression de compte n’est pas encore disponible. '
            'Aucune donnée n’a été touchée.',
          ),
        ),
      );
      return;
    }

    setState(() => _deleting = true);
    final outcome = await auth.deleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);

    switch (outcome) {
      case AccountDeletionOutcome.ok:
        // Succès serveur confirmé : on efface aussi l'identité EN MÉMOIRE +
        // son snapshot persisté (prénom / date de naissance / conseiller /
        // portrait) avant de repartir sur le flux non authentifié.
        await state.clearForAccountDeletion();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
          (route) => false,
        );
      case AccountDeletionOutcome.unauthorized:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
          (route) => false,
        );
      case AccountDeletionOutcome.unavailable:
      case AccountDeletionOutcome.retryable:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de supprimer ton compte pour le moment. '
              'Ta session est conservée, réessaie plus tard.',
            ),
          ),
        );
    }
  }

  /// Ouvre l'aperçu de LA publication du jour (visuel WEBP final déjà généré) +
  /// partage natif. Au retour on rafraîchit les compteurs (le partage a pu
  /// incrémenter les jours). Aucun générateur, aucune variante.
  Future<void> _openPublication() async {
    final thought = await _thoughts.today();
    if (!mounted) return;
    await showDailyThoughtSheet(context, thought: thought);
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Prénom mis à jour.')));
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
    final messenger = ScaffoldMessenger.of(context);
    // Règle 18+ (J2) : une édition ne peut pas rendre le compte < 18 ans.
    // Aucun PATCH n'est envoyé, l'état local n'est pas touché.
    if (!meetsMinimumAge(picked)) {
      messenger.showSnackBar(const SnackBar(content: Text(kMinimumAgeMessage)));
      return;
    }
    setState(() => _savingBirthDate = true);
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
                _Header(
                  firstName: firstName,
                  email: email,
                  showBackButton: widget.showBackButton,
                ),
                const SizedBox(height: 22),
                if (advisor != null) ...[
                  _AdvisorSection(advisor: advisor),
                  const SizedBox(height: 16),
                ],
                _TimeSection(consultation: consultation),
                const SizedBox(height: 16),
                // Reconstruction CIBLÉE de la seule section abonnement quand
                // `ConsultationController.notifyListeners()` se déclenche
                // (ex. `refresh()`/`refreshAll()` en arrière-plan) — corrige
                // le bug audité : `consultation` est lu ici via
                // `maybeReadOf` (sans dépendance), donc sans ce
                // `ListenableBuilder` explicite la section restait figée sur
                // le premier statut lu, même après un resync réussi. Le
                // reste de l'écran (Dashboard entier) n'est jamais
                // reconstruit pour ça.
                consultation == null
                    ? _SubscriptionSection(
                        consultation: consultation,
                        purchase: purchase,
                        subscriptionManager: widget.subscriptionManager ??
                            defaultSubscriptionManager,
                      )
                    : ListenableBuilder(
                        listenable: consultation,
                        builder: (context, _) => _SubscriptionSection(
                          consultation: consultation,
                          purchase: purchase,
                          subscriptionManager: widget.subscriptionManager ??
                              defaultSubscriptionManager,
                        ),
                      ),
                const SizedBox(height: 16),
                _JourneySection(
                  likedMessages: _likedMessages,
                  likedTarot: _likedTarot,
                  shareDays: _shareDays,
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Parcours bien-être',
                  icon: PhosphorIconsRegular.path,
                  child: _LinkRow(
                    label: 'Suivre mon parcours bien-être',
                    icon: PhosphorIconsRegular.mountains,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WellbeingJourneyScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'L’expérience Auryel',
                  icon: PhosphorIconsRegular.compassRose,
                  child: _LinkRow(
                    label: 'Découvrir Auryel',
                    icon: PhosphorIconsRegular.sparkle,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AuryelExperienceScreen(fromDashboard: true),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _RewardsSection(
                  // Serveur autoritaire quand disponible, sinon cache local.
                  shareDays: _serverShareCount ?? _shareDays,
                  target: _shareTarget,
                  onGenerate: _openPublication,
                  memoryProgress: _memoryProgress,
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
                _Section(
                  title: 'Notifications',
                  icon: PhosphorIconsRegular.bell,
                  child: _LinkRow(
                    label: 'Notifications',
                    icon: PhosphorIconsRegular.bell,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Confidentialité',
                  icon: PhosphorIconsRegular.shieldCheck,
                  child: const MetaConsentTile(),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Aide',
                  icon: PhosphorIconsRegular.lifebuoy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LinkRow(
                        label: 'Signaler un problème',
                        icon: PhosphorIconsRegular.chatCircleText,
                        onTap: _openSupport,
                      ),
                      const SizedBox(height: 4),
                      _LinkRow(
                        label: 'Noter l’appli',
                        icon: PhosphorIconsRegular.star,
                        onTap: _rating ? () {} : _rateApp,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _PrivacySection(onDelete: _confirmDelete, deleting: _deleting),
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
  const _Header({
    required this.firstName,
    required this.email,
    this.showBackButton = true,
  });

  final String firstName;
  final String email;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBackButton)
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
          )
        else
          const SizedBox(height: 8),
        const SizedBox(height: 6),
        // Identité Auryel affirmée dès l'ouverture : le wordmark domine,
        // « Mon espace » devient un sous-titre. Compact, aligné à gauche.
        const AuryelWordmark(fontSize: 30, letterSpacing: 5, rules: false),
        const SizedBox(height: 6),
        Text(
          'Mon espace',
          style: AuryelText.body(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textMuted,
            letterSpacing: 1.4,
          ),
        ),
        if (firstName.isNotEmpty) ...[
          const SizedBox(height: 6),
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
              MaterialPageRoute(builder: (_) => const AdvisorChooserScreen()),
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
    // Même source de vérité que l'Accueil (`availableTimeLabel`) — plus de
    // « 0 min » incohérent. GROS CHANTIER ÉCONOMIQUE (Prompt 1/5) : vocabulaire
    // Bienvenue / Premium / Bonus / Acheté, jamais de durée figée en dur.
    final label =
        c?.availableTimeLabel ?? ConsultationController.formatTotalTime(0);
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
            label,
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
                'Bienvenue',
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
            // Ordre = ordre de débit backend (first_free -> premium -> earned
            // -> purchased) pour que le total se réconcilie avec les lignes.
            if (t.earnedRemainingSeconds > 0)
              _TimeRow(
                'Bonus',
                ConsultationController.formatTotalTime(
                  t.earnedRemainingSeconds,
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
    required this.subscriptionManager,
  });

  final ConsultationController? consultation;
  final PurchaseController? purchase;
  final SubscriptionManager subscriptionManager;

  Future<void> _manage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await subscriptionManager.openManagement();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Ouvre l’app Google Play puis Abonnements pour gérer ou résilier '
            'ton abonnement Auryel.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = consultation?.quota?.isPremium ?? false;
    final periodEnd = consultation?.quota?.periodEnd;
    final canRestore = purchase?.canRestore ?? false;
    // Prix STORE d'abord ; repli marketing « 7,99 €/mois » sinon.
    final storePrice = purchase?.premiumProduct?.price;
    final priceLabel = (storePrice != null && storePrice.isNotEmpty)
        ? storePrice
        : '7,99 €/mois';

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
              onTap: () => _manage(context),
            ),
            const SizedBox(height: 4),
            Text(
              'Renouvellement automatique. Résiliation depuis Google Play → '
              'Abonnements.',
              style: AuryelText.body(
                fontSize: 10.5,
                color: AuryelColors.textMuted,
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
              priceLabel,
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
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
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
                builder: (_) => const BibliothequeScreen(showBackButton: true),
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
    required this.target,
    required this.onGenerate,
    this.memoryProgress,
  });

  /// Jours de partage à afficher — serveur si disponible, sinon cache local.
  final int shareDays;

  /// Palier (30 en V1) — vient de la réponse serveur quand disponible.
  final int target;
  final VoidCallback onGenerate;

  /// Éligibilité Memory (source serveur). `null` = règle affichée sans état.
  final MemoryProgress? memoryProgress;

  @override
  Widget build(BuildContext context) {
    final safeTarget = target <= 0 ? 30 : target;
    final capped = shareDays > safeTarget ? safeTarget : shareDays;
    return _Section(
      title: 'Mes récompenses',
      icon: PhosphorIconsRegular.gift,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ta pensée du jour',
            style: AuryelText.display(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Partage la publication du jour avec tes contacts.',
            style: AuryelText.body(
              fontSize: 11.5,
              height: 1.4,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$safeTarget jours de partage = 1 h de consultation offerte.',
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
              value: capped / safeTarget,
              minHeight: 6,
              backgroundColor: AuryelColors.warmBorder,
              valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$capped / $safeTarget jours',
            style: AuryelText.body(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(height: 12),
          AuryelGoldButton(
            label: 'Partager ma pensée du jour',
            onTap: onGenerate,
          ),
          const SizedBox(height: 8),
          Text(
            'Un partage compté par jour. Le décompte des jours et le crédit '
            'de l’heure sont gérés par nos serveurs.',
            style: AuryelText.body(
              fontSize: 10.5,
              height: 1.4,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          _MemoryRewardBlock(progress: memoryProgress),
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

/// Bloc « Le Jeu Auryel » de la section récompenses. GROS CHANTIER AURYEL
/// (Prompt 3/5) : la récompense mini-jeux est désormais des ÉTOILES, avec un
/// plafond PARTAGÉ par toute la catégorie (Memory / Suite intuitive / Carte
/// cachée) — une seule récompense par jour, tous jeux confondus, plus une
/// fenêtre 7 j indépendante par niveau. Indépendant du partage (30 j = 1 h)
/// et du parcours bien-être (30 journées = 15 min). La source de vérité est
/// le serveur : [progress] est `null` tant qu'il n'a pas répondu.
class _MemoryRewardBlock extends StatelessWidget {
  const _MemoryRewardBlock({this.progress});

  final MemoryProgress? progress;

  static String? _humanizeUntil(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    final diff = dt.difference(DateTime.now());
    if (diff.inSeconds <= 0) return null;
    if (diff.inHours >= 24) return '${(diff.inHours / 24).ceil()} j';
    if (diff.inHours >= 1) return '${diff.inHours} h';
    return 'moins d’une heure';
  }

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final stars = p?.starsReward ?? 0;
    final status = p == null
        ? null
        : (p.eligibleToday
              ? 'disponible aujourd’hui'
              : () {
                  final until = _humanizeUntil(p.nextResetAt);
                  return until == null ? 'déjà obtenue' : 'à nouveau dans $until';
                }());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Le Jeu Auryel',
          style: AuryelText.display(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Une récompense mini-jeu par jour, tous jeux confondus.',
          style: AuryelText.body(
            fontSize: 11.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                stars > 0 ? 'Termine une partie — +$stars ⭐' : 'Termine une partie',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AuryelText.body(
                  fontSize: 11.5,
                  color: AuryelColors.textSecondary,
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: 8),
              Text(
                status,
                textAlign: TextAlign.right,
                style: AuryelText.body(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: status == 'disponible aujourd’hui'
                      ? AuryelColors.goldLight
                      : AuryelColors.textMuted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Les seuils de temps et le crédit sont gérés par nos serveurs.',
          style: AuryelText.body(
            fontSize: 10.5,
            height: 1.4,
            color: AuryelColors.textMuted,
          ),
        ),
      ],
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
          border: Border.all(color: AuryelColors.gold.withValues(alpha: 0.35)),
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
  const _PrivacySection({required this.onDelete, required this.deleting});

  final VoidCallback onDelete;
  final bool deleting;

  void _openDoc(BuildContext context, String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Informations & confidentialité',
      icon: PhosphorIconsRegular.shieldCheck,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identité de l'éditeur — visible sans quitter l'app.
          Text(
            kPublisherIdentitySummary,
            style: AuryelText.body(
              fontSize: 11,
              height: 1.45,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            kMinimumAgeMessage,
            style: AuryelText.body(
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _LinkRow(
            label: 'Politique de confidentialité',
            icon: PhosphorIconsRegular.fileText,
            onTap: () => _openDoc(
              context,
              'Politique de confidentialité',
              kPrivacyPolicyInAppText,
            ),
          ),
          _LinkRow(
            label: 'Conditions d’utilisation',
            icon: PhosphorIconsRegular.fileText,
            onTap: () =>
                _openDoc(context, 'Conditions d’utilisation', kTermsInAppText),
          ),
          _LinkRow(
            label: 'Conditions Premium',
            icon: PhosphorIconsRegular.fileText,
            onTap: () => _openDoc(
              context,
              'Conditions Auryel Premium',
              kPremiumTermsInAppText,
            ),
          ),
          _LinkRow(
            label: 'Mentions légales',
            icon: PhosphorIconsRegular.fileText,
            onTap: () =>
                _openDoc(context, 'Mentions légales', kLegalNoticeInAppText),
          ),
          _LinkRow(
            label: 'Gérer mon abonnement',
            icon: PhosphorIconsRegular.gear,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
          ),
          const SizedBox(height: 4),
          if (deleting)
            Row(
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AuryelColors.goldLight),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Suppression en cours…',
                  style: AuryelText.body(
                    fontSize: 12.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            )
          else
            _LinkRow(
              label: 'Supprimer mon compte',
              icon: PhosphorIconsRegular.trash,
              onTap: onDelete,
            ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AuryelColors.warmBorder),
          const SizedBox(height: 12),
          // Transparence IA (wording canonique) + disclaimer produit + note IA.
          // Affichés ici une fois, jamais à chaque message de consultation.
          Text(
            kAiTransparencyText,
            style: AuryelText.body(
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AuryelColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kAuryelDisclaimerText,
            style: AuryelText.body(
              fontSize: 10.5,
              height: 1.45,
              color: AuryelColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kAiResponsesDisclaimerText,
            style: AuryelText.body(
              fontSize: 10.5,
              height: 1.45,
              color: AuryelColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne juridique : ouvre l'URL si elle existe, sinon état « bientôt » inerte
/// (jamais de lien fictif ouvert).
/// Ligne juridique. URL renseignée -> ouvre la page HTTPS externe (échec ->
/// message sobre). URL `null` -> ligne INERTE « Bientôt disponible » : jamais
/// un lien actif qui ne fait rien, jamais un lien cassé.
class LegalLinkRow extends StatelessWidget {
  const LegalLinkRow({
    super.key,
    required this.label,
    required this.url,
    required this.launcher,
  });

  final String label;
  final String? url;
  final LegalLinkLauncher launcher;

  Future<void> _open(BuildContext context) async {
    final u = url;
    if (u == null || u.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launcher.open(u);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Impossible d’ouvrir la page. Réessaie plus tard.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = url != null && url!.isNotEmpty;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PhosphorIcon(
            PhosphorIconsRegular.fileText,
            size: 14,
            color: available ? AuryelColors.goldLight : AuryelColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AuryelText.body(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: available
                    ? AuryelColors.goldLight
                    : AuryelColors.textMuted,
              ),
            ),
          ),
          if (available)
            const PhosphorIcon(
              PhosphorIconsRegular.arrowSquareOut,
              size: 12,
              color: AuryelColors.textMuted,
            )
          else
            Text(
              'Bientôt disponible',
              style: AuryelText.body(
                fontSize: 10.5,
                color: AuryelColors.textMuted,
              ),
            ),
        ],
      ),
    );
    if (!available) return row;
    return Semantics(
      button: true,
      link: true,
      label: label,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(8),
        child: row,
      ),
    );
  }
}

/// Deuxième confirmation de suppression : saisie explicite de « SUPPRIMER ».
class _DeleteConfirmDialog extends StatefulWidget {
  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final TextEditingController _c = TextEditingController();
  static const _word = 'SUPPRIMER';
  bool get _ok => _c.text.trim().toUpperCase() == _word;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AuryelColors.surface,
      title: Text(
        'Confirmer la suppression',
        style: AuryelText.display(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Écris « $_word » pour confirmer.',
            style: AuryelText.body(fontSize: 13, color: AuryelColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            style: AuryelText.display(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: AuryelColors.gold,
            decoration: const InputDecoration(
              hintText: _word,
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AuryelColors.warmBorder),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AuryelColors.gold, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Annuler',
            style: AuryelText.body(color: AuryelColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: _ok ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            'Supprimer définitivement',
            style: AuryelText.body(
              fontWeight: FontWeight.w600,
              color: _ok ? AuryelColors.goldLight : AuryelColors.textMuted,
            ),
          ),
        ),
      ],
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
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
                    borderSide: BorderSide(
                      color: AuryelColors.gold,
                      width: 1.5,
                    ),
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

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

// Legacy mission widgets remain available to their dedicated flows, but are
// intentionally not mounted on Home.
// ignore_for_file: unused_element, unused_element_parameter, unused_shown_name

import '../api/wellbeing_api.dart' show kWellbeingMissions;
import '../api/rewards_api.dart' show RewardRule;
import '../data/content_repository.dart';
import '../data/daily_like_store.dart';
import '../data/daily_share_tracker.dart';
import '../data/daily_thought.dart';
import '../data/tirage.dart';
import '../screens/splash_screen.dart';
import '../screens/consultation_screen.dart';
import '../state/auryel_state.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../state/rewards_controller.dart';
import '../state/wellbeing_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart' show AdvisorInfo, advisorByName;
import '../widgets/auryel_wordmark.dart';
import '../widgets/daily_message_sheet.dart';
import '../widgets/gold_button.dart';
import '../widgets/main_nav_scope.dart';
import '../widgets/auryel_banner.dart';
import 'dashboard_screen.dart';
import 'premium_screen.dart';
import 'rewards_wallet_screen.dart';
import 'meditation_feed_screen.dart';
import 'tirage_jeu_screen.dart';
import 'tirage_screen.dart';

/// Reset DEBUG uniquement (geste caché — appui long sur l'icône profil,
/// visible seulement en `kDebugMode`).
Future<void> _debugResetOnboarding(BuildContext context) async {
  await AuryelStateScope.of(context).debugReset();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const SplashScreen()),
    (route) => false,
  );
}

/// Accueil commercial Auryel : conseiller, temps disponible, offres puis
/// contenu quotidien. Les missions restent accessibles depuis le portefeuille
/// Étoiles, jamais supprimées de l'application.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.thoughtRepository});

  /// Injecté par les tests ; en production la source est le pack local
  /// `assets/pensees/`.
  final DailyThoughtRepository? thoughtRepository;

  @override
  Widget build(BuildContext context) {
    final state = AuryelStateScope.of(context);
    // Défensif : après un changement de compte / une connexion sur un nouvel
    // appareil, le profil local peut être absent (pas encore de récupération
    // serveur au login). `advisorByName('')` retombe alors sur le conseiller
    // par défaut (Séléna = `guide=selena` côté backend) au lieu de crasher.
    final advisor = advisorByName(state.selectedAdvisor ?? '');
    final consultation = ConsultationScope.maybeReadOf(context);
    final haloSize = math.min(360.0, MediaQuery.sizeOf(context).width);

    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 140,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: haloSize,
                  height: haloSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AuryelColors.gold.withValues(alpha: 0.16),
                        AuryelColors.gold.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(
                  children: [
                    // « Mon compte » / consultation gratuite
                    // rejoignent le flux normal de la colonne (au lieu d'un
                    // overlay `Positioned` au-dessus du wordmark) : sur les
                    // petits écrans (Samsung Galaxy A07/A075F), les 2 pilules
                    // pouvaient chevaucher visuellement « AURYEL ». En
                    // séquence, aucun chevauchement possible, quelle que soit
                    // la largeur d'écran — le logo qui suit reste toujours
                    // parfaitement centré en dessous.
                    const _AccountAndStarsRow().animate().fadeIn(
                      delay: 100.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 10),
                    const AuryelWordmark().animate().fadeIn(duration: 500.ms),
                    const SizedBox(height: 6),
                    Text(
                      'ESPACE PRIVÉ',
                      textAlign: TextAlign.center,
                      style: AuryelText.body(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: AuryelColors.textMuted,
                        letterSpacing: 2.4,
                      ),
                    ).animate().fadeIn(delay: 120.ms, duration: 500.ms),
                    const SizedBox(height: 10),
                    const _Ornament().animate().fadeIn(
                      delay: 200.ms,
                      duration: 500.ms,
                    ),
                    const SizedBox(height: 6),
                    _DailyThoughtZone(repository: thoughtRepository)
                        .animate()
                        .fadeIn(delay: 260.ms, duration: 500.ms),
                    const SizedBox(height: 10),
                    const _DailyTirageCard(),
                    const SizedBox(height: 10),
                    (consultation == null
                            ? _TimeAvailableBlock(
                                consultation: null,
                                preferredAdvisor: advisor,
                              )
                            : ListenableBuilder(
                                listenable: consultation,
                                builder: (context, _) => _TimeAvailableBlock(
                                  consultation: consultation,
                                  preferredAdvisor: advisor,
                                ),
                              ))
                        .animate()
                        .fadeIn(delay: 340.ms, duration: 500.ms),
                    const SizedBox(height: 6),
                    (consultation == null
                            ? const _ConsultationOffers(isPremium: false)
                            : ListenableBuilder(
                                listenable: consultation,
                                builder: (context, _) =>
                                    consultation.quota?.isPremium == true
                                    ? const SizedBox.shrink()
                                    : const _ConsultationOffers(
                                        isPremium: false,
                                      ),
                              ))
                        .animate()
                        .fadeIn(delay: 400.ms, duration: 500.ms),
                    const SizedBox(height: 6),
                    consultation == null
                        ? const SizedBox.shrink()
                        : ListenableBuilder(
                            listenable: consultation,
                            builder: (context, _) => AuryelBanner(
                              isPremium: consultation.quota?.isPremium,
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyTirageCard extends StatefulWidget {
  const _DailyTirageCard();

  @override
  State<_DailyTirageCard> createState() => _DailyTirageCardState();
}

class _DailyTirageCardState extends State<_DailyTirageCard>
    with WidgetsBindingObserver {
  TirageResult? _today;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  bool _isToday(DateTime value) {
    final date = value.toLocal();
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _load() async {
    final auth = AuthScope.maybeOf(context);
    if (auth == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final token = await auth.currentToken();
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final response = await auth.tirageApi.list(bearer: token, limit: 20);
      if (!mounted) return;
      setState(() {
        final today = response.tirages.where((t) => _isToday(t.createdAt));
        _today = today.isEmpty ? null : today.first;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTirage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TirageScreen(initialResult: _today)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final result = _today;
    final cardName = result?.cards.isNotEmpty == true
        ? result!.cards.first.name
        : (result == null || result.cardKeys.isEmpty
              ? null
              : result.cardKeys.first);
    final summary = result?.combinedInterpretation.trim();
    return Container(
      key: const Key('home-daily-tirage-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AuryelColors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tirage du jour', style: AuryelText.display(fontSize: 18)),
          const SizedBox(height: 4),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (result == null) ...[
            Text(
              'Une carte pour commencer la journée autrement.',
              style: AuryelText.body(color: AuryelColors.textSecondary),
            ),
            const SizedBox(height: 8),
            _CompactCta(
              key: const Key('home-daily-tirage-cta'),
              label: 'Tirer ma carte',
              onTap: _openTirage,
            ),
          ] else ...[
            Text(
              cardName ?? 'Votre carte du jour',
              style: AuryelText.display(fontSize: 16),
            ),
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AuryelText.body(
                  fontSize: 12.5,
                  color: AuryelColors.textSecondary,
                  height: 1.25,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _CompactCta(
              key: const Key('home-daily-tirage-talk'),
              label: 'En parler à mon conseiller',
              onTap: _openTirage,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CORRECTIF PRODUIT — « Mon compte » + pilule Étoiles, dans le flux normal
// de l'Accueil (ligne dédiée juste au-dessus du wordmark AURYEL, jamais un
// overlay `Positioned` par-dessus lui : c'est ce qui provoquait le
// chevauchement observé sur Samsung Galaxy A07/A075F). Le logo reste centré
// sans dépendre de la largeur des pilules.
// ---------------------------------------------------------------------------

class _AccountAndStarsRow extends StatelessWidget {
  const _AccountAndStarsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onLongPress: kDebugMode ? () => _debugResetOnboarding(context) : null,
          // CORRECTIF UX FINAL — « Mon compte » quitte la barre du bas
          // (nav V2) : ce bouton devient le SEUL accès au Dashboard depuis
          // l'Accueil. Nettement plus visible qu'une simple icône profil
          // (icône + texte, zone tactile confortable, rendu premium
          // reconnaissable comme une action de navigation, pas un détail
          // discret).
          child: Semantics(
            button: true,
            label: 'Mon compte',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                key: const Key('home-my-account-button'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: AuryelColors.surface.withValues(alpha: 0.75),
                    border: Border.all(
                      color: AuryelColors.goldLight.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PhosphorIcon(
                        PhosphorIconsFill.userCircle,
                        size: 20,
                        color: AuryelColors.goldLight,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Mon compte',
                        style: AuryelText.body(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textCream,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const _FreeConsultationPill(),
      ],
    );
  }
}

// GROS CHANTIER AURYEL (Prompt 2/5, revu au correctif produit) — pilule
// « ⭐ solde ». Le SERVEUR reste l'unique source de vérité : [RewardsScope]
// est l'instance PARTAGÉE (câblée dans main()) — jamais un solde recalculé
// ici.
//
// CORRECTIF PRODUIT — auparavant masquée tant que le wallet n'avait jamais
// chargé (« jamais un faux 0 »). Décision produit revue : la pilule reste
// TOUJOURS visible dès qu'un [RewardsScope] existe (pour que l'utilisatrice
// comprenne d'emblée que les Étoiles existent) — un neutre « … » remplace le
// montant tant que le solde réel n'est pas connu (chargement ou erreur),
// jamais un montant inventé. Solde réellement à 0 -> affiche « 0 », jamais
// masqué. Sans [RewardsScope] du tout (tests hérités qui ne montent que
// `HomeScreen` sans le câbler) : masquée, seul cas où aucune donnée n'existe.
class _FreeConsultationPill extends StatelessWidget {
  const _FreeConsultationPill();

  /// `340` en dessous de 100 000 (jamais coupé) ; compacté seulement à une
  /// très grande valeur, en gardant 1 décimale (`"1.2M"`) — jamais une simple
  /// troncature qui perdrait toute précision.
  @override
  Widget build(BuildContext context) {
    final rewards = RewardsScope.maybeOf(context);
    if (rewards == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: rewards,
      builder: (context, _) {
        final questionLabel = rewards.wallet == null
            ? 'Consultation gratuite'
            : '${rewards.questionsAvailable} question${rewards.questionsAvailable <= 1 ? '' : 's'} gratuite${rewards.questionsAvailable <= 1 ? '' : 's'}';
        final ctaLabel =
            rewards.wallet == null || rewards.questionsAvailable == 0
            ? 'Obtenir des questions →'
            : 'Ouvrir la consultation →';
        return Semantics(
          button: true,
          label: 'Consultation gratuite, $questionLabel, $ctaLabel',
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const Key('home-stars-pill'),
              borderRadius: BorderRadius.circular(999),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RewardsWalletScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 11, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AuryelColors.surface.withValues(alpha: 0.75),
                  border: Border.all(
                    color: AuryelColors.goldLight.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questionLabel,
                          key: const Key('home-free-consultation-pill-value'),
                          style: AuryelText.body(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AuryelColors.textCream,
                          ),
                        ),
                        Text(
                          ctaLabel,
                          style: AuryelText.body(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AuryelColors.goldLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _HomeAdvisorCard extends StatelessWidget {
  const _HomeAdvisorCard({required this.advisor});

  final AdvisorInfo advisor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AuryelColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuryelColors.warmBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuryelColors.goldGradient,
            ),
            child: ClipOval(
              child: Image.asset(advisor.assetPath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TON CONSEILLER',
                  style: AuryelText.body(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.gold,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
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
                    fontSize: 11.5,
                    color: AuryelColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const PhosphorIcon(
            PhosphorIconsRegular.arrowRight,
            size: 17,
            color: AuryelColors.goldLight,
          ),
        ],
      ),
    );
  }
}

class _ConsultationOffers extends StatelessWidget {
  const _ConsultationOffers({required this.isPremium});

  final bool isPremium;

  void _openPremium(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));

  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return Container(
        key: const Key('home-premium-active'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AuryelColors.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AuryelColors.warmBorder),
        ),
        child: Row(
          children: [
            const PhosphorIcon(
              PhosphorIconsRegular.crown,
              size: 18,
              color: AuryelColors.goldLight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Premium actif · Sans publicité',
                style: AuryelText.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.textCream,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OfferCard(
          key: const Key('home-premium-offer'),
          title: 'Auryel Premium',
          detail: '4 h de consultation par mois',
          price: '4,99 €/mois',
          footnote: 'Sans publicité',
          primary: true,
          cta: 'Découvrir Premium',
          onTap: () => _openPremium(context),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    super.key,
    required this.title,
    required this.detail,
    required this.price,
    required this.cta,
    required this.onTap,
    this.footnote,
    this.primary = false,
  });

  final String title, detail, price, cta;
  final String? footnote;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: primary
            ? LinearGradient(
                colors: [
                  AuryelColors.gold.withValues(alpha: 0.24),
                  AuryelColors.surface.withValues(alpha: 0.9),
                ],
              )
            : null,
        color: primary ? null : AuryelColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primary
              ? AuryelColors.goldLight.withValues(alpha: 0.7)
              : AuryelColors.warmBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AuryelText.display(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AuryelText.body(
                    fontSize: 12,
                    color: AuryelColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      price,
                      style: AuryelText.body(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AuryelColors.goldLight,
                      ),
                    ),
                    if (footnote != null)
                      Text(
                        footnote!,
                        overflow: TextOverflow.ellipsis,
                        style: AuryelText.body(
                          fontSize: 11,
                          color: AuryelColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: _CompactCta(label: cta, onTap: onTap),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 20,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.4),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
        Container(
          width: 20,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color: AuryelColors.warmBorder.withValues(alpha: 0.6),
  );
}

// ===========================================================================
// 1 — PENSÉE DU JOUR  (comportement inchangé — spacings légèrement compactés)
// ===========================================================================

class _DailyThoughtZone extends StatefulWidget {
  const _DailyThoughtZone({this.repository});

  final DailyThoughtRepository? repository;

  @override
  State<_DailyThoughtZone> createState() => _DailyThoughtZoneState();
}

class _DailyThoughtZoneState extends State<_DailyThoughtZone>
    with WidgetsBindingObserver {
  late final DailyThoughtRepository _repo =
      widget.repository ?? DailyThoughtRepository();
  final DailyShareTracker _tracker = DailyShareTracker();

  /// Source distante (serveur -> cache -> embarqué). `null` = pas de
  /// [ContentScope] dans l'arbre (tests hérités) -> on lit [_repo] embarqué.
  ContentRepository? _content;
  bool _bootstrapped = false;

  DailyThought? _thought;
  DateTime? _loadedDay;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= ContentScope.maybeOf(context);
    if (!_bootstrapped) {
      _bootstrapped = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<DailyThought> _loadThought() => _content != null
      ? _content!.thoughtFor(DateTime.now())
      : _repo.thoughtFor(DateTime.now());

  Future<void> _refresh() async {
    if (_thought != null && _loadedDay == _today) return;
    try {
      final t = await _loadThought();
      if (!mounted) return;
      setState(() {
        _thought = t;
        _loadedDay = _today;
      });
    } catch (_) {
      /* garde la pensée précédente, jamais d'écran vide */
    }
  }

  void _openPreview() {
    final t = _thought;
    if (t == null) return;
    showDailyThoughtSheet(context, thought: t, tracker: _tracker);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedDay != null && _loadedDay != _today) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }

    final split = _thought?.splitAccent();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AuryelText.body(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: AuryelColors.textSecondary,
              height: 1.32,
            ),
            children: [
              if (split != null && split.lead.isNotEmpty)
                TextSpan(text: '${split.lead} '),
              TextSpan(
                text: split?.accent ?? '',
                style: AuryelText.body(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: AuryelColors.goldLight,
                  height: 1.32,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ShareRewardBlock(onShare: _openPreview),
      ],
    );
  }
}

/// Bloc partage de la pensée du jour : bénéfice explicite + VRAI bouton
/// « Partager maintenant » (plus d'encadré ambigu ni de « Cliquez ici »). Le
/// compteur de jours reste sous le bouton, en secondaire. La logique de
/// récompense (30 jours = 1 h) est INCHANGÉE : `onShare` ouvre l'aperçu
/// partageable exactement comme avant.
/// Montant réel d'une règle Étoiles depuis le wallet partagé, `null` si
/// [RewardsScope] est absent, pas encore chargé, ou si la règle n'existe pas
/// (jamais inventé côté Flutter).
int? _ruleStarsAmount(BuildContext context, String ruleKey) {
  final rules = RewardsScope.maybeOf(context)?.rules;
  if (rules == null) return null;
  for (final RewardRule r in rules) {
    if (r.ruleKey == ruleKey) return r.starsAmount;
  }
  return null;
}

/// CORRECTIF PRODUIT — l'ancienne promesse (« 30 jours de partage = 1 h de
/// consultation ») reste un VRAI mécanisme serveur, INCHANGÉ (pas touché
/// ici), mais n'est plus mise en avant : elle coexistait avec les Étoiles et
/// brouillait le message. Le partage crédite RÉELLEMENT des Étoiles
/// (`share_completed`, `POST /api/app/rewards/daily-share`) : on affiche ce
/// gain réel quand la règle est connue, sinon un CTA neutre sans aucun
/// montant inventé. Le compteur « X / 30 jours » disparaît avec la promesse
/// qu'il servait.
class _ShareRewardBlock extends StatelessWidget {
  const _ShareRewardBlock({required this.onShare});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    const headline = 'Partage cette pensée avec tes proches';
    final block = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: AuryelText.body(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        AuryelGoldButton(label: 'Partager maintenant', onTap: onShare),
      ],
    );
    if (MediaQuery.disableAnimationsOf(context)) return block;
    return block.animate().fadeIn(duration: 320.ms);
  }
}

class _DailyLikeButton extends StatefulWidget {
  const _DailyLikeButton();

  @override
  State<_DailyLikeButton> createState() => _DailyLikeButtonState();
}

class _DailyLikeButtonState extends State<_DailyLikeButton> {
  final DailyLikeStore _store = DailyLikeStore();
  bool _liked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await _store.isLikedToday();
      if (mounted) setState(() => _liked = v);
    } catch (_) {
      /* défaut : non aimé */
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    setState(() => _liked = !_liked);
    try {
      final persisted = await _store.toggleToday();
      if (mounted && persisted != _liked) setState(() => _liked = persisted);
    } catch (_) {
      /* on garde l'état optimiste */
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _liked ? 'Retirer des favoris' : 'Ajouter aux favoris',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: PhosphorIcon(
              _liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
              size: 17,
              color: _liked ? AuryelColors.goldLight : AuryelColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 2 — TES MISSIONS DU JOUR
// ===========================================================================

/// AUDIT ACCUEIL/PARCOURS — les 4 missions quotidiennes RÉELLES, dans le même
/// ordre et avec le MÊME identifiant que le serveur (`kWellbeingMissions` :
/// pensee / tirage / consultation / moment). Accueil affiche EXACTEMENT ce
/// que « Mon parcours bien-être » affiche : les deux lisent
/// `WellbeingController.progress.today` sur la MÊME instance partagée
/// (voir [WellbeingScope], `main.dart`). Il n'existe plus de tracker local
/// séparé pour ce bloc — plus jamais deux vérités différentes.
class _MissionsSection extends StatefulWidget {
  const _MissionsSection({this.repository});

  final DailyThoughtRepository? repository;

  @override
  State<_MissionsSection> createState() => _MissionsSectionState();
}

class _MissionsSectionState extends State<_MissionsSection>
    with WidgetsBindingObserver {
  late final DailyThoughtRepository _repo =
      widget.repository ?? DailyThoughtRepository();
  // Sert UNIQUEMENT au CTA « Pensée du jour » (ouvre la feuille, qui gère
  // elle-même la récompense de partage 30 jours — un système SÉPARÉ, non
  // lié à cette mission quotidienne). N'alimente plus aucun état « terminé ».
  final DailyShareTracker _shareTracker = DailyShareTracker();

  ContentRepository? _content;
  WellbeingController? _wellbeing;
  bool _ownsWellbeing = false;
  bool _bootstrapped = false;

  DailyThought? _thought;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content ??= ContentScope.maybeOf(context);
    if (!_bootstrapped) {
      _bootstrapped = true;
      // AUDIT ACCUEIL/PARCOURS — priorité à l'instance PARTAGÉE (créée dans
      // main(), écoutée aussi par « Mon parcours bien-être ») : Accueil et
      // Parcours affichent alors TOUJOURS le même état. Repli sur un
      // contrôleur local UNIQUEMENT si aucun scope n'est câblé (tests
      // hérités qui ne montent que HomeScreen).
      final shared = WellbeingScope.maybeOf(context);
      if (shared != null) {
        _wellbeing = shared;
      } else {
        final auth = AuthScope.maybeOf(context);
        final api = auth?.wellbeingApi;
        if (auth != null && api != null) {
          _wellbeing = WellbeingController(
            api: api,
            tokenProvider: auth.currentToken,
          );
          _ownsWellbeing = true;
        }
      }
      _wellbeing?.addListener(_onWellbeingChange);
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wellbeing?.removeListener(_onWellbeingChange);
    if (_ownsWellbeing) _wellbeing?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _onWellbeingChange() {
    if (mounted) setState(() {});
  }

  Future<DailyThought> _loadThought() => _content != null
      ? _content!.thoughtFor(DateTime.now())
      : _repo.thoughtFor(DateTime.now());

  Future<void> _refresh() async {
    try {
      _thought ??= await _loadThought();
    } catch (_) {
      /* le CTA « Pensée du jour » reste ouvrable dès que le contenu arrive */
    }
    await _wellbeing?.refresh();
    if (!mounted) return;
    setState(() {});
  }

  void _goTab(int index, {VoidCallback? fallback}) {
    final scope = MainNavScope.maybeOf(context);
    if (scope != null) {
      scope.goToTab(index);
    } else {
      fallback?.call();
    }
  }

  Future<void> _onMissionTap(String missionId) async {
    switch (missionId) {
      case 'pensee':
        // Ouvre la feuille « Pensée du jour ». C'est CET appel qui enregistre
        // la mission côté serveur (`showDailyThoughtSheet` -> POST
        // /api/app/wellbeing/mission { pensee }), une fois consultée.
        final t = _thought;
        if (t == null) return;
        await showDailyThoughtSheet(
          context,
          thought: t,
          tracker: _shareTracker,
        );
      case 'tirage':
        // L’ancien hub reste accessible depuis l’espace Étoiles ; cet ancien
        // appel de compatibilité ne doit plus être utilisé par la Home.
        _goTab(
          kTabTirage,
          fallback: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TirageJeuScreen())),
        );
      case 'consultation':
        // Ouvre l'onglet central CONSULTATION -> LISTE des discussions.
        // N'ouvre JAMAIS directement un ChatScreen basé sur `selectedAdvisor`
        // (J6-F2 §12). Ne coche PAS la mission (elle se coche côté serveur
        // sur une activité de consultation réelle).
        _goTab(kTabConsultation);
      case 'moment':
        // Le lecteur reste une route interne depuis le nouveau parcours ; il
        // ne réapparaît pas comme onglet principal.
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MeditationFeedScreen()));
    }
    if (mounted) await _refresh();
  }

  static const Map<String, ({String label, IconData icon})> _labels = {
    'pensee': (label: 'Pensée du jour', icon: PhosphorIconsRegular.sparkle),
    'tirage': (label: 'Carte du jour', icon: PhosphorIconsRegular.cardsThree),
    'consultation': (
      label: 'Consultation',
      icon: PhosphorIconsRegular.chatCircle,
    ),
    'moment': (
      label: 'Prends ton temps',
      icon: PhosphorIconsRegular.flowerLotus,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final wellbeing = _wellbeing;
    final total = kWellbeingMissions.length; // 4
    final completed = wellbeing == null
        ? 0
        : kWellbeingMissions.where(wellbeing.isMissionDone).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'TES MISSIONS DU JOUR',
              style: AuryelText.body(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AuryelColors.gold,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              '$completed/$total',
              style: AuryelText.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : completed / total,
            minHeight: 3,
            backgroundColor: AuryelColors.warmBorder,
            valueColor: const AlwaysStoppedAnimation(AuryelColors.goldLight),
          ),
        ),
        const SizedBox(height: 6),
        for (final id in kWellbeingMissions)
          _MissionRow(
            label: _labels[id]!.label,
            icon: _labels[id]!.icon,
            done: wellbeing?.isMissionDone(id) ?? false,
            onTap: () => _onMissionTap(id),
          ),
        if (completed == total) ...[
          const SizedBox(height: 6),
          Text(
            'Journée Auryel complétée',
            textAlign: TextAlign.center,
            style: AuryelText.body(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.label,
    required this.icon,
    required this.done,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final animDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final color = done ? AuryelColors.goldLight : AuryelColors.textSecondary;

    return Semantics(
      button: true,
      checked: done,
      label: '$label${done ? ', accomplie' : ''}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: animDuration,
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: done
                      ? const PhosphorIcon(
                          PhosphorIconsFill.checkCircle,
                          key: ValueKey('done'),
                          size: 20,
                          color: AuryelColors.goldLight,
                        )
                      : PhosphorIcon(
                          PhosphorIconsRegular.circle,
                          key: const ValueKey('todo'),
                          size: 20,
                          color: AuryelColors.textMuted,
                        ),
                ),
                const SizedBox(width: 12),
                PhosphorIcon(icon, size: 15, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AuryelText.body(
                      fontSize: 13,
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      color: color,
                    ),
                  ),
                ),
                if (!done)
                  PhosphorIcon(
                    PhosphorIconsRegular.caretRight,
                    size: 13,
                    color: AuryelColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 3 — TEMPS DISPONIBLE (bloc compact)
// ===========================================================================

class _TimeAvailableBlock extends StatelessWidget {
  const _TimeAvailableBlock({
    required this.consultation,
    this.preferredAdvisor,
  });

  final ConsultationController? consultation;
  final AdvisorInfo? preferredAdvisor;

  String _serverTimeLabel(ConsultationController? c) {
    if (c == null) return 'Temps offert disponible';
    final t = c.time;
    if (t != null && t.totalRemainingSeconds > 0) {
      final total = t.totalRemainingSeconds;
      final minutes = total ~/ 60;
      final seconds = total % 60;
      if (!c.hasActiveSession && total == t.firstFreeRemainingSeconds) {
        return '$minutes minutes offertes';
      }
      if (c.hasActiveSession && total < 3600) {
        return '$minutes min ${seconds.toString().padLeft(2, '0')} s restantes';
      }
      final formatted = ConsultationController.formatTotalTime(total);
      return '$formatted restantes';
    }
    if (t == null && c.quota?.firstFreeAvailable == true) {
      return '20 minutes offertes';
    }
    return 'Temps de consultation épuisé';
  }

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    final hasTime =
        c == null ||
        (c.time?.totalRemainingSeconds ?? 0) > 0 ||
        (c.time == null && c.quota?.firstFreeAvailable == true);
    final value = _serverTimeLabel(c);
    final active = c?.hasActiveSession == true;
    final ctaLabel = active
        ? 'Consultation en cours'
        : 'Voir mes consultations';

    return Semantics(
      button: true,
      label: 'Ouvrir les consultations, $value',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('home-time-card'),
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final nav = MainNavScope.maybeOf(context);
            if (nav != null) {
              nav.goToTab(kTabConsultation);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConsultationScreen()),
              );
            }
          },
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AuryelColors.surface.withValues(alpha: 0.5),
              border: Border.all(color: AuryelColors.warmBorder, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TON TEMPS DE CONSULTATION',
                        style: AuryelText.body(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.gold,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: AuryelText.display(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textCream,
                        ),
                      ),
                      if (active)
                        Text(
                          'Temps réel communiqué par le serveur',
                          style: AuryelText.body(
                            fontSize: 10.5,
                            color: AuryelColors.textSecondary,
                          ),
                        ),
                      if (!hasTime)
                        Text(
                          'Découvre les solutions ci-dessous pour continuer.',
                          style: AuryelText.body(
                            fontSize: 11.5,
                            color: AuryelColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasTime) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 132,
                    child: _CompactCta(label: ctaLabel, onTap: null),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactCta extends StatelessWidget {
  const _CompactCta({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AuryelColors.backgroundDeep,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

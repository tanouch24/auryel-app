import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../data/daily_like_store.dart';
import '../data/daily_message.dart';
import '../screens/splash_screen.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import '../widgets/consultation_block.dart';
import '../widgets/daily_message_sheet.dart';
import 'advisor_chooser_screen.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'premium_screen.dart';

// Message du jour — désormais porté par [DailyMessage] (texte + interprétation +
// date), un seul point à rebrancher sur l'API contenu du jour plus tard.
const _daily = DailyMessage.today;

/// Reset DEBUG uniquement (geste caché — appui long sur l'icône profil,
/// visible seulement en `kDebugMode`) : efface les données mock
/// d'onboarding et relance l'app depuis le splash pour rejouer le parcours.
Future<void> _debugResetOnboarding(BuildContext context) async {
  await AuryelStateScope.of(context).debugReset();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const SplashScreen()),
    (route) => false,
  );
}

/// Écran d'accueil "Accueil". Contenu en dur pour l'instant — structuré
/// pour être branché sur des données réelles (phrase du jour, conseiller
/// assigné) plus tard.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// F3 — ouvre le vrai chat avec le conseiller choisi. Seul branchement du
  /// CTA consultation ; le reste de l'accueil est inchangé (redesign = F5).
  void _openChat(BuildContext context, AdvisorInfo advisor) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(advisor: advisor)));
  }

  /// F5-C — ouvre l'écran Premium (état `locked` du bloc consultation).
  void _openPremium(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
  }

  /// F5-C — état du bloc consultation dérivé de l'état RÉEL (lecture seule,
  /// aucun crédit consommé) :
  ///   session active           -> active
  ///   1re consultation offerte -> firstFree
  ///   Premium avec quota restant / crédit gagné -> subscriberAvailable
  ///   sinon                    -> locked
  static ConsultationState _deriveState(ConsultationController c) {
    if (c.hasActiveSession) return ConsultationState.active;
    final q = c.quota;
    if (q?.firstFreeAvailable == true) return ConsultationState.firstFree;
    // TIMER-D.1 — l'accès dépend du PORTEFEUILLE DE TEMPS, pas du nombre de
    // consultations. `time` présent => on tranche dessus.
    final t = c.time;
    if (t != null) {
      return t.hasTime
          ? ConsultationState.subscriberAvailable
          : ConsultationState.locked;
    }
    // Fallback backend ancien (pas de bloc `time`) : logique quota historique.
    if (q == null) return ConsultationState.firstFree;
    if (q.isPremium && q.monthlyRemaining > 0) {
      return ConsultationState.subscriberAvailable;
    }
    if (q.earnedAvailable > 0) return ConsultationState.subscriberAvailable;
    return ConsultationState.locked;
  }

  /// TIMER-D.2 — « 7 h 42 min disponibles » (accord singulier pour « < 1 min »
  /// / « 1 h » gardé au pluriel : c'est le portefeuille qui est « disponible »).
  static String _availableLabel(ConsultationController c) =>
      '${ConsultationController.formatTotalTime(c.remaining.inSeconds)} disponibles';

  /// B8.1 §3 — valeur BRUTE pour le bandeau « TEMPS DISPONIBLE » du bloc
  /// consultation. « 1 h offerte » pour la 1re heure gratuite, « 0 min » quand
  /// le portefeuille est épuisé, sinon le portefeuille formaté (« 3 h 20 min »).
  static String _timeValueFor(
    ConsultationState state,
    ConsultationController c,
  ) {
    if (state == ConsultationState.firstFree) return '1 h offerte';
    if (state == ConsultationState.locked) return '0 min';
    return ConsultationController.formatTotalTime(c.remaining.inSeconds);
  }

  /// F4/F5-C / TIMER-D.2 — bloc consultation piloté par l'état partagé.
  /// Consultation reprenable + temps dispo => bannière « Reprendre ma
  /// consultation » + « X h Y min disponibles ». Sinon CTA dérivé du TEMPS
  /// (offerte / temps dispo / épuisé).
  Widget _buildConsultationBlock(
    BuildContext context,
    ConsultationController consultation,
    AdvisorInfo fallbackAdvisor,
  ) {
    if (consultation.hasActiveSession) {
      final session = consultation.active!;
      // Le conseiller backend prime pendant la session (figé si fenêtre active).
      final advisor = advisorByGuideKey(session.advisorId) ?? fallbackAdvisor;
      return ConsultationBlock(
        state: ConsultationState.active,
        advisorName: advisor.name,
        advisorAssetPath: advisor.assetPath,
        activeResumeLabel: 'Reprendre ma consultation',
        activeRemainingText: _availableLabel(consultation),
        availableTimeValue: _timeValueFor(
          ConsultationState.active,
          consultation,
        ),
        onStart: () => _openChat(context, advisor),
      );
    }
    final derived = _deriveState(consultation);
    return ConsultationBlock(
      state: derived,
      advisorName: fallbackAdvisor.name,
      advisorAssetPath: fallbackAdvisor.assetPath,
      availableTimeText: derived == ConsultationState.subscriberAvailable
          ? _availableLabel(consultation)
          : null,
      availableTimeValue: _timeValueFor(derived, consultation),
      onStart: () => _openChat(context, fallbackAdvisor),
      onSubscribe: () => _openPremium(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AuryelStateScope.of(context);
    final advisor = advisorByName(state.selectedAdvisor!);
    // Lecture SANS dépendance : le rebuild d'1 s est confiné au bloc
    // consultation via un ListenableBuilder (l'accueil animé ne se
    // reconstruit pas à chaque tick). `null` = écran monté hors scope (tests).
    final consultation = ConsultationScope.maybeReadOf(context);
    // Le halo est décoratif : borné à la largeur de l'écran pour ne jamais
    // déborder sur les côtés (Galaxy A07 ~360 dp et en dessous).
    final haloSize = math.min(360.0, MediaQuery.sizeOf(context).width);
    return Container(
      decoration: const BoxDecoration(
        gradient: AuryelColors.backgroundGradient,
      ),
      child: Stack(
        children: [
          // Halo chaud radial derrière la phrase du jour — chaleur subtile mais perceptible.
          Positioned(
            top: 150,
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 38),
                        const _Wordmark().animate().fadeIn(duration: 600.ms),
                        const SizedBox(height: 10),
                        Text(
                          '${_daily.dateLabel} · ESPACE PRIVÉ',
                          textAlign: TextAlign.center,
                          style: AuryelText.body(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AuryelColors.textMuted,
                            letterSpacing: 2.4,
                          ),
                        ).animate().fadeIn(delay: 150.ms, duration: 600.ms),
                        const SizedBox(height: 26),
                        const _Ornament().animate().fadeIn(
                          delay: 250.ms,
                          duration: 600.ms,
                        ),
                        const SizedBox(height: 18),
                        // B8.3 §2-A/§2-B — phrase du jour d'abord, puis
                        // « Voir l'interprétation » + cœur juste en dessous.
                        _DailyMessageZone(
                          onSeeInterpretation: () =>
                              showDailyMessageSheet(context),
                        ).animate().fadeIn(delay: 500.ms, duration: 600.ms),
                        const SizedBox(height: 24),
                        (consultation == null
                                ? ConsultationBlock(
                                    state: ConsultationState.firstFree,
                                    advisorName: advisor.name,
                                    advisorAssetPath: advisor.assetPath,
                                    availableTimeValue: '1 h offerte',
                                    onStart: () => _openChat(context, advisor),
                                    onSubscribe: () => _openPremium(context),
                                  )
                                : ListenableBuilder(
                                    listenable: consultation,
                                    builder: (context, _) =>
                                        _buildConsultationBlock(
                                          context,
                                          consultation,
                                          advisor,
                                        ),
                                  ))
                            .animate()
                            .fadeIn(delay: 650.ms, duration: 600.ms)
                            .slideY(
                              begin: 0.06,
                              end: 0,
                              curve: Curves.easeOutCubic,
                            ),
                        const SizedBox(height: 10),
                        const _ChangeAdvisorLink().animate().fadeIn(
                          delay: 720.ms,
                          duration: 600.ms,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  AdvisorsCarousel(selectedAdvisorName: state.selectedAdvisor)
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 600.ms),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          // Icône profil ancrée en haut de l'écran, indépendante du bloc de
          // contenu centré — mène à l'écran "Espace" (placeholder).
          // Appui long = reset DEBUG de l'onboarding mock (kDebugMode
          // uniquement — jamais exposé comme fonctionnalité utilisateur).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onLongPress: kDebugMode
                        ? () => _debugResetOnboarding(context)
                        : null,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DashboardScreen(),
                        ),
                      ),
                      icon: PhosphorIcon(
                        PhosphorIconsThin.userCircle,
                        size: 22,
                        color: AuryelColors.textMuted,
                      ),
                      splashRadius: 20,
                    ),
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _thinRule(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ShaderMask(
            shaderCallback: (bounds) =>
                AuryelColors.goldGradient.createShader(bounds),
            child: Text(
              'AURYEL',
              style: AuryelText.display(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 6,
              ),
            ),
          ),
        ),
        _thinRule(),
      ],
    );
  }

  Widget _thinRule() {
    return Container(
      width: 34,
      height: 1,
      color: AuryelColors.gold.withValues(alpha: 0.55),
    );
  }
}

class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.4),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                gradient: AuryelColors.goldGradient,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
        Container(
          width: 22,
          height: 1,
          color: AuryelColors.gold.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

/// B8.3 §2-A/§2-B — zone message du jour de l'accueil.
/// 1) la PHRASE du jour (visible en premier).
/// 2) JUSTE EN DESSOUS : « Voir l'interprétation » (+ caret) et un cœur discret.
/// Aucun bouton « Partager » ici (le partage vit dans la feuille).
class _DailyMessageZone extends StatelessWidget {
  const _DailyMessageZone({required this.onSeeInterpretation});

  final VoidCallback onSeeInterpretation;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AuryelText.body(
              fontSize: 21,
              fontWeight: FontWeight.w400,
              color: AuryelColors.textSecondary,
              height: 1.34,
            ),
            children: [
              TextSpan(text: _daily.leadText),
              TextSpan(
                text: _daily.accentText,
                style: AuryelText.body(
                  fontSize: 21,
                  fontWeight: FontWeight.w400,
                  color: AuryelColors.goldLight,
                  height: 1.34,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeeInterpretationCta(onTap: onSeeInterpretation),
            const SizedBox(width: 2),
            const _DailyLikeButton(),
          ],
        ),
      ],
    );
  }
}

/// B8.4 §4 — CTA « Voir l'interprétation » : immédiatement identifiable comme
/// tappable. Texte plus grand + gras, underline dorée discrète, zone tactile
/// ≥ 44 dp. Reste élégant (pas de gros bouton jaune).
class _SeeInterpretationCta extends StatelessWidget {
  const _SeeInterpretationCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AuryelColors.goldLight,
                      width: 1.4,
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'Voir l’interprétation',
                  style: AuryelText.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.goldLight,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              PhosphorIcon(
                PhosphorIconsBold.caretDown,
                size: 15,
                color: AuryelColors.goldLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cœur discret : « j'aime » LOCAL du message du jour (état par jour, persisté
/// via [DailyLikeStore] -> `SharedPreferences`). Aucun backend, aucune
/// récompense. Les tests injectent l'état via `SharedPreferences.setMockInitialValues`.
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
      /* état par défaut : non aimé */
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    // Optimiste : bascule tout de suite, persiste ensuite.
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
            padding: const EdgeInsets.all(8),
            child: PhosphorIcon(
              _liked
                  ? PhosphorIconsFill.heart
                  : PhosphorIconsRegular.heart,
              size: 17,
              color: _liked
                  ? AuryelColors.goldLight
                  : AuryelColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// UX-B §5 — point d'entrée discret « Changer de conseiller », posé juste sous
/// le bloc consultation (près du conseiller préféré). Ouvre la liste des 10.
class _ChangeAdvisorLink extends StatelessWidget {
  const _ChangeAdvisorLink();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdvisorChooserScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.arrowsLeftRight,
                size: 14,
                color: AuryelColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                'Changer de conseiller',
                style: AuryelText.body(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AuryelColors.textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

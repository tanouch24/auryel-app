import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/splash_screen.dart';
import '../state/auryel_state.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart';
import '../widgets/consultation_block.dart';
import 'advisor_chooser_screen.dart';
import 'chat_screen.dart';
import 'placeholder_screen.dart';
import 'premium_screen.dart';

// La phrase du jour, en dur pour l'instant — factorisée pour que l'affichage
// (RichText) et le partage restent synchronisés sans dupliquer le texte.
const _dailyPhraseLead = 'Ce que tu n’oses pas regarder ';
const _dailyPhraseAccent = 'te dirige.';
const _dailyPhrase = '$_dailyPhraseLead$_dailyPhraseAccent';

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
    if (q == null) return ConsultationState.firstFree;
    if (q.firstFreeAvailable) return ConsultationState.firstFree;
    if (q.isPremium && q.monthlyRemaining > 0) {
      return ConsultationState.subscriberAvailable;
    }
    if (q.earnedAvailable > 0) return ConsultationState.subscriberAvailable;
    return ConsultationState.locked;
  }

  /// F4/F5-C — bloc consultation piloté par l'état partagé. Session active ET
  /// non expirée => bannière « Reprendre ma consultation · XhXX restante ».
  /// Sinon, CTA dérivé du quota (offerte / abonné / locked).
  Widget _buildConsultationBlock(
    BuildContext context,
    ConsultationController consultation,
    AdvisorInfo fallbackAdvisor,
  ) {
    if (consultation.hasActiveSession) {
      final session = consultation.active!;
      // Le conseiller backend prime pendant la session.
      final advisor = advisorByGuideKey(session.advisorId) ?? fallbackAdvisor;
      final remaining = ConsultationController.formatRemaining(
        consultation.remaining,
      );
      return ConsultationBlock(
        state: ConsultationState.active,
        advisorName: advisor.name,
        advisorAssetPath: advisor.assetPath,
        activeResumeLabel: 'Reprendre ma consultation · $remaining restante',
        onStart: () => _openChat(context, advisor),
      );
    }
    return ConsultationBlock(
      state: _deriveState(consultation),
      advisorName: fallbackAdvisor.name,
      advisorAssetPath: fallbackAdvisor.assetPath,
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
                  width: 360,
                  height: 360,
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
                        const SizedBox(height: 56),
                        const _Wordmark().animate().fadeIn(duration: 600.ms),
                        const SizedBox(height: 10),
                        Text(
                          'MARDI 25 AOÛT · ESPACE PRIVÉ',
                          textAlign: TextAlign.center,
                          style: AuryelText.body(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AuryelColors.textMuted,
                            letterSpacing: 2.4,
                          ),
                        ).animate().fadeIn(delay: 150.ms, duration: 600.ms),
                        const SizedBox(height: 56),
                        const _Ornament().animate().fadeIn(
                          delay: 250.ms,
                          duration: 600.ms,
                        ),
                        const SizedBox(height: 22),
                        RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: AuryelText.display(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w500,
                                  height: 1.32,
                                ),
                                children: [
                                  const TextSpan(text: _dailyPhraseLead),
                                  TextSpan(
                                    text: _dailyPhraseAccent,
                                    style: AuryelText.display(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w500,
                                      fontStyle: FontStyle.italic,
                                      color: AuryelColors.goldLight,
                                      height: 1.32,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .animate()
                            .fadeIn(delay: 350.ms, duration: 700.ms)
                            .slideY(
                              begin: 0.08,
                              end: 0,
                              curve: Curves.easeOutCubic,
                            ),
                        const SizedBox(height: 28),
                        _TapToRead().animate().fadeIn(
                          delay: 550.ms,
                          duration: 600.ms,
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'Ce message te fait penser à quelqu’un ?',
                          textAlign: TextAlign.center,
                          style: AuryelText.body(
                            fontSize: 13,
                            color: AuryelColors.textSecondary,
                          ),
                        ).animate().fadeIn(delay: 580.ms, duration: 600.ms),
                        const SizedBox(height: 12),
                        const _ShareButton().animate().fadeIn(
                          delay: 600.ms,
                          duration: 600.ms,
                        ),
                        const SizedBox(height: 32),
                        (consultation == null
                                ? ConsultationBlock(
                                    state: ConsultationState.firstFree,
                                    advisorName: advisor.name,
                                    advisorAssetPath: advisor.assetPath,
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
                        const SizedBox(height: 12),
                        const _ChangeAdvisorLink().animate().fadeIn(
                          delay: 720.ms,
                          duration: 600.ms,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
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
                          builder: (_) => const PlaceholderScreen(
                            title: 'Mon espace',
                            icon: PhosphorIconsRegular.userCircle,
                            subtitle: 'Bientôt, ton espace personnel.',
                          ),
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

class _TapToRead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Découvrir le message du jour',
          style: AuryelText.body(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AuryelColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        PhosphorIcon(
          PhosphorIconsThin.caretDown,
          size: 16,
          color: AuryelColors.textMuted,
        ),
      ],
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

class _ShareButton extends StatelessWidget {
  const _ShareButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => SharePlus.instance.share(
          ShareParams(text: '$_dailyPhrase\n\n— Auryel'),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AuryelColors.gold.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.shareNetwork,
                size: 15,
                color: AuryelColors.goldLight,
              ),
              const SizedBox(width: 8),
              Text(
                'Partager',
                style: AuryelText.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AuryelColors.goldLight,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

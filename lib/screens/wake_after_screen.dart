import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../api/api_client.dart';
import '../data/advisor_audio.dart';
import '../data/consultation.dart';
import '../screens/advisor_selector_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/onboarding/email_auth_screen.dart';
import '../state/auth_controller.dart';
import '../state/consultation_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/advisors_carousel.dart' show AdvisorInfo;
import '../widgets/main_nav_shell.dart';

/// Écran calme affiché après extinction du Réveil Auryel — « Belle journée ».
/// Deux CTA seulement : parler au conseiller (mécanisme EXISTANT, identique
/// à « En parler » depuis un tirage — l'utilisateur choisit qui contacter,
/// jamais un conseiller fictif propre au réveil), ou continuer sa journée
/// (retour Accueil). Auth/quota/Premium : entièrement gérés par
/// [ConsultationController.openAdvisor] / [ChatScreen], rien de spécifique
/// ici.
class WakeAfterScreen extends StatefulWidget {
  const WakeAfterScreen({
    super.key,
    this.selectorAudioOverride,
    this.pendingContext,
  });

  /// Test uniquement : lecteur audio du sélecteur de conseiller injecté
  /// (aucun canal plateforme réel en test) — même mécanisme que
  /// `TirageScreen.selectorAudioOverride`.
  final AdvisorAudio? selectorAudioOverride;

  /// Brouillon contextuel à remettre au chat après un réveil réel. Il reste
  /// soumis à l'envoi explicite de l'utilisateur et n'est jamais envoyé ici.
  final String? pendingContext;

  @override
  State<WakeAfterScreen> createState() => _WakeAfterScreenState();
}

class _WakeAfterScreenState extends State<WakeAfterScreen> {
  bool _opening = false;

  void _continueMyDay() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavShell()),
      (route) => false,
    );
  }

  /// Même mécanisme que `TirageScreen._talkAboutTirage` (J6-F2 §13) : choix
  /// du conseiller par l'utilisateur, fil existant repris sinon nouveau fil
  /// ouvert via `openAdvisor` — jamais de conseiller parallèle inventé pour
  /// le réveil, jamais de contournement d'auth/quota/Premium.
  Future<void> _talkToAdvisor() async {
    if (_opening) return;
    setState(() => _opening = true);
    final controller = ConsultationScope.maybeReadOf(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await controller?.refreshConsultations();
    if (!mounted) return;

    final existing = <String, ConsultationSummaryDto>{
      for (final c
          in controller?.consultations ?? const <ConsultationSummaryDto>[])
        c.advisorId: c,
    };

    final picked = await navigator.push<AdvisorInfo>(
      MaterialPageRoute(
        builder: (_) => AdvisorSelectorScreen(
          title: 'Avec qui veux-tu commencer ta journée ?',
          existingAdvisorIds: existing.keys.toSet(),
          audioOverride: widget.selectorAudioOverride,
        ),
      ),
    );
    if (!mounted) return;
    if (picked == null) {
      setState(() => _opening = false);
      return;
    }

    final known = existing[picked.guideKey];
    if (known != null) {
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            consultationId: known.id,
            advisor: picked,
            initialMessage: widget.pendingContext,
          ),
        ),
      );
      return;
    }
    if (controller == null) {
      setState(() => _opening = false);
      return;
    }

    try {
      final dto = await controller.openAdvisor(picked.guideKey);
      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            consultationId: dto.id,
            advisor: picked,
            initialMessage: widget.pendingContext,
          ),
        ),
      );
    } on ApiUnauthorizedException {
      await AuthScope.of(context).invalidateSession();
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _opening = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Connexion impossible — réessaie.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _continueMyDay();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: AuryelColors.backgroundGradient,
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PhosphorIcon(
                      PhosphorIconsRegular.sunHorizon,
                      size: 56,
                      color: AuryelColors.goldLight,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Belle journée',
                      textAlign: TextAlign.center,
                      style: AuryelText.display(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: AuryelColors.textCream,
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _opening ? null : _talkToAdvisor,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: AuryelColors.goldGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              child: Center(
                                child: _opening
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AuryelColors.backgroundDeep,
                                        ),
                                      )
                                    : Text(
                                        'Parler à mon conseiller',
                                        style: AuryelText.body(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AuryelColors.backgroundDeep,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _opening ? null : _continueMyDay,
                      child: Text(
                        'Continuer ma journée',
                        style: AuryelText.body(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AuryelColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/auryel_theme.dart';
import 'gold_button.dart';

/// Coquille commune aux écrans d'onboarding : retour optionnel, puces de
/// progression, titre/sous-titre, contenu défilant, CTA or fixé en bas
/// (optionnel — l'écran de création de compte n'en a pas besoin, ses 3
/// boutons de connexion jouent ce rôle).
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.totalSteps,
    this.showBack = true,
    required this.title,
    this.subtitle,
    required this.child,
    this.ctaLabel,
    this.onCta,
    this.ctaEnabled = true,
  });

  final int step;
  final int totalSteps;
  final bool showBack;
  final String title;
  final String? subtitle;
  final Widget child;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final bool ctaEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: showBack
                          ? IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: PhosphorIcon(
                                PhosphorIconsThin.arrowLeft,
                                size: 20,
                                color: AuryelColors.textMuted,
                              ),
                              splashRadius: 18,
                            )
                          : null,
                    ),
                    Expanded(
                      child: Center(
                        child: _StepDots(step: step, totalSteps: totalSteps),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AuryelText.display(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: AuryelText.body(
                            fontSize: 13.5,
                            color: AuryelColors.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      child,
                    ],
                  ),
                ),
              ),
              if (ctaLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                  child: AuryelGoldButton(
                    label: ctaLabel!,
                    onTap: onCta ?? () {},
                    enabled: ctaEnabled,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.totalSteps});

  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (i) {
        final active = i < step;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: active
                ? AuryelColors.gold
                : AuryelColors.textMuted.withValues(alpha: 0.35),
          ),
        );
      }),
    );
  }
}

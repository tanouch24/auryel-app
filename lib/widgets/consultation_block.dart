import 'package:flutter/material.dart';

import '../theme/auryel_theme.dart';

/// Les 4 états possibles du bloc consultation sur l'accueil.
/// Pour l'instant piloté par une variable en dur (voir home_screen.dart) —
/// sera branché sur l'état réel de session/abonnement plus tard.
enum ConsultationState { firstFree, active, subscriberAvailable, locked }

/// Bloc "conseiller / consultation" de l'accueil. Design fidèle au panneau
/// conseiller (anneau or autour du portrait, liseré subtil) avec un CTA or
/// plein — c'est l'action premium de l'écran.
class ConsultationBlock extends StatelessWidget {
  const ConsultationBlock({
    super.key,
    required this.state,
    required this.advisorName,
    required this.advisorAssetPath,
    this.onStart,
    this.activeResumeLabel,
    this.activeRemainingText,
  });

  final ConsultationState state;
  final String advisorName;
  final String advisorAssetPath;

  /// Callback du CTA principal (F3 : ouvrir le ChatScreen). Injecté par
  /// l'écran hôte plutôt que codé en dur dans le widget.
  final VoidCallback? onStart;

  /// F4 — libellé du CTA quand une VRAIE session est active (ex.
  /// « Reprendre ma consultation · 1h40 restante »). `null` => libellé par
  /// défaut « Continuer ma consultation ».
  final String? activeResumeLabel;

  /// F4 — temps restant réel dérivé de `ConsultationController` ; remplace
  /// l'ancien texte fictif « Encore 22h ». `null` => aucune sous-ligne.
  final String? activeRemainingText;

  @override
  Widget build(BuildContext context) {
    if (state == ConsultationState.active) {
      return _ActiveBanner(
        name: advisorName,
        assetPath: advisorAssetPath,
        onStart: onStart,
        resumeLabel: activeResumeLabel,
        remainingText: activeRemainingText,
      );
    }
    return _StandardCard(
      state: state,
      name: advisorName,
      assetPath: advisorAssetPath,
      onStart: onStart,
    );
  }
}

class _StandardCard extends StatelessWidget {
  const _StandardCard({
    required this.state,
    required this.name,
    required this.assetPath,
    this.onStart,
  });

  final ConsultationState state;
  final String name;
  final String assetPath;
  final VoidCallback? onStart;

  (String, String) get _copy => switch (state) {
    ConsultationState.firstFree => (
      'Ta première consultation de 24h est offerte',
      'Commencer ma consultation',
    ),
    ConsultationState.subscriberAvailable => (
      'Une question ? Ton conseiller est là pour toi.',
      'Ouvrir une consultation',
    ),
    ConsultationState.locked => (
      'Envie de retrouver ton conseiller ?',
      'S’abonner pour consulter',
    ),
    ConsultationState.active => ('', ''), // non utilisé ici
  };

  @override
  Widget build(BuildContext context) {
    final (body, cta) = _copy;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Portrait(assetPath: assetPath, size: 68),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AuryelText.display(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: AuryelText.body(
                        fontSize: 12.5,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _GoldButton(label: cta, onTap: onStart),
        ],
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({
    required this.name,
    required this.assetPath,
    this.onStart,
    this.resumeLabel,
    this.remainingText,
  });

  final String name;
  final String assetPath;
  final VoidCallback? onStart;
  final String? resumeLabel;
  final String? remainingText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AuryelColors.surfaceLight,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AuryelColors.gold.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Portrait(assetPath: assetPath, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ta consultation avec $name est en cours',
                      style: AuryelText.display(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (remainingText != null &&
                        remainingText!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        remainingText!,
                        style: AuryelText.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AuryelColors.goldLight,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GoldButton(
            label: resumeLabel ?? 'Continuer ma consultation',
            onTap: onStart,
          ),
        ],
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AuryelColors.goldGradient,
      ),
      child: ClipOval(child: Image.asset(assetPath, fit: BoxFit.cover)),
    );
  }
}

/// Bouton or plein — l'action premium de l'accueil, doit rester bien visible.
class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AuryelColors.goldGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AuryelText.body(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AuryelColors.backgroundDeep,
                    letterSpacing: 0.4,
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

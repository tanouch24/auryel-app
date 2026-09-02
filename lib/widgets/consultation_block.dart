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
    this.onSubscribe,
    this.activeResumeLabel,
    this.activeRemainingText,
    this.availableTimeText,
    this.availableTimeValue,
  });

  final ConsultationState state;
  final String advisorName;
  final String advisorAssetPath;

  /// B8.1 §3 — valeur BRUTE du temps disponible mise en avant (« 3 h 20 min »,
  /// « 1 h offerte », « 0 min »), affichée sous un libellé « TEMPS DISPONIBLE »
  /// bien visible en tête du bloc. `null` => pas de bandeau temps.
  final String? availableTimeValue;

  /// Callback du CTA principal (F3 : ouvrir le ChatScreen). Injecté par
  /// l'écran hôte plutôt que codé en dur dans le widget.
  final VoidCallback? onStart;

  /// F5-C — CTA de l'état `locked` (« S'abonner pour consulter ») : ouvre
  /// l'écran Premium. La navigation est gérée par l'écran hôte, pas ici.
  final VoidCallback? onSubscribe;

  /// F4 — libellé du CTA quand une consultation est reprenable (ex.
  /// « Reprendre ma consultation »). `null` => « Continuer ma consultation ».
  final String? activeResumeLabel;

  /// TIMER-D.2 — sous-ligne « portefeuille de temps » de la bannière active
  /// (ex. « 7 h 42 min disponibles »). `null` => aucune sous-ligne.
  final String? activeRemainingText;

  /// TIMER-D.2 — sous-texte « temps disponible » de la carte `subscriberAvailable`
  /// (ex. « 7 h 42 min disponibles »). `null` => texte d'invite générique.
  final String? availableTimeText;

  @override
  Widget build(BuildContext context) {
    if (state == ConsultationState.active) {
      return _ActiveBanner(
        name: advisorName,
        assetPath: advisorAssetPath,
        onStart: onStart,
        resumeLabel: activeResumeLabel,
        remainingText: activeRemainingText,
        timeValue: availableTimeValue,
      );
    }
    return _StandardCard(
      state: state,
      name: advisorName,
      assetPath: advisorAssetPath,
      onStart: onStart,
      onSubscribe: onSubscribe,
      availableTimeText: availableTimeText,
      timeValue: availableTimeValue,
    );
  }
}

class _StandardCard extends StatelessWidget {
  const _StandardCard({
    required this.state,
    required this.name,
    required this.assetPath,
    this.onStart,
    this.onSubscribe,
    this.availableTimeText,
    this.timeValue,
  });

  final ConsultationState state;
  final String name;
  final String assetPath;
  final VoidCallback? onStart;
  final VoidCallback? onSubscribe;
  final String? availableTimeText;
  final String? timeValue;

  (String, String) get _copy => switch (state) {
    ConsultationState.firstFree => (
      // TIMER-D.1/D.2 — 1 h offerte, une seule fois par compte.
      'Ta première heure de consultation est offerte',
      'Commencer ma consultation',
    ),
    ConsultationState.subscriberAvailable => (
      // TIMER-D.2 — met en avant le PORTEFEUILLE DE TEMPS quand il est connu.
      availableTimeText ?? 'Ton conseiller est là quand tu en as besoin.',
      'Ouvrir une consultation',
    ),
    ConsultationState.locked => (
      'Ton temps de consultation est épuisé.',
      'S’abonner pour consulter',
    ),
    ConsultationState.active => ('', ''), // non utilisé ici
  };

  @override
  Widget build(BuildContext context) {
    final (body, cta) = _copy;
    // L'état `locked` invite à s'abonner -> ouvre l'écran Premium ;
    // les autres états ouvrent une consultation.
    final onTap = state == ConsultationState.locked ? onSubscribe : onStart;
    return Container(
      // B8.3 §2-C — bloc consultation plus compact (padding + tailles internes
      // resserrés) pour laisser « Découvre nos conseillers » remonter dans
      // l'écran, sans perdre en lisibilité ni casser la DA.
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AuryelColors.warmBorder, width: 1),
      ),
      child: Column(
        children: [
          if (timeValue != null) ...[
            _TimeAvailable(value: timeValue!),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _Portrait(assetPath: assetPath, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AuryelText.display(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: AuryelText.body(
                        fontSize: 12,
                        height: 1.3,
                        color: AuryelColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GoldButton(label: cta, onTap: onTap),
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
    this.timeValue,
  });

  final String name;
  final String assetPath;
  final VoidCallback? onStart;
  final String? resumeLabel;
  final String? remainingText;
  final String? timeValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AuryelColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AuryelColors.gold.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          if (timeValue != null) ...[
            _TimeAvailable(value: timeValue!),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              _Portrait(assetPath: assetPath, size: 46),
              const SizedBox(width: 13),
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
                    if (remainingText != null && remainingText!.isNotEmpty) ...[
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
          const SizedBox(height: 12),
          _GoldButton(
            label: resumeLabel ?? 'Continuer ma consultation',
            onTap: onStart,
          ),
        ],
      ),
    );
  }
}

/// B8.1 §3 — bandeau « TEMPS DISPONIBLE » en tête du bloc consultation : le
/// portefeuille de temps du modèle TIMER doit se lire d'un coup d'œil sur
/// l'accueil (constat réel : la valeur était noyée en sous-texte).
class _TimeAvailable extends StatelessWidget {
  const _TimeAvailable({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEMPS DISPONIBLE',
          style: AuryelText.body(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AuryelColors.textMuted,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AuryelText.display(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
            height: 1.1,
          ),
        ),
      ],
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
              padding: const EdgeInsets.symmetric(vertical: 12),
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

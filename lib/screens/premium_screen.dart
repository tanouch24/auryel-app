import 'package:flutter/material.dart';

import '../state/purchase_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';

/// Écran d'abonnement Premium (F5-C).
///
/// Se branche EXCLUSIVEMENT sur [PurchaseController] (via [PurchaseScope]) —
/// aucun appel direct à `InAppPurchase`, aucun droit Premium local. Le prix
/// affiché vient de `ProductDetails.price` (store) quand disponible ; sinon un
/// libellé neutre, jamais un prix inventé. Le droit réel reste porté par le
/// backend (`ConsultationController.quota.isPremium`), relu après un verify 200.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PurchaseScope.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _Body(controller: controller),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final PurchaseController controller;

  String get _priceLabel {
    final p = controller.premiumProduct?.price;
    return (p != null && p.isNotEmpty) ? p : 'Abonnement mensuel';
  }

  @override
  Widget build(BuildContext context) {
    final s = controller.state;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AuryelColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Auryel Premium',
            style: AuryelText.display(
              fontSize: 30,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          const _OfferLine('4 consultations de 2 h par mois'),
          const SizedBox(height: 10),
          const _OfferLine('Messages illimités pendant chaque consultation'),
          const SizedBox(height: 22),
          Text(
            _priceLabel,
            style: AuryelText.body(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(height: 24),
          _StatusArea(state: s, errorCode: controller.errorCode),
          const SizedBox(height: 20),
          _PrimaryAction(controller: controller),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: controller.canRestore
                  ? controller.restorePurchases
                  : null,
              child: Text(
                'Restaurer mes achats',
                style: AuryelText.body(
                  fontWeight: FontWeight.w600,
                  color: controller.canRestore
                      ? AuryelColors.goldLight
                      : AuryelColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferLine extends StatelessWidget {
  const _OfferLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 10),
          child: Icon(
            Icons.check_rounded,
            size: 16,
            color: AuryelColors.goldLight,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AuryelText.body(
              fontSize: 13.5,
              color: AuryelColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Message + éventuel indicateur de progression selon [PurchaseState].
class _StatusArea extends StatelessWidget {
  const _StatusArea({required this.state, this.errorCode});

  final PurchaseState state;
  final String? errorCode;

  ({String message, bool busy}) get _content => switch (state) {
    PurchaseState.loadingProducts => (
      message: 'Chargement de l’offre…',
      busy: true,
    ),
    PurchaseState.productsUnavailable => (
      message: 'L’abonnement n’est pas encore disponible.',
      busy: false,
    ),
    PurchaseState.storeUnavailable => (
      message: 'Le service d’achat est temporairement indisponible.',
      busy: false,
    ),
    PurchaseState.purchasing => (message: 'Ouverture du paiement…', busy: true),
    PurchaseState.pendingStore => (
      message: 'Achat en attente de confirmation.',
      busy: true,
    ),
    PurchaseState.verifying => (
      message: 'Vérification de ton abonnement…',
      busy: true,
    ),
    PurchaseState.verifyRetryable => (
      message:
          'La vérification n’a pas abouti. Ton achat est conservé — réessaie.',
      busy: false,
    ),
    PurchaseState.verifyFatal => (
      message: 'Ton achat n’a pas pu être validé. Contacte le support si le problème persiste.',
      busy: false,
    ),
    PurchaseState.requiresAuthentication => (
      message: 'Reconnecte-toi pour finaliser ton abonnement.',
      busy: false,
    ),
    PurchaseState.active => (message: 'Premium est activé.', busy: false),
    PurchaseState.storeError => (
      message: 'Une erreur est survenue avec le magasin. Réessaie.',
      busy: false,
    ),
    // idle / canceled : aucun message alarmant.
    PurchaseState.idle || PurchaseState.canceled => (message: '', busy: false),
  };

  @override
  Widget build(BuildContext context) {
    final c = _content;
    if (c.message.isEmpty) return const SizedBox.shrink();
    final isSuccess = state == PurchaseState.active;
    return Row(
      children: [
        if (c.busy) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            c.message,
            style: AuryelText.body(
              fontSize: 13,
              color: isSuccess
                  ? AuryelColors.goldLight
                  : AuryelColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bouton principal : « S'abonner », ou « Réessayer » quand la vérification
/// est récupérable.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.controller});

  final PurchaseController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.state == PurchaseState.active) {
      return const SizedBox.shrink();
    }
    if (controller.state == PurchaseState.verifyRetryable) {
      return AuryelGoldButton(
        label: 'Réessayer',
        onTap: controller.retryVerification,
      );
    }
    return AuryelGoldButton(
      label: 'S’abonner',
      enabled: controller.canBuy,
      onTap: controller.buyPremium,
    );
  }
}

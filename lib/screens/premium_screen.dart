import 'package:flutter/material.dart';

import '../config/legal_texts.dart';
import '../data/subscription_manager.dart';
import '../state/consultation_controller.dart';
import '../state/meta_consent_controller.dart';
import '../state/purchase_controller.dart';
import '../theme/auryel_theme.dart';
import '../widgets/gold_button.dart';
import 'legal_document_screen.dart';

/// Écran d'abonnement Premium (F5-C).
///
/// Se branche sur [PurchaseController] (via [PurchaseScope]) pour le tunnel
/// d'achat, et sur [ConsultationController] (via [ConsultationScope]) pour la
/// SOURCE DE VÉRITÉ du droit Premium (`quota.isPremium`) et du temps disponible
/// (`availableTimeLabel`). Aucun appel direct à `InAppPurchase`, aucun droit
/// Premium local, aucun prix inventé (`ProductDetails.price` d'abord ;
/// « 7,99 €/mois » n'est qu'un repli marketing clairement secondaire).
///
/// L'app ne résilie jamais elle-même : « Gérer mon abonnement » ouvre la page
/// officielle Google Play via [SubscriptionManager].
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key, this.subscriptionManager});

  /// Test uniquement : sinon [defaultSubscriptionManager].
  final SubscriptionManager? subscriptionManager;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _paywallLogged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_paywallLogged) return;
    _paywallLogged = true;
    // Meta : « paywall vu » (une fois par ouverture d'écran). No-op sans
    // consentement. Aucune donnée personnelle.
    AnalyticsScope.eventsOf(context).logPaywallViewed();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionManager = widget.subscriptionManager;
    final controller = PurchaseScope.of(context);
    final consultation = ConsultationScope.maybeReadOf(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AuryelColors.backgroundGradient,
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _Body(
              controller: controller,
              isPremium: consultation?.quota?.isPremium ?? false,
              timeLabel: consultation?.availableTimeLabel,
              subscriptionManager:
                  subscriptionManager ?? defaultSubscriptionManager,
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.isPremium,
    required this.timeLabel,
    required this.subscriptionManager,
  });

  final PurchaseController controller;
  final bool isPremium;
  final String? timeLabel;
  final SubscriptionManager subscriptionManager;

  String get _priceLabel {
    final p = controller.premiumProduct?.price;
    // Prix STORE d'abord (régionalisé, autoritaire). Store indisponible ->
    // libellé neutre, JAMAIS un prix inventé ni un faux ProductDetails
    // (le « 7,99 €/mois » marketing vit sur la carte Dashboard, pas ici).
    return (p != null && p.isNotEmpty) ? p : 'Abonnement mensuel';
  }

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
          if (isPremium)
            _ActiveBlock(
              timeLabel: timeLabel,
              onManage: () => _manage(context),
              onRestore: controller.canRestore
                  ? controller.restorePurchases
                  : null,
            )
          else
            _OfferBlock(priceLabel: _priceLabel, controller: controller),
          const SizedBox(height: 24),
          _ExtraHourBlock(controller: controller),
          const SizedBox(height: 20),
          const _LegalFooter(),
        ],
      ),
    );
  }
}

/// Rappel juridique de l'écran Premium + accès aux textes DANS l'app.
/// Ces boutons NE déclenchent aucun achat : ils ouvrent [LegalDocumentScreen].
class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  void _openDoc(BuildContext context, String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: AuryelColors.warmBorder),
        const SizedBox(height: 12),
        Text(
          'Abonnement mensuel à renouvellement automatique via Google Play ou '
          'l’App Store. Le prix est celui indiqué par le Store avant l’achat. '
          '8 h de consultation par mois, messages illimités pendant le temps '
          'disponible. Résiliation à tout moment depuis le Store. Restauration '
          'des achats disponible ci-dessus. Détails dans les Conditions '
          'Premium.',
          style: AuryelText.body(
            fontSize: 10.5,
            height: 1.5,
            color: AuryelColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _DocLink(
              label: 'Conditions Premium',
              onTap: () => _openDoc(
                context,
                'Conditions Auryel Premium',
                kPremiumTermsInAppText,
              ),
            ),
            _DocLink(
              label: 'Politique de confidentialité',
              onTap: () => _openDoc(
                context,
                'Politique de confidentialité',
                kPrivacyPolicyInAppText,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DocLink extends StatelessWidget {
  const _DocLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: AuryelText.body(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
          ),
        ),
      ),
    );
  }
}

/// Utilisateur DÉJÀ Premium (source : backend). Aucun CTA d'achat.
class _ActiveBlock extends StatelessWidget {
  const _ActiveBlock({
    required this.timeLabel,
    required this.onManage,
    required this.onRestore,
  });

  final String? timeLabel;
  final VoidCallback onManage;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Premium actif',
          style: AuryelText.body(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AuryelColors.goldLight,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Temps disponible',
          style: AuryelText.body(fontSize: 12, color: AuryelColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          timeLabel ?? '—',
          style: AuryelText.display(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AuryelColors.goldLight,
          ),
        ),
        const SizedBox(height: 22),
        AuryelGoldButton(label: 'Gérer mon abonnement', onTap: onManage),
        const SizedBox(height: 10),
        if (onRestore != null)
          Center(
            child: TextButton(
              onPressed: onRestore,
              child: Text(
                'Restaurer mes achats',
                style: AuryelText.body(
                  fontWeight: FontWeight.w600,
                  color: AuryelColors.goldLight,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Ton abonnement se renouvelle automatiquement chaque mois. Tu peux '
          'le résilier à tout moment depuis Google Play ; il reste actif '
          'jusqu’à la fin de la période déjà payée.',
          style: AuryelText.body(
            fontSize: 11.5,
            height: 1.4,
            color: AuryelColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Utilisateur NON Premium : présentation de l'offre + tunnel d'achat.
class _OfferBlock extends StatelessWidget {
  const _OfferBlock({required this.priceLabel, required this.controller});

  final String priceLabel;
  final PurchaseController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _OfferLine('8 h de consultation par mois'),
        const SizedBox(height: 10),
        const _OfferLine('Messages illimités pendant le temps disponible'),
        const SizedBox(height: 22),
        Text(
          priceLabel,
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
        const SizedBox(height: 16),
        Text(
          'Abonnement mensuel, renouvelé automatiquement via Google Play. '
          'Résiliable à tout moment depuis Google Play → Abonnements. '
          'Le paiement se fait uniquement via ton compte Google Play — aucun '
          'paiement sur un autre site.',
          style: AuryelText.body(
            fontSize: 11,
            height: 1.4,
            color: AuryelColors.textMuted,
          ),
        ),
      ],
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
      message:
          'Ton achat n’a pas pu être validé. Contacte le support si le '
          'problème persiste.',
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

/// Achat « 1 heure supplémentaire » (consommable, RÉPÉTABLE). Visible pour
/// tous — abonné ou non. Le crédit de 3600 s est décidé par le serveur ; ici
/// on n'affiche qu'un état. Le prix vient de `ProductDetails.price` (« 1,99 € »
/// est un repli).
class _ExtraHourBlock extends StatelessWidget {
  const _ExtraHourBlock({required this.controller});

  final PurchaseController controller;

  /// Prix STORE uniquement (régionalisé, autoritaire). Aucun prix inventé si
  /// le produit n'est pas chargé — le « 1,99 € » de référence vit dans les
  /// Conditions Premium.
  String? get _price {
    final p = controller.extraHourProduct?.price;
    return (p != null && p.isNotEmpty) ? p : null;
  }

  ({String message, bool busy})? get _status => switch (controller.extraHourState) {
    ExtraHourPurchaseState.purchasing => (
      message: 'Ouverture du paiement…',
      busy: true,
    ),
    ExtraHourPurchaseState.pendingStore => (
      message: 'Achat en attente de confirmation.',
      busy: true,
    ),
    ExtraHourPurchaseState.verifying => (
      message: 'Validation de ton achat…',
      busy: true,
    ),
    ExtraHourPurchaseState.credited => (
      message: '1 heure supplémentaire ajoutée à ton temps de consultation.',
      busy: false,
    ),
    ExtraHourPurchaseState.alreadyCredited => (
      message: 'Cet achat a déjà été crédité — ton temps est à jour.',
      busy: false,
    ),
    ExtraHourPurchaseState.verifyRetryable => (
      message:
          'La validation n’a pas abouti. Ton achat est conservé — réessaie.',
      busy: false,
    ),
    ExtraHourPurchaseState.verifyFatal => (
      message:
          'Ton achat n’a pas pu être validé. Contacte le support si le '
          'problème persiste.',
      busy: false,
    ),
    ExtraHourPurchaseState.requiresAuthentication => (
      message: 'Reconnecte-toi pour finaliser ton achat.',
      busy: false,
    ),
    ExtraHourPurchaseState.storeError => (
      message: 'Une erreur est survenue avec le magasin. Réessaie.',
      busy: false,
    ),
    ExtraHourPurchaseState.unavailable => (
      message: 'L’achat d’une heure supplémentaire n’est pas disponible pour '
          'le moment.',
      busy: false,
    ),
    ExtraHourPurchaseState.idle || ExtraHourPurchaseState.canceled => null,
  };

  @override
  Widget build(BuildContext context) {
    final s = controller.extraHourState;
    final status = _status;
    final unavailable = s == ExtraHourPurchaseState.unavailable ||
        controller.extraHourProduct == null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AuryelColors.warmBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1 heure supplémentaire',
            style: AuryelText.body(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AuryelColors.goldLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ajoute 1 heure de consultation à ton temps disponible. Achat '
            'unique, renouvelable autant de fois que tu veux.',
            style: AuryelText.body(
              fontSize: 12,
              height: 1.4,
              color: AuryelColors.textMuted,
            ),
          ),
          if (_price != null) ...[
            const SizedBox(height: 12),
            Text(
              _price!,
              style: AuryelText.body(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AuryelColors.goldLight,
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (status.busy) ...[
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AuryelColors.goldLight,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    status.message,
                    style: AuryelText.body(
                      fontSize: 12.5,
                      color: s == ExtraHourPurchaseState.credited
                          ? AuryelColors.goldLight
                          : AuryelColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (s == ExtraHourPurchaseState.verifyRetryable)
            AuryelGoldButton(
              label: 'Réessayer',
              onTap: controller.retryExtraHourVerification,
            )
          else
            AuryelGoldButton(
              label: 'Ajouter 1 heure',
              enabled: !unavailable && controller.canBuyExtraHour,
              onTap: controller.buyExtraHour,
            ),
        ],
      ),
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

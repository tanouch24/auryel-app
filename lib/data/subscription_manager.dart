import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

import 'purchase.dart';

const String kAuryelAndroidPackage = 'com.auryel.auryel';

/// URL OFFICIELLE de la gestion des abonnements Google Play (résiliation /
/// modification), avec le `package` de l'app et le `sku` du produit quand
/// connu. Aucune URL inventée — schéma documenté par Google.
Uri playSubscriptionsUri({String? productId}) {
  final sku = (productId == null || productId.isEmpty)
      ? kPremiumMonthlyProductId
      : productId;
  return Uri.https('play.google.com', '/store/account/subscriptions', {
    'package': kAuryelAndroidPackage,
    'sku': sku,
  });
}

/// URL OFFICIELLE de la gestion des abonnements App Store.
Uri appleSubscriptionsUri() =>
    Uri.parse('https://apps.apple.com/account/subscriptions');

/// Sortie vers la GESTION d'abonnement du store (résiliation / modification).
///
/// L'app ne résilie JAMAIS elle-même : elle ouvre la page officielle du store.
/// Abstraction pour rester testable (pas de canal plateforme en test).
abstract class SubscriptionManager {
  /// Ouvre la gestion d'abonnement du store. Renvoie `true` si le lien a pu
  /// être ouvert. Ne lève jamais.
  Future<bool> openManagement({String? productId});
}

/// Implémentation réelle via `url_launcher`.
class StoreSubscriptionManager implements SubscriptionManager {
  const StoreSubscriptionManager();

  Uri _uri({String? productId}) {
    try {
      if (Platform.isIOS) return appleSubscriptionsUri();
    } catch (_) {
      /* Platform indisponible -> Android (cible V1) */
    }
    return playSubscriptionsUri(productId: productId);
  }

  @override
  Future<bool> openManagement({String? productId}) async {
    try {
      return await launchUrl(
        _uri(productId: productId),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Implémentation inerte (tests, plateformes non ciblées) : ne fait rien,
/// renvoie `false` — l'appelant affiche alors un repli propre, jamais un faux
/// « abonnement résilié ».
class NoopSubscriptionManager implements SubscriptionManager {
  const NoopSubscriptionManager();

  @override
  Future<bool> openManagement({String? productId}) async => false;
}

/// Instance par défaut : réelle en mobile, inerte ailleurs (bureau/CI).
SubscriptionManager get defaultSubscriptionManager {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      return const StoreSubscriptionManager();
    }
  } catch (_) {
    /* Platform indisponible */
  }
  return const NoopSubscriptionManager();
}

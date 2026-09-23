import 'dart:io' show Platform;

/// Liens juridiques & confidentialité affichés dans « Mon compte ».
///
/// ⚠️ AUCUNE URL FICTIVE. Tant que les pages définitives (3E Technology Ltd)
/// ne sont pas en ligne, les constantes ci-dessous valent `null` et l'UI
/// affiche l'entrée en état « bientôt disponible » — jamais un lien qui
/// ouvrirait une mauvaise page.
///
/// DÉPENDANCE : quand les URLs seront fournies (politique de confidentialité
/// obligatoire pour la soumission Stores), il suffira de les renseigner ici.
/// L'ouverture réelle d'un lien externe nécessitera alors `url_launcher`
/// (pas encore une dépendance — hors périmètre de ce lot).
class LegalLinks {
  const LegalLinks._();

  /// Politique de confidentialité / RGPD, publiée sur le site Auryel.
  static const String privacyPolicyUrl =
      'https://auryelvoyance.com/confidentialite';

  /// Conditions générales d'utilisation. `null` = pas encore publiées.
  static const String? termsUrl = null;

  /// Mentions légales (3E Technology Ltd, n° 17179077). `null` = pas publiées.
  static const String? legalNoticeUrl = null;

  /// Gestion de l'abonnement : pages OFFICIELLES et STABLES des stores (ce ne
  /// sont pas des URLs inventées). Utilisées seulement quand un lanceur d'URL
  /// sera disponible ; d'ici là l'entrée route vers l'écran Premium interne.
  static String get manageSubscriptionUrl {
    try {
      if (Platform.isIOS) {
        return 'https://apps.apple.com/account/subscriptions';
      }
    } catch (_) {
      /* Platform indisponible (tests) -> valeur Android par défaut */
    }
    return 'https://play.google.com/store/account/subscriptions';
  }
}

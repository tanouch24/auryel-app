import 'dart:io' show Platform;

/// Liens juridiques & confidentialité affichés dans « Mon compte ».
///
/// Les URLs ci-dessous sont les pages publiques Auryel vérifiées ou fournies
/// par l'éditeur. Elles ne remplacent pas les documents affichés dans l'app.
///
class LegalLinks {
  const LegalLinks._();

  /// Politique de confidentialité / RGPD, publiée sur le site Auryel.
  static const String privacyPolicyUrl =
      'https://auryelvoyance.com/confidentialite';

  /// Conditions générales d'utilisation publiques.
  static const String termsUrl = 'https://auryelvoyance.com/cgu';

  /// Demande publique de suppression de compte fournie par l'éditeur.
  static const String accountDeletionUrl =
      'https://auryelvoyance.com/suppression-compte';

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

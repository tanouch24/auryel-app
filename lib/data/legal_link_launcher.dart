import 'package:url_launcher/url_launcher.dart';

/// Ouverture des pages juridiques externes (politique de confidentialité, CGU,
/// mentions légales) quand leur URL sera renseignée dans `LegalLinks`.
///
/// Aujourd'hui toutes ces URLs valent `null` -> l'UI n'appelle jamais ce
/// launcher (elle affiche « Bientôt disponible »). L'abstraction est prête pour
/// le jour où les URLs 3E Technology Ltd seront en ligne : il suffira de les
/// renseigner. **Aucune URL n'est inventée ici.**
abstract class LegalLinkLauncher {
  /// Ouvre [url] (HTTPS uniquement) dans le navigateur externe. Renvoie `true`
  /// si le lien a pu être ouvert. Ne lève jamais.
  Future<bool> open(String url);
}

/// Implémentation réelle via `url_launcher` (déjà une dépendance depuis le lot
/// Billing — aucune nouvelle dépendance).
class UrlLauncherLegalLinkLauncher implements LegalLinkLauncher {
  const UrlLauncherLegalLinkLauncher();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url.trim());
    // HTTPS uniquement — jamais de schéma exotique.
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Implémentation inerte (tests) : renvoie `false`, aucun canal plateforme.
class NoopLegalLinkLauncher implements LegalLinkLauncher {
  const NoopLegalLinkLauncher();

  @override
  Future<bool> open(String url) async => false;
}

const LegalLinkLauncher defaultLegalLinkLauncher =
    UrlLauncherLegalLinkLauncher();

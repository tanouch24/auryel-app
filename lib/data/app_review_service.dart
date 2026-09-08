import 'package:in_app_review/in_app_review.dart';

/// Résultat d'une demande de notation, pour un feedback NEUTRE côté UI
/// (jamais « merci pour vos 5 étoiles »).
enum AppReviewOutcome {
  /// La boîte native a été demandée (elle peut ou non s'afficher — c'est
  /// normal, `requestReview()` ne le garantit pas).
  requested,

  /// La boîte native n'est pas disponible : on a ouvert la fiche du store.
  openedStore,

  /// Rien n'a pu être fait (plugin absent / erreur) — l'app ne plante pas.
  unavailable,
}

/// Abstraction TESTABLE de la notation in-app. Le bouton « Noter l'appli » est
/// VOLONTAIREMENT déclenché par l'utilisateur : aucune pop-up automatique dans
/// ce lot. Aucun review gating (pas de « aimez-vous Auryel ? » préalable),
/// aucune récompense, aucun wording « 5 étoiles ».
abstract class AppReviewService {
  Future<AppReviewOutcome> rate();
}

/// Implémentation réelle sur `in_app_review`.
///
/// Android : `openStoreListing()` n'a besoin d'aucun identifiant (utilise le
/// package name). iOS : l'App Store ID n'étant pas encore connu, le repli
/// `openStoreListing` iOS reste incomplet — à compléter dans un lot ultérieur
/// (`appStoreId`). Le chemin nominal reste `requestReview()`.
class InAppReviewService implements AppReviewService {
  InAppReviewService({InAppReview? plugin, this.appStoreId})
      : _plugin = plugin ?? InAppReview.instance;

  final InAppReview _plugin;

  /// À renseigner quand l'app sera publiée sur l'App Store.
  final String? appStoreId;

  @override
  Future<AppReviewOutcome> rate() async {
    try {
      if (await _plugin.isAvailable()) {
        await _plugin.requestReview();
        return AppReviewOutcome.requested;
      }
    } catch (_) {
      // on tente quand même le repli fiche store ci-dessous.
    }
    try {
      await _plugin.openStoreListing(appStoreId: appStoreId);
      return AppReviewOutcome.openedStore;
    } catch (_) {
      return AppReviewOutcome.unavailable;
    }
  }
}

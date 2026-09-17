import '../widgets/main_nav_scope.dart';
import 'notification_payload.dart';

/// Destination produit d'une notification : un onglet de [MainNavShell].
/// JAMAIS un nouvel onglet, JAMAIS la Boutique.
class NotificationRoute {
  const NotificationRoute({required this.tabIndex, this.requiresAuth = false});

  /// Index d'onglet cible (`kTab*` de `main_nav_scope.dart`).
  final int tabIndex;

  /// `true` si la destination n'a de sens que connecté (ex. Consultation).
  /// Utilisateur non connecté -> la destination est différée puis rejouée
  /// après authentification (cf. `MainNavShell`), jamais forcée.
  final bool requiresAuth;

  @override
  bool operator ==(Object other) =>
      other is NotificationRoute &&
      other.tabIndex == tabIndex &&
      other.requiresAuth == requiresAuth;

  @override
  int get hashCode => Object.hash(tabIndex, requiresAuth);

  @override
  String toString() =>
      'NotificationRoute(tab: $tabIndex, requiresAuth: $requiresAuth)';
}

/// Traduit un [NotificationType] en onglet. Table figée V1 :
///
///   daily_thought       -> Accueil        (0)
///   daily_meditation    -> Bien-être      (1, le lecteur reste une route interne)
///   weekly_sleep        -> Bien-être      (1)
///   personal_guidance   -> Consultation   (2, requiresAuth)
///   wellbeing_daily     -> Bien-être      (1)
///   ebook_monthly       -> Bien-être      (1)
///   inconnu             -> null           (aucune navigation)
class NotificationRouter {
  const NotificationRouter();

  NotificationRoute? routeFor(NotificationType type) {
    switch (type) {
      case NotificationType.dailyThought:
        return const NotificationRoute(tabIndex: kTabHome);
      case NotificationType.dailyMeditation:
      case NotificationType.weeklySleep:
      case NotificationType.wellbeingDaily:
      case NotificationType.wellbeingSession:
        return const NotificationRoute(tabIndex: kTabBienEtre);
      case NotificationType.personalGuidance:
        return const NotificationRoute(
          tabIndex: kTabConsultation,
          requiresAuth: true,
        );
      case NotificationType.ebookMonthly:
        return const NotificationRoute(tabIndex: kTabBienEtre);
      case NotificationType.unknown:
        return null;
    }
  }

  NotificationRoute? routeForPayload(NotificationPayload payload) =>
      routeFor(payload.type);
}

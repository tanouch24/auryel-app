import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Handler FCM exécuté dans un ISOLATE SÉPARÉ quand un message data arrive
/// alors que l'app est en arrière-plan ou terminée.
///
/// Contraintes Firebase/Flutter respectées :
///  - fonction TOP-LEVEL (pas une méthode d'instance) ;
///  - `@pragma('vm:entry-point')` pour survivre au tree-shaking en release ;
///  - AUCUNE navigation, AUCUN `BuildContext`, AUCUN accès à l'UI (isolate
///    distinct) ;
///  - AUCUNE logique métier : le routing se fait quand l'app revient au
///    premier plan via `onMessageOpenedApp` / `getInitialMessage`
///    (cf. [FcmNotificationService]).
///
/// Ici on se contente d'initialiser Firebase dans l'isolate (obligatoire pour
/// que le SDK fonctionne) ; si la config est absente, on échoue en silence —
/// aucun impact sur l'app.
@pragma('vm:entry-point')
Future<void> auryelFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Config Firebase absente / déjà initialisée : rien à faire ici.
  }
  // Volontairement vide : le contenu du message sera traité au retour au
  // premier plan. On NE logge PAS le message (données potentiellement perso).
}

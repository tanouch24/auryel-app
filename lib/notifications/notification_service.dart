import 'dart:async';

import 'notification_payload.dart';

/// État de l'autorisation de notifications, indépendant de la plateforme.
enum NotificationPermissionStatus {
  /// Jamais demandée (Android < 13 : implicitement accordée ; iOS : à demander).
  notDetermined,

  /// Accordée.
  authorized,

  /// Refusée par l'utilisateur -> il faut passer par les réglages système.
  denied,

  /// iOS : autorisation « discrète » (notifications silencieuses).
  provisional,

  /// Aucune infrastructure de notifications sur ce build / cet appareil
  /// (Firebase non configuré, plateforme non supportée…).
  unavailable,
}

/// Façade unique des notifications Auryel. AUCUN écran ne touche
/// `FirebaseMessaging` directement : tout passe par cette abstraction, ce qui
/// la rend testable et permet de démarrer l'app même sans Firebase.
///
/// Contrat :
///  - [initialize] : idempotent, ne lève jamais, n'empêche jamais le démarrage.
///  - [isAvailable] : `false` si aucune infra push (cf. [DisabledNotificationService]).
///  - [permissionStatus] / [requestPermission] : la demande n'est JAMAIS
///    automatique — elle est déclenchée explicitement (écran Notifications).
///  - [currentToken] / [onTokenRefresh] : jeton d'enregistrement push. Le jeton
///    n'est JAMAIS loggé et n'empêche jamais le démarrage s'il est `null`.
///  - [onMessageOpened] : l'utilisateur a ouvert l'app EN TAPANT une notif
///    (app en arrière-plan).
///  - [onForegroundMessage] : message reçu app au premier plan.
///  - [takeInitialPayload] : notification ayant LANCÉ l'app depuis un état
///    terminé — consommable UNE seule fois (le routing est fait quand la
///    navigation est prête).
abstract class AuryelNotificationService {
  Future<void> initialize();

  bool get isAvailable;

  Future<NotificationPermissionStatus> permissionStatus();

  Future<NotificationPermissionStatus> requestPermission();

  Future<String?> currentToken();

  Stream<String> get onTokenRefresh;

  Stream<NotificationPayload> get onMessageOpened;

  Stream<NotificationPayload> get onForegroundMessage;

  /// Renvoie la notification qui a lancé l'app (état terminé) puis l'oublie
  /// (consommation unique). `null` si l'app n'a pas été lancée par une notif.
  NotificationPayload? takeInitialPayload();

  void dispose();
}

/// Implémentation ACTIVE-INERTE : aucune infra push (Firebase non configuré).
/// L'app fonctionne normalement ; l'écran Notifications affiche « indisponible ».
/// Remplacée à terme par une implémentation `firebase_messaging` derrière la
/// MÊME interface, sans toucher aux écrans.
class DisabledNotificationService implements AuryelNotificationService {
  final _tokenRefresh = StreamController<String>.broadcast();
  final _opened = StreamController<NotificationPayload>.broadcast();
  final _foreground = StreamController<NotificationPayload>.broadcast();

  @override
  Future<void> initialize() async {
    /* rien à initialiser — no-op volontaire */
  }

  @override
  bool get isAvailable => false;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async =>
      NotificationPermissionStatus.unavailable;

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.unavailable;

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  @override
  Stream<NotificationPayload> get onMessageOpened => _opened.stream;

  @override
  Stream<NotificationPayload> get onForegroundMessage => _foreground.stream;

  @override
  NotificationPayload? takeInitialPayload() => null;

  @override
  void dispose() {
    _tokenRefresh.close();
    _opened.close();
    _foreground.close();
  }
}

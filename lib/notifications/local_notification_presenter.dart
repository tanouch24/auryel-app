import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_payload.dart';

/// Affiche une notification LOCALE quand un message FCM arrive alors que l'app
/// est au premier plan (Android n'affiche rien de lui-même dans ce cas).
///
/// Crée aussi le canal Android `auryel_default` avec une visibilité PRIVÉE sur
/// l'écran verrouillé : le titre/corps affichés restent ceux, GÉNÉRIQUES,
/// envoyés par le serveur — jamais de contenu de consultation.
///
/// Le tap sur cette notif locale est routé via [onSelect] (même logique que
/// `onMessageOpenedApp`).
class LocalNotificationPresenter {
  LocalNotificationPresenter({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channel = AndroidNotificationChannel(
    'auryel_default',
    'Auryel',
    description: 'Rappels doux et messages de ton conseiller.',
    importance: Importance.defaultImportance,
  );

  bool _ready = false;
  void Function(NotificationPayload payload)? onSelect;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      const initAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: initAndroid),
        onDidReceiveNotificationResponse: _onResponse,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _ready = true;
    } catch (e) {
      // Plugin non disponible (tests / plateforme) -> présentateur inerte.
      if (kDebugMode) debugPrint('LocalNotificationPresenter init KO: $e');
      _ready = false;
    }
  }

  /// Affiche le payload s'il est routable (type connu). Rien de sensible :
  /// on n'affiche QUE `title` / `body` fournis par le serveur.
  Future<void> show(NotificationPayload payload) async {
    if (!_ready || !payload.isActionable) return;
    final title = payload.title ?? 'Auryel';
    final body = payload.body ?? '';
    try {
      await _plugin.show(
        payload.type.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            visibility: NotificationVisibility.private,
          ),
        ),
        payload: payload.type.wire,
      );
    } catch (_) {
      /* affichage best-effort */
    }
  }

  void _onResponse(NotificationResponse response) {
    final cb = onSelect;
    if (cb == null) return;
    final type = NotificationType.fromWire(response.payload);
    cb(NotificationPayload(type: type));
  }
}

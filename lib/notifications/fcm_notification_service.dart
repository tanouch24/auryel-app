import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_background_handler.dart';
import 'notification_payload.dart';
import 'notification_service.dart';

/// Implémentation RÉELLE de [AuryelNotificationService] sur Firebase Cloud
/// Messaging (Android V1). AUCUN écran ne touche `FirebaseMessaging`
/// directement : tout passe par cette classe.
///
/// ROBUSTESSE — l'app doit démarrer et fonctionner même si Firebase n'est PAS
/// configuré (pas de `google-services.json`, pas de plugin Google Services, ou
/// environnement de test) :
///  - [initialize] enveloppe TOUT dans des `try/catch` ; en cas d'échec (config
///    absente, `MissingPluginException` en test), [isAvailable] reste `false`
///    et l'app continue sans push.
///  - Aucun `FirebaseOptions` de production n'est fabriqué ici :
///    `Firebase.initializeApp()` lit la config native (google-services.json).
///
/// Le jeton n'est JAMAIS loggé. La permission n'est JAMAIS demandée
/// automatiquement (uniquement via le CTA de l'écran Notifications).
class FcmNotificationService implements AuryelNotificationService {
  FcmNotificationService({FirebaseMessaging? messaging})
    : _injectedMessaging = messaging;

  final FirebaseMessaging? _injectedMessaging;

  FirebaseMessaging? _fm;
  bool _available = false;
  bool _initialized = false;

  final _tokenRefresh = StreamController<String>.broadcast();
  final _opened = StreamController<NotificationPayload>.broadcast();
  final _foreground = StreamController<NotificationPayload>.broadcast();

  final List<StreamSubscription<dynamic>> _subs = [];

  NotificationPayload? _initialPayload;
  bool _initialConsumed = false;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Config Firebase absente / plateforme non supportée / test :
      // on reste indisponible, l'app continue.
      _available = false;
      return;
    }

    try {
      _fm = _injectedMessaging ?? FirebaseMessaging.instance;

      // Handler top-level (isolate distinct) — enregistré une seule fois.
      FirebaseMessaging.onBackgroundMessage(
        auryelFirebaseMessagingBackgroundHandler,
      );

      // App au premier plan : on EXPOSE le message, on n'affiche AUCUN popup
      // intrusif ici (cf. rapport, section Foreground).
      _subs.add(
        FirebaseMessaging.onMessage.listen((m) {
          if (!_foreground.isClosed) {
            _foreground.add(
              NotificationPayload.fromData(
                notificationDataFromRemoteMessage(m),
              ),
            );
          }
        }),
      );

      // App en arrière-plan, l'utilisateur TAPE la notif.
      _subs.add(
        FirebaseMessaging.onMessageOpenedApp.listen((m) {
          if (!_opened.isClosed) {
            _opened.add(
              NotificationPayload.fromData(
                notificationDataFromRemoteMessage(m),
              ),
            );
          }
        }),
      );

      // Rotation du jeton — jamais loggé.
      _subs.add(
        _fm!.onTokenRefresh.listen((t) {
          if (t.isNotEmpty && !_tokenRefresh.isClosed) _tokenRefresh.add(t);
        }),
      );

      // Notification ayant LANCÉ l'app depuis un état terminé.
      final initial = await _fm!.getInitialMessage();
      if (initial != null) {
        _initialPayload = NotificationPayload.fromData(
          notificationDataFromRemoteMessage(initial),
        );
      }

      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  /// Data values are authoritative when present; notification title/body are
  /// the safe fallback used by FCM notification messages. Android exposes the
  /// latter outside `RemoteMessage.data`, especially on the foreground path.
  @visibleForTesting
  static Map<String, Object?> notificationDataFromRemoteMessage(
    RemoteMessage m,
  ) {
    final data = m.data.map((k, v) => MapEntry(k, v as Object?));
    final notification = m.notification;
    if ((data['title'] == null || data['title'].toString().trim().isEmpty) &&
        notification?.title != null) {
      data['title'] = notification!.title;
    }
    if ((data['body'] == null || data['body'].toString().trim().isEmpty) &&
        notification?.body != null) {
      data['body'] = notification!.body;
    }
    return data;
  }

  @override
  Future<NotificationPermissionStatus> permissionStatus() async {
    final fm = _fm;
    if (!_available || fm == null) {
      return NotificationPermissionStatus.unavailable;
    }
    try {
      final s = await fm.getNotificationSettings();
      return _mapAuth(s.authorizationStatus);
    } catch (_) {
      return NotificationPermissionStatus.unavailable;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    final fm = _fm;
    if (!_available || fm == null) {
      return NotificationPermissionStatus.unavailable;
    }
    try {
      final s = await fm.requestPermission();
      return _mapAuth(s.authorizationStatus);
    } catch (_) {
      return NotificationPermissionStatus.unavailable;
    }
  }

  static NotificationPermissionStatus _mapAuth(AuthorizationStatus s) {
    switch (s) {
      case AuthorizationStatus.authorized:
        return NotificationPermissionStatus.authorized;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
        return NotificationPermissionStatus.denied;
      case AuthorizationStatus.provisional:
        return NotificationPermissionStatus.provisional;
      case AuthorizationStatus.notDetermined:
        return NotificationPermissionStatus.notDetermined;
    }
  }

  @override
  Future<String?> currentToken() async {
    final fm = _fm;
    if (!_available || fm == null) return null;
    try {
      final t = await fm.getToken();
      return (t != null && t.isNotEmpty) ? t : null; // jamais loggé
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  @override
  Stream<NotificationPayload> get onMessageOpened => _opened.stream;

  @override
  Stream<NotificationPayload> get onForegroundMessage => _foreground.stream;

  @override
  NotificationPayload? takeInitialPayload() {
    if (_initialConsumed) return null;
    _initialConsumed = true;
    final p = _initialPayload;
    _initialPayload = null;
    return p;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _tokenRefresh.close();
    _opened.close();
    _foreground.close();
  }
}

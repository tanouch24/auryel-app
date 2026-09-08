import 'dart:async';

import 'package:flutter/widgets.dart';

import 'notification_router.dart';
import 'notification_service.dart';
import 'push_token_registrar.dart';

/// Colle les briques notifications ENSEMBLE, une seule fois, au niveau app :
///  - initialise le [AuryelNotificationService] (no-op si Firebase absent) ;
///  - relaie le jeton courant + chaque refresh vers le [PushTokenRegistrar]
///    (aujourd'hui [NoopPushTokenRegistrar] : aucun endpoint) ;
///  - expose `service` + `router` aux écrans via [NotificationScope].
///
/// Le routing lui-même (payload -> onglet) est fait par `MainNavShell` quand la
/// navigation est prête : cf. [NotificationRouter]. Volontairement simple —
/// aucune machine à états.
class NotificationCoordinator {
  // ignore_for_file: prefer_initializing_formals
  NotificationCoordinator({
    required this.service,
    PushTokenRegistrar registrar = const NoopPushTokenRegistrar(),
    this.router = const NotificationRouter(),
  }) : _registrar = registrar;

  final AuryelNotificationService service;
  final NotificationRouter router;
  final PushTokenRegistrar _registrar;

  StreamSubscription<String>? _tokenSub;
  bool _started = false;

  /// À appeler une fois au démarrage (après `runApp` : ne bloque rien). Toutes
  /// les erreurs sont absorbées — jamais d'échec de démarrage à cause du push.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await service.initialize();
    } catch (_) {
      /* démarrage jamais bloqué par le push */
    }

    _tokenSub = service.onTokenRefresh.listen((token) {
      if (token.isNotEmpty) {
        // jamais loggé
        unawaited(_safe(() => _registrar.register(token)));
      }
    });

    try {
      final token = await service.currentToken();
      if (token != null && token.isNotEmpty) {
        unawaited(_safe(() => _registrar.register(token)));
      }
    } catch (_) {
      /* token indisponible -> on continue */
    }
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {
      /* enregistrement best effort */
    }
  }

  void dispose() {
    _tokenSub?.cancel();
    _tokenSub = null;
    service.dispose();
  }
}

/// Fournit le [AuryelNotificationService] + [NotificationRouter] à l'arbre.
/// Absent des tests hérités -> `maybeOf` renvoie `null`, aucun traitement de
/// notification, aucun crash.
class NotificationScope extends InheritedWidget {
  const NotificationScope({
    super.key,
    required this.service,
    this.router = const NotificationRouter(),
    required super.child,
  });

  final AuryelNotificationService service;
  final NotificationRouter router;

  static NotificationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>();

  @override
  bool updateShouldNotify(NotificationScope oldWidget) =>
      oldWidget.service != service || oldWidget.router != router;
}

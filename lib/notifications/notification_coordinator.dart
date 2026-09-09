import 'dart:async';

import 'package:flutter/widgets.dart';

import 'notification_payload.dart';
import 'notification_router.dart';
import 'notification_service.dart';
import 'push_token_registrar.dart';

/// Colle les briques notifications ENSEMBLE, une seule fois, au niveau app :
///  - initialise le [AuryelNotificationService] (no-op si Firebase absent) ;
///  - BUFFERISE le jeton FCM courant + chaque refresh, et ne l'enregistre
///    auprès du backend ([PushTokenRegistrar]) QUE lorsqu'une session est
///    valide ([isSignedIn]) — au démarrage le Bearer n'existe pas encore ;
///  - [onSignedIn] : appelé quand l'auth devient valide -> flush du jeton ;
///  - [unregisterCurrent] : appelé AVANT un logout / une suppression de compte
///    (Bearer encore vivant) -> désenregistre le jeton de CET appareil ;
///  - expose `service` + `router` aux écrans via [NotificationScope] ;
///  - relaie les messages reçus au premier plan à [onForegroundMessage] pour
///    qu'un présentateur (flutter_local_notifications) les affiche.
///
/// Le routing payload -> onglet reste fait par `MainNavShell`. Volontairement
/// simple : aucune machine à états, toutes les erreurs absorbées.
class NotificationCoordinator {
  // ignore_for_file: prefer_initializing_formals
  NotificationCoordinator({
    required this.service,
    PushTokenRegistrar registrar = const NoopPushTokenRegistrar(),
    this.router = const NotificationRouter(),
    bool Function()? isSignedIn,
  })  : _registrar = registrar,
        _isSignedIn = isSignedIn ?? (() => false);

  final AuryelNotificationService service;
  final NotificationRouter router;
  final PushTokenRegistrar _registrar;
  final bool Function() _isSignedIn;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<NotificationPayload>? _foregroundSub;
  bool _started = false;

  /// Dernier jeton FCM connu (bufferisé). Enregistré dès qu'une session est
  /// valide ; réutilisé par [unregisterCurrent].
  String? _lastToken;

  /// Flux des messages reçus app au premier plan (à afficher via une notif
  /// locale — Android n'affiche rien tout seul dans ce cas).
  final _foreground = StreamController<NotificationPayload>.broadcast();
  Stream<NotificationPayload> get onForegroundMessage => _foreground.stream;

  /// Tap sur une notif LOCALE affichée au premier plan -> à router comme un
  /// `onMessageOpenedApp` (changement d'onglet).
  final _tap = StreamController<NotificationPayload>.broadcast();
  Stream<NotificationPayload> get onNotificationTap => _tap.stream;
  void handleForegroundTap(NotificationPayload payload) {
    if (!_tap.isClosed) _tap.add(payload);
  }

  /// À appeler une fois au démarrage (après `runApp`). Ne bloque jamais.
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
        _lastToken = token; // jamais loggé
        if (_isSignedIn()) {
          unawaited(_safe(() => _registrar.register(token)));
        }
      }
    });

    _foregroundSub = service.onForegroundMessage.listen((p) {
      if (!_foreground.isClosed) _foreground.add(p);
    });

    try {
      final token = await service.currentToken();
      if (token != null && token.isNotEmpty) {
        _lastToken = token;
        if (_isSignedIn()) {
          unawaited(_safe(() => _registrar.register(token)));
        }
      }
    } catch (_) {
      /* token indisponible -> on continue */
    }
  }

  /// L'auth vient de devenir valide (login réussi / restauration) : on
  /// enregistre le jeton bufferisé. Idempotent côté serveur.
  Future<void> onSignedIn() async {
    final token = _lastToken;
    if (token == null || token.isEmpty) {
      // pas encore de jeton connu : on tente de le récupérer maintenant.
      try {
        final t = await service.currentToken();
        if (t != null && t.isNotEmpty) {
          _lastToken = t;
          await _safe(() => _registrar.register(t));
        }
      } catch (_) {}
      return;
    }
    await _safe(() => _registrar.register(token));
  }

  /// AVANT un logout / une suppression de compte : désenregistre le jeton de
  /// cet appareil (best effort, Bearer encore vivant).
  Future<void> unregisterCurrent() async {
    final token = _lastToken;
    if (token == null || token.isEmpty) return;
    await _safe(() => _registrar.unregister(token));
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {
      /* best effort */
    }
  }

  void dispose() {
    _tokenSub?.cancel();
    _tokenSub = null;
    _foregroundSub?.cancel();
    _foregroundSub = null;
    _foreground.close();
    _tap.close();
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
    this.coordinator,
    required super.child,
  });

  final AuryelNotificationService service;
  final NotificationRouter router;

  /// Présent quand `main()` fournit le coordinateur : expose `onNotificationTap`
  /// (tap sur une notif locale affichée au premier plan). `null` dans les tests
  /// hérités.
  final NotificationCoordinator? coordinator;

  static NotificationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>();

  @override
  bool updateShouldNotify(NotificationScope oldWidget) =>
      oldWidget.service != service ||
      oldWidget.router != router ||
      oldWidget.coordinator != coordinator;
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/notifications/fcm_background_handler.dart';
import 'package:auryel/notifications/fcm_notification_service.dart';
import 'package:auryel/notifications/notification_coordinator.dart';
import 'package:auryel/notifications/notification_service.dart';
import 'package:auryel/notifications/push_token_registrar.dart';

// ===========================================================================
// LOT FCM / PUSH ANDROID V1 — l'implémentation RÉELLE doit DÉGRADER proprement
// quand Firebase n'est pas configuré (cas des tests : aucun canal plateforme).
// Le routing / la logique pending / les états de l'écran Réglages sont couverts
// par test/notifications_test.dart (fakes).
// ===========================================================================

class _RecordingRegistrar implements PushTokenRegistrar {
  final List<String> registered = [];
  int unregisterCalls = 0;
  @override
  Future<void> register(String token) async => registered.add(token);
  @override
  Future<void> unregister() async => unregisterCalls++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FcmNotificationService — Firebase absent (env de test)', () {
    test('R1 — initialize() ne crash pas, isAvailable == false', () async {
      final s = FcmNotificationService();
      addTearDown(s.dispose);
      await s.initialize();
      await s.initialize(); // idempotent
      expect(s.isAvailable, isFalse);
    });

    test('permission / token / initial payload -> valeurs sûres', () async {
      final s = FcmNotificationService();
      addTearDown(s.dispose);
      await s.initialize();
      expect(
        await s.permissionStatus(),
        NotificationPermissionStatus.unavailable,
      );
      expect(
        await s.requestPermission(),
        NotificationPermissionStatus.unavailable,
      );
      expect(await s.currentToken(), isNull);
      expect(s.takeInitialPayload(), isNull);
    });

    test('les streams sont exposés et ne lèvent pas', () async {
      final s = FcmNotificationService();
      addTearDown(s.dispose);
      await s.initialize();
      // On s'abonne : aucun événement, aucune exception.
      final subs = [
        s.onMessageOpened.listen((_) {}),
        s.onForegroundMessage.listen((_) {}),
        s.onTokenRefresh.listen((_) {}),
      ];
      for (final sub in subs) {
        addTearDown(sub.cancel);
      }
      await Future<void>.delayed(Duration.zero);
      expect(true, isTrue);
    });

    test('permissionStatus/currentToken sans initialize -> sûrs', () async {
      final s = FcmNotificationService();
      addTearDown(s.dispose);
      expect(
        await s.permissionStatus(),
        NotificationPermissionStatus.unavailable,
      );
      expect(await s.currentToken(), isNull);
    });
  });

  group('Background handler', () {
    test('auryelFirebaseMessagingBackgroundHandler ne lève jamais', () async {
      // RemoteMessage vide : le handler tente Firebase.initializeApp() (échoue
      // en test), l'absorbe, et retourne.
      await expectLater(
        auryelFirebaseMessagingBackgroundHandler(const RemoteMessage()),
        completes,
      );
      await expectLater(
        auryelFirebaseMessagingBackgroundHandler(
          const RemoteMessage(data: {'type': 'daily_thought'}),
        ),
        completes,
      );
    });
  });

  group('NotificationCoordinator + FcmNotificationService', () {
    test('start() absorbe tout, aucun token -> registrar jamais appelé, '
        'dispose() OK', () async {
      final reg = _RecordingRegistrar();
      final coord = NotificationCoordinator(
        service: FcmNotificationService(),
        registrar: reg,
      );
      await coord.start();
      await coord.start(); // idempotent
      await Future<void>.delayed(Duration.zero);
      expect(reg.registered, isEmpty); // pas de Firebase -> pas de token
      coord.dispose();
    });
  });
}

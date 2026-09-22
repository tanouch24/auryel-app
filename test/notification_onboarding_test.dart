import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/notifications/notification_payload.dart';
import 'package:auryel/notifications/notification_service.dart';
import 'package:auryel/screens/onboarding/notification_onboarding_screen.dart';

class _FakeService implements AuryelNotificationService {
  _FakeService(this.status);

  NotificationPermissionStatus status;
  int permissionRequests = 0;

  @override
  Future<void> initialize() async {}

  @override
  bool get isAvailable => true;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => status;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    permissionRequests++;
    status = NotificationPermissionStatus.authorized;
    return status;
  }

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<NotificationPayload> get onMessageOpened => const Stream.empty();

  @override
  Stream<NotificationPayload> get onForegroundMessage => const Stream.empty();

  @override
  NotificationPayload? takeInitialPayload() => null;

  @override
  void dispose() {}
}

void main() {
  testWidgets('permission déjà accordée : aucun second appel système', (
    tester,
  ) async {
    final service = _FakeService(NotificationPermissionStatus.authorized);
    await tester.pumpWidget(
      MaterialApp(home: NotificationOnboardingScreen(serviceOverride: service)),
    );

    await tester.tap(find.text('Activer les notifications'));
    await tester.pumpAndSettle();

    expect(service.permissionRequests, 0);
  });

  testWidgets('permission non déterminée : le CTA déclenche la demande', (
    tester,
  ) async {
    final service = _FakeService(NotificationPermissionStatus.notDetermined);
    await tester.pumpWidget(
      MaterialApp(home: NotificationOnboardingScreen(serviceOverride: service)),
    );

    await tester.tap(find.text('Activer les notifications'));
    await tester.pumpAndSettle();

    expect(service.permissionRequests, 1);
  });
}

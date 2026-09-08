import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/notifications/app_settings_opener.dart';
import 'package:auryel/notifications/notification_coordinator.dart';
import 'package:auryel/notifications/notification_payload.dart';
import 'package:auryel/notifications/notification_router.dart';
import 'package:auryel/notifications/notification_service.dart';
import 'package:auryel/notifications/push_token_registrar.dart';
import 'package:auryel/screens/notification_settings_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// LOT FCM / NOTIFICATIONS — architecture pure Dart (Firebase NON configuré).
// ===========================================================================
// ignore_for_file: prefer_initializing_formals

class _FakeNotificationService implements AuryelNotificationService {
  _FakeNotificationService({
    NotificationPayload? initial,
    this.status = NotificationPermissionStatus.notDetermined,
    this.token,
  }) : _initial = initial;

  NotificationPayload? _initial;
  NotificationPermissionStatus status;
  String? token;
  int initializeCalls = 0;
  int requestCalls = 0;

  final _opened = StreamController<NotificationPayload>.broadcast();
  final _foreground = StreamController<NotificationPayload>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();

  void emitOpened(NotificationPayload p) => _opened.add(p);
  void emitTokenRefresh(String t) => _tokenRefresh.add(t);

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  bool get isAvailable => true;

  @override
  Future<NotificationPermissionStatus> permissionStatus() async => status;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    requestCalls++;
    return status;
  }

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  @override
  Stream<NotificationPayload> get onMessageOpened => _opened.stream;

  @override
  Stream<NotificationPayload> get onForegroundMessage => _foreground.stream;

  @override
  NotificationPayload? takeInitialPayload() {
    final p = _initial;
    _initial = null;
    return p;
  }

  @override
  void dispose() {
    _opened.close();
    _foreground.close();
    _tokenRefresh.close();
  }
}

class _RecordingRegistrar implements PushTokenRegistrar {
  final List<String> registered = [];
  int unregisterCalls = 0;

  @override
  Future<void> register(String token) async => registered.add(token);

  @override
  Future<void> unregister() async => unregisterCalls++;
}

class _RecordingOpener implements AppSettingsOpener {
  int opened = 0;
  @override
  Future<void> open() async => opened++;
}

AuryelState _state() => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u-1',
    selectedAdvisor: 'Maïa',
    firstName: 'Nina',
    birthDate: DateTime(1994, 1, 1),
    portraitData: 't',
    portraitFeedback: 'ok',
    onboardingCompleted: true,
  ),
);

/// Un jeton est toujours présent en stockage ; [signedIn] true -> on appelle
/// `restore()` (statut `signedIn`). Sinon le statut reste `unknown` (isSignedIn
/// == false), et un `restore()` ultérieur du test peut le faire basculer.
Future<AuthController> _auth({bool signedIn = false}) async {
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/account') {
        return http.Response(
          jsonEncode({'user_id': 'u-1', 'email': 'nina@example.com'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/api/tirages') {
        return http.Response(
          jsonEncode({'tirages': <dynamic>[], 'next_cursor': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }),
    baseUrl: 'http://test.local',
  );
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('tok'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: ConsultationApi(client),
    tirageApi: TirageApi(client),
  );
  if (signedIn) await auth.restore();
  addTearDown(auth.dispose);
  return auth;
}

Future<int> _pumpShell(
  WidgetTester t,
  _FakeNotificationService fake, {
  bool signedIn = true,
}) async {
  final auth = await _auth(signedIn: signedIn);
  await t.pumpWidget(
    AuthScope(
      controller: auth,
      child: AuryelStateScope(
        state: _state(),
        child: MaterialApp(home: MainNavShell(notificationsOverride: fake)),
      ),
    ),
  );
  await t.pumpAndSettle();
  return t.widget<MainNavScope>(find.byType(MainNavScope)).currentIndex;
}

int _currentIndex(WidgetTester t) =>
    t.widget<MainNavScope>(find.byType(MainNavScope)).currentIndex;

NotificationPayload _payload(String type) =>
    NotificationPayload.fromData({'type': type});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // ROUTER (unitaire)
  // -------------------------------------------------------------------------
  group('NotificationRouter', () {
    const router = NotificationRouter();

    test('1 — daily_thought -> Accueil (0)', () {
      expect(
        router.routeFor(NotificationType.dailyThought)!.tabIndex,
        kTabHome,
      );
    });
    test('2 — daily_meditation -> Méditation (3)', () {
      expect(
        router.routeFor(NotificationType.dailyMeditation)!.tabIndex,
        kTabMeditation,
      );
    });
    test('3 — weekly_sleep -> Méditation (3)', () {
      expect(
        router.routeFor(NotificationType.weeklySleep)!.tabIndex,
        kTabMeditation,
      );
    });
    test('4 — personal_guidance -> Consultation (2), requiresAuth', () {
      final r = router.routeFor(NotificationType.personalGuidance)!;
      expect(r.tabIndex, kTabConsultation);
      expect(r.requiresAuth, isTrue);
    });
    test('5 — weekly_life_lesson -> Accueil (0)', () {
      expect(
        router.routeFor(NotificationType.weeklyLifeLesson)!.tabIndex,
        kTabHome,
      );
    });
    test('6 — type inconnu -> null (aucune navigation)', () {
      expect(router.routeFor(NotificationType.unknown), isNull);
    });
    test('8 — aucune route ne cible un onglet hors 0..4 (jamais Boutique)', () {
      for (final t in NotificationType.values) {
        final r = router.routeFor(t);
        if (r != null) {
          expect(r.tabIndex, inInclusiveRange(0, 4));
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // PAYLOAD (tolérance)
  // -------------------------------------------------------------------------
  group('NotificationPayload', () {
    test('7 — data null / vide -> unknown, aucun crash', () {
      expect(NotificationPayload.fromData(null).type, NotificationType.unknown);
      expect(NotificationPayload.fromData({}).type, NotificationType.unknown);
    });
    test('type inconnu -> unknown ; champs partiels tolérés', () {
      final p = NotificationPayload.fromData({
        'type': 'chelou',
        'title': 'Coucou',
        'extra': 42,
      });
      expect(p.type, NotificationType.unknown);
      expect(p.title, 'Coucou');
      expect(p.isActionable, isFalse);
    });
    test('champs connus parsés', () {
      final p = NotificationPayload.fromData({
        'type': 'personal_guidance',
        'consultation_id': 'c-9',
        'advisor': 'maia',
      });
      expect(p.type, NotificationType.personalGuidance);
      expect(p.consultationId, 'c-9');
      expect(p.advisor, 'maia');
    });
  });

  // -------------------------------------------------------------------------
  // DisabledNotificationService (Firebase absent)
  // -------------------------------------------------------------------------
  group('DisabledNotificationService', () {
    test('12/13/15 — indisponible, token null, streams vides, no-op', () async {
      final s = DisabledNotificationService();
      addTearDown(s.dispose);
      await s.initialize(); // ne lève pas
      expect(s.isAvailable, isFalse);
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
  });

  // -------------------------------------------------------------------------
  // COORDINATOR — token / refresh vers le registrar
  // -------------------------------------------------------------------------
  group('NotificationCoordinator', () {
    test('11/12 — start() absorbe tout, aucun crash si indisponible', () async {
      final coord = NotificationCoordinator(
        service: DisabledNotificationService(),
        registrar: _RecordingRegistrar(),
      );
      await coord.start();
      await coord.start(); // idempotent
      coord.dispose();
    });

    test('13 — token null -> registrar jamais appelé', () async {
      final reg = _RecordingRegistrar();
      final coord = NotificationCoordinator(
        service: _FakeNotificationService(token: null),
        registrar: reg,
      );
      await coord.start();
      await Future<void>.delayed(Duration.zero);
      expect(reg.registered, isEmpty);
      coord.dispose();
    });

    test('14 — token présent + refresh -> registrar.register appelé', () async {
      final fake = _FakeNotificationService(token: 'tok-abc');
      final reg = _RecordingRegistrar();
      final coord = NotificationCoordinator(service: fake, registrar: reg);
      await coord.start();
      await Future<void>.delayed(Duration.zero);
      expect(reg.registered, contains('tok-abc'));

      fake.emitTokenRefresh('tok-def');
      await Future<void>.delayed(Duration.zero);
      expect(reg.registered, contains('tok-def'));
      coord.dispose();
    });

    test('NoopPushTokenRegistrar — n\'échoue jamais', () async {
      const reg = NoopPushTokenRegistrar();
      await reg.register('x');
      await reg.unregister();
    });
  });

  // -------------------------------------------------------------------------
  // ROUTING dans MainNavShell
  // -------------------------------------------------------------------------
  group('MainNavShell routing', () {
    testWidgets('1 — initial daily_thought -> onglet 0', (t) async {
      final fake = _FakeNotificationService(initial: _payload('daily_thought'));
      final idx = await _pumpShell(t, fake);
      expect(idx, kTabHome);
    });

    testWidgets('2 — initial daily_meditation -> onglet 3', (t) async {
      final fake = _FakeNotificationService(
        initial: _payload('daily_meditation'),
      );
      expect(await _pumpShell(t, fake), kTabMeditation);
    });

    testWidgets('3 — onMessageOpened weekly_sleep -> onglet 3', (t) async {
      final fake = _FakeNotificationService();
      await _pumpShell(t, fake);
      expect(_currentIndex(t), kTabHome);
      fake.emitOpened(_payload('weekly_sleep'));
      await t.pumpAndSettle();
      expect(_currentIndex(t), kTabMeditation);
    });

    testWidgets('4/10 — personal_guidance (connecté) -> onglet 2', (t) async {
      final fake = _FakeNotificationService(
        initial: _payload('personal_guidance'),
      );
      expect(await _pumpShell(t, fake, signedIn: true), kTabConsultation);
    });

    testWidgets('5 — weekly_life_lesson -> onglet 0', (t) async {
      final fake = _FakeNotificationService(
        initial: _payload('weekly_life_lesson'),
      );
      expect(await _pumpShell(t, fake), kTabHome);
    });

    testWidgets('6/7 — type inconnu / payload vide -> onglet 0, aucun crash', (
      t,
    ) async {
      final fake = _FakeNotificationService(
        initial: _payload('n-importe-quoi'),
      );
      expect(await _pumpShell(t, fake), kTabHome);
      fake.emitOpened(NotificationPayload.fromData(null));
      await t.pumpAndSettle();
      expect(_currentIndex(t), kTabHome);
      expect(t.takeException(), isNull);
    });

    testWidgets('9 — non connecté + personal_guidance -> NON routé (différé), '
        'puis rejoué après connexion', (t) async {
      final fake = _FakeNotificationService(
        initial: _payload('personal_guidance'),
      );
      final auth = await _auth(signedIn: false);
      await t.pumpWidget(
        AuthScope(
          controller: auth,
          child: AuryelStateScope(
            state: _state(),
            child: MaterialApp(home: MainNavShell(notificationsOverride: fake)),
          ),
        ),
      );
      await t.pumpAndSettle();
      // Pas poussé de force dans Consultation.
      expect(_currentIndex(t), kTabHome);

      // La session devient valide -> la destination différée est rejouée.
      await auth.restore();
      await t.pumpAndSettle();
      expect(_currentIndex(t), kTabConsultation);
    });

    testWidgets(
      '8 — aucune notification ne cible la Boutique (5 onglets only)',
      (t) async {
        final fake = _FakeNotificationService();
        await _pumpShell(t, fake);
        for (final type in [
          'daily_thought',
          'daily_meditation',
          'weekly_sleep',
          'personal_guidance',
          'weekly_life_lesson',
          'inconnu',
        ]) {
          fake.emitOpened(_payload(type));
          await t.pumpAndSettle();
          expect(_currentIndex(t), inInclusiveRange(0, 4));
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // NotificationSettingsScreen
  // -------------------------------------------------------------------------
  group('NotificationSettingsScreen', () {
    Future<void> pump(
      WidgetTester t,
      _FakeNotificationService fake, {
      AppSettingsOpener? opener,
    }) async {
      await t.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            serviceOverride: fake,
            settingsOpener: opener ?? const NoopAppSettingsOpener(),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('16 — unavailable : message, aucun CTA', (t) async {
      final fake = _FakeNotificationService(
        status: NotificationPermissionStatus.unavailable,
      );
      await pump(t, fake);
      expect(find.text('Notifications Auryel'), findsOneWidget);
      expect(
        find.textContaining('ne sont pas encore disponibles'),
        findsOneWidget,
      );
      expect(find.text('Activer les notifications'), findsNothing);
      expect(find.text('Ouvrir les réglages'), findsNothing);
    });

    testWidgets('17 — notDetermined : CTA « Activer les notifications » '
        'appelle requestPermission', (t) async {
      final fake = _FakeNotificationService(
        status: NotificationPermissionStatus.notDetermined,
      );
      await pump(t, fake);
      expect(find.text('Activer les notifications'), findsOneWidget);
      await t.tap(find.text('Activer les notifications'));
      await t.pumpAndSettle();
      expect(fake.requestCalls, 1);
    });

    testWidgets('17b — authorized : « activées », aucun CTA', (t) async {
      final fake = _FakeNotificationService(
        status: NotificationPermissionStatus.authorized,
      );
      await pump(t, fake);
      expect(
        find.text('Les notifications Auryel sont activées.'),
        findsOneWidget,
      );
      expect(find.text('Activer les notifications'), findsNothing);
    });

    testWidgets(
      '18 — denied : « Ouvrir les réglages » utilise l\'abstraction',
      (t) async {
        final fake = _FakeNotificationService(
          status: NotificationPermissionStatus.denied,
        );
        final opener = _RecordingOpener();
        await pump(t, fake, opener: opener);
        expect(find.text('Ouvrir les réglages'), findsOneWidget);
        await t.tap(find.text('Ouvrir les réglages'));
        await t.pumpAndSettle();
        expect(opener.opened, 1);
      },
    );

    testWidgets('scope absent -> unavailable, aucun crash', (t) async {
      await t.pumpWidget(const MaterialApp(home: NotificationSettingsScreen()));
      await t.pumpAndSettle();
      expect(
        find.textContaining('ne sont pas encore disponibles'),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 15 — app démarre sans config Firebase (DisabledNotificationService)
  // -------------------------------------------------------------------------
  testWidgets('15 — MainNavShell démarre avec DisabledNotificationService', (
    t,
  ) async {
    final coord = NotificationCoordinator(
      service: DisabledNotificationService(),
    );
    await coord.start();
    final auth = await _auth(signedIn: true);
    await t.pumpWidget(
      AuthScope(
        controller: auth,
        child: AuryelStateScope(
          state: _state(),
          child: MaterialApp(
            home: MainNavShell(notificationsOverride: coord.service),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(MainNavShell), findsOneWidget);
    expect(_currentIndex(t), kTabHome);
    expect(t.takeException(), isNull);
    coord.dispose();
  });
}

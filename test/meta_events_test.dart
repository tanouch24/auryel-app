import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/analytics/meta_events.dart';
import 'package:auryel/state/meta_consent_controller.dart';

/// Faux SDK Meta : capture les appels, ne touche à aucun canal natif.
class _FakeFb implements FacebookAppEvents {
  final List<String> events = [];
  bool? advertiserTracking;
  bool? autoLog;
  int clearCalls = 0;
  int flushCalls = 0;
  List<String>? dpo;

  @override
  Future<void> logEvent({
    String? name,
    double? valueToSum,
    Map<String, Object?>? parameters,
  }) async {
    events.add(name ?? '');
    // Garde-fou PII : aucun paramètre ne doit être transmis par la façade.
    if (parameters != null && parameters.isNotEmpty) {
      throw StateError('la façade ne doit transmettre AUCUN paramètre : $parameters');
    }
  }

  bool? collectId;

  @override
  Future<void> setAdvertiserTracking({
    required bool enabled,
    bool collectId = true,
  }) async {
    advertiserTracking = enabled;
    this.collectId = collectId;
  }

  @override
  Future<void> setAutoLogAppEventsEnabled(bool enabled) async {
    autoLog = enabled;
  }

  @override
  Future<void> setDataProcessingOptions(
    List<String> options, {
    int? country,
    int? state,
  }) async {
    dpo = options;
  }

  @override
  Future<void> clearUserData() async => clearCalls++;

  @override
  Future<void> flush() async => flushCalls++;

  @override
  noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetaConfig', () {
    test('incomplète -> fabrique renvoie NoopMetaEvents', () async {
      final e = await MetaEvents.create(
        config: const MetaConfig(appId: '', clientToken: ''),
        consentGranted: true,
      );
      expect(e, isA<NoopMetaEvents>());
      expect(e.isActive, isFalse);
    });

    test('complète -> FacebookMetaEvents', () async {
      final e = await MetaEvents.create(
        config: const MetaConfig(appId: '123', clientToken: 'abc'),
        consentGranted: false,
      );
      expect(e, isA<FacebookMetaEvents>());
    });
  });

  group('FacebookMetaEvents — consentement', () {
    test('AVANT consentement : aucun événement, SDK désactivé', () async {
      final fb = _FakeFb();
      final e = FacebookMetaEvents(plugin: fb);
      await e.setConsent(false);

      expect(e.isActive, isFalse);
      expect(fb.advertiserTracking, isFalse);
      expect(fb.autoLog, isFalse);
      expect(fb.clearCalls, greaterThan(0));

      await e.logOnboardingCompleted();
      await e.logPaywallViewed();
      await e.logSubscriptionStarted();
      await e.logConsultationStarted();
      expect(fb.events, isEmpty);
    });

    test('APRÈS consentement : SDK activé, les 4 événements passent, '
        'sans aucun paramètre (PII)', () async {
      final fb = _FakeFb();
      final e = FacebookMetaEvents(plugin: fb);
      await e.setConsent(true);

      expect(e.isActive, isTrue);
      expect(fb.advertiserTracking, isTrue);
      expect(fb.autoLog, isTrue);
      expect(fb.collectId, isFalse, reason: 'GAID jamais collecté');

      await e.logOnboardingCompleted();
      await e.logPaywallViewed();
      await e.logSubscriptionStarted();
      await e.logConsultationStarted();
      expect(fb.events, [
        'onboarding_completed',
        'paywall_viewed',
        'subscription_started',
        'consultation_started',
      ]);
    });

    test('RÉVOCATION : SDK re-désactivé, purge, plus aucun événement', () async {
      final fb = _FakeFb();
      final e = FacebookMetaEvents(plugin: fb);
      await e.setConsent(true);
      await e.logPaywallViewed();
      fb.events.clear();

      await e.setConsent(false);
      expect(e.isActive, isFalse);
      expect(fb.autoLog, isFalse);
      expect(fb.clearCalls, greaterThan(0));

      await e.logPaywallViewed();
      expect(fb.events, isEmpty);
    });
  });

  group('MetaConsentController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('défaut = false (jamais pré-coché), persiste, applique au MetaEvents',
        () async {
      final fb = _FakeFb();
      final events = FacebookMetaEvents(plugin: fb);
      final c = MetaConsentController(events: events);
      await c.load();
      expect(c.granted, isFalse);

      await c.setGranted(true);
      expect(c.granted, isTrue);
      expect(events.isActive, isTrue);
      expect(await MetaConsentController.readPersisted(), isTrue);

      await c.setGranted(false);
      expect(events.isActive, isFalse);
      expect(await MetaConsentController.readPersisted(), isFalse);
    });
  });
}

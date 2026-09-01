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
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/main.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';

// ===========================================================================
// Fixtures
// ===========================================================================

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _quota({
  int monthlyLimit = 10,
  int monthlyUsed = 1,
  bool isPremium = true,
  bool firstFree = false,
  int earned = 0,
}) =>
    {
      'is_premium': isPremium,
      'monthly_limit': monthlyLimit,
      'monthly_used': monthlyUsed,
      'monthly_remaining': monthlyLimit - monthlyUsed,
      'earned_available': earned,
      'first_free_available': firstFree,
      'period_start': '2026-08-01T00:00:00Z',
      'period_end': '2026-09-01T00:00:00Z',
    };

/// Bloc `time` (TIMER-D.1) — SOURCE DE VÉRITÉ du temps disponible.
Map<String, dynamic> _time({
  int firstFree = 0,
  int premium = 28800,
  int purchased = 0,
  int? total,
  bool windowActive = true,
  Duration windowRemaining = const Duration(minutes: 5),
}) {
  final now = DateTime.now().toUtc();
  return {
    'first_free_remaining_seconds': firstFree,
    'premium_remaining_seconds': premium,
    'purchased_remaining_seconds': purchased,
    'total_remaining_seconds': total ?? (firstFree + premium + purchased),
    'window_active': windowActive,
    'window_expires_at':
        windowActive ? now.add(windowRemaining).toIso8601String() : null,
  };
}

/// Corps `GET /state` (ou `POST /message`) avec une consultation active.
/// `remaining` mappe le PORTEFEUILLE DE TEMPS total (bloc `time`). `expires_at`
/// est renvoyé pour compat mais n'est JAMAIS un cutoff.
Map<String, dynamic> _activeState({
  String advisorId = 'maia',
  Duration remaining = const Duration(hours: 2),
  int monthlyLimit = 10,
  int monthlyUsed = 1,
  bool windowActive = true,
  bool includeTime = true,
}) {
  final now = DateTime.now().toUtc();
  final totalSeconds = remaining.inSeconds;
  return {
    'consultation': {
      'id': 'c-1',
      'advisor_id': advisorId,
      'started_at':
          now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'expires_at': now.add(const Duration(hours: 2)).toIso8601String(),
      'seconds_remaining': totalSeconds,
      'credit_source': 'time',
      'opened_now': false,
    },
    if (includeTime)
      'time': _time(premium: totalSeconds, windowActive: windowActive),
    'quota': _quota(monthlyLimit: monthlyLimit, monthlyUsed: monthlyUsed),
  };
}

Map<String, dynamic> _noState({
  int monthlyLimit = 10,
  int monthlyUsed = 1,
  bool isPremium = true,
  bool firstFree = false,
  int earned = 0,
  int? timeTotal,
}) =>
    {
      'consultation': null,
      'time': _time(
        premium: timeTotal ?? (isPremium ? 28800 : 0),
        firstFree: firstFree ? 3600 : 0,
        windowActive: false,
      ),
      'quota': _quota(
        monthlyLimit: monthlyLimit,
        monthlyUsed: monthlyUsed,
        isPremium: isPremium,
        firstFree: firstFree,
        earned: earned,
      ),
    };

Map<String, dynamic> _noCreditBody({int monthlyUsed = 8}) => {
      'error': 'time_exhausted',
      'consultation': null,
      'time': _time(premium: 0, windowActive: false),
      'quota': _quota(monthlyLimit: 8, monthlyUsed: monthlyUsed),
    };

typedef _Rig = ({
  ConsultationController controller,
  AuthController auth,
  InMemoryTokenStore tokens,
  List<String> hits,
});

_Rig _rig(
  Future<http.Response> Function(http.Request req) handler, {
  String? token = 'tok',
}) {
  final hits = <String>[];
  final tokens = InMemoryTokenStore(token);
  final client = ApiClient(
    httpClient: MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      return handler(req);
    }),
    baseUrl: 'http://test.local',
  );
  final consultationApi = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(api: AuthApi(client), tokenStore: tokens),
    profileApi: ProfileApi(client),
    consultationApi: consultationApi,
    tirageApi: TirageApi(client),
  );
  final controller =
      ConsultationController(api: consultationApi, auth: auth);
  addTearDown(controller.dispose);
  return (controller: controller, auth: auth, tokens: tokens, hits: hits);
}

AuryelState _completedState({String advisor = 'Séléna'}) => AuryelState(
      repository: LocalOnboardingRepository(),
      initial: OnboardingRecord(
        userId: 'u',
        selectedAdvisor: advisor,
        firstName: 'N',
        birthDate: DateTime(1994, 1, 1),
        portraitData: 'x',
        portraitFeedback: 'y',
        onboardingCompleted: true,
      ),
    );

Future<void> _pumpWithin(
  WidgetTester tester,
  _Rig rig,
  Widget home, {
  String advisor = 'Séléna',
}) {
  return tester.pumpWidget(
    AuthScope(
      controller: rig.auth,
      child: ConsultationScope(
        controller: rig.controller,
        child: AuryelStateScope(
          state: _completedState(advisor: advisor),
          child: MaterialApp(home: home),
        ),
      ),
    ),
  );
}

int _stateGets(_Rig rig) =>
    rig.hits.where((h) => h == 'GET /api/consultation/state').length;

int _messagePosts(_Rig rig) =>
    rig.hits.where((h) => h == 'POST /api/consultation/message').length;

// ===========================================================================

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // A. GET API
  // =========================================================================
  group('A. ConsultationApi.getState', () {
    test('GET /api/consultation/state + Bearer, parse session + quota=10',
        () async {
      http.Request? seen;
      final client = ApiClient(
        httpClient: MockClient((req) async {
          seen = req;
          return _json(_activeState(advisorId: 'orion', monthlyLimit: 10));
        }),
        baseUrl: 'http://test.local',
      );

      final res = await ConsultationApi(client).getState(bearer: 'abc123');

      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/api/consultation/state');
      expect(seen!.headers['Authorization'], 'Bearer abc123');
      expect(res.consultation, isNotNull);
      expect(res.consultation!.advisorId, 'orion');
      expect(res.quota.monthlyLimit, 10);
    });

    test('consultation:null parsé proprement', () async {
      final client = ApiClient(
        httpClient: MockClient((_) async => _json(_noState())),
        baseUrl: 'http://test.local',
      );
      final res = await ConsultationApi(client).getState(bearer: 'x');
      expect(res.consultation, isNull);
      expect(res.quota.isPremium, isTrue);
      expect(res.quota.monthlyLimit, 10);
    });
  });

  // =========================================================================
  // B. Controller
  // =========================================================================
  group('B. ConsultationController', () {
    test('refresh sans jeton : aucun appel HTTP', () async {
      final rig = _rig((_) async => _json(_activeState()), token: null);
      await rig.controller.refresh();
      expect(rig.hits, isEmpty);
      expect(rig.controller.active, isNull);
    });

    test('refresh avec session active : active + quota renseignés', () async {
      final rig = _rig((_) async =>
          _json(_activeState(advisorId: 'maia', remaining: const Duration(hours: 2))));
      await rig.controller.refresh();
      expect(rig.controller.active, isNotNull);
      expect(rig.controller.active!.advisorId, 'maia');
      expect(rig.controller.hasActiveSession, isTrue);
      expect(rig.controller.quota!.monthlyLimit, 10);
    });

    test('refresh consultation:null -> active vidé', () async {
      final rig = _rig((_) async => _json(_noState()));
      await rig.controller.refresh();
      expect(rig.controller.active, isNull);
      expect(rig.controller.hasActiveSession, isFalse);
      expect(rig.controller.quota!.monthlyLimit, 10);
    });

    test('remaining dérivé de time.total, jamais de expiresAt', () async {
      final rig = _rig((_) async => _json(_activeState(
            remaining: const Duration(minutes: 90), // -> time.total = 5400
          )));
      await rig.controller.refresh();
      expect(rig.controller.remaining.inSeconds, 5400);
      // expiresAt du fixture = now + 2 h ; ignoré (sinon on lirait ~7200 s).
      expect(rig.controller.remaining.inMinutes, 90);
    });

    test('backend SANS bloc time : fallback sur consultation.secondsRemaining',
        () async {
      final rig = _rig((_) async => _json(_activeState(
            remaining: const Duration(minutes: 42),
            includeTime: false, // simule un backend distant ancien
          )));
      await rig.controller.refresh();
      expect(rig.controller.time, isNull);
      expect(rig.controller.remaining.inSeconds, 42 * 60);
      expect(rig.controller.hasActiveSession, isTrue);
    });

    test('formatTotalTime : portefeuille d\'heures', () {
      expect(ConsultationController.formatTotalTime(28800), '8 h');
      expect(ConsultationController.formatTotalTime(27720), '7 h 42 min');
      expect(ConsultationController.formatTotalTime(3600), '1 h');
      expect(ConsultationController.formatTotalTime(3900), '1 h 05 min');
      expect(ConsultationController.formatTotalTime(3300), '55 min');
      expect(ConsultationController.formatTotalTime(30), '< 1 min');
      expect(ConsultationController.formatTotalTime(0), '0 min');
      expect(ConsultationController.formatTotalTime(-30), '0 min');
      // compat : ancienne signature Duration
      expect(
          ConsultationController.formatRemaining(const Duration(hours: 1, minutes: 40)),
          '1 h 40 min');
    });

    test('temps épuisé : isExpired vrai, hasActiveSession faux', () async {
      final rig = _rig((_) async => _json(_activeState(
            remaining: const Duration(seconds: 0), // time.total = 0
          )));
      await rig.controller.refresh();
      expect(rig.controller.isExpired, isTrue);
      expect(rig.controller.hasActiveSession, isFalse);
      // ...mais la consultation reste RÉSUMABLE (historique visible).
      expect(rig.controller.hasResumableConsultation, isTrue);
      expect(rig.controller.remaining, Duration.zero);
    });

    test('le tick 1s ne tourne QUE fenêtre active, sans muter aucune donnée',
        () async {
      final rig = _rig((_) async => _json(_activeState(
            remaining: const Duration(hours: 1),
          ))); // windowActive = true par défaut
      await rig.controller.refresh();
      final exp = rig.controller.active!.expiresAt;
      final sec = rig.controller.active!.secondsRemaining;
      var notifs = 0;
      rig.controller.addListener(() => notifs++);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(rig.controller.active!.expiresAt, exp);
      expect(rig.controller.active!.secondsRemaining, sec);
      expect(rig.controller.remaining.inSeconds, 3600);
      expect(notifs, greaterThanOrEqualTo(1));
    });

    test('fenêtre inactive : aucun tick', () async {
      final rig = _rig((_) async => _json(_activeState(
            remaining: const Duration(hours: 1),
            windowActive: false,
          )));
      await rig.controller.refresh();
      var notifs = 0;
      rig.controller.addListener(() => notifs++);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(notifs, 0);
      // consultation toujours résumable + du temps dispo.
      expect(rig.controller.hasActiveSession, isTrue);
    });

    test('erreur réseau : état connu conservé + refreshError', () async {
      var call = 0;
      final rig = _rig((_) async {
        call++;
        if (call == 1) return _json(_activeState(advisorId: 'orion'));
        throw http.ClientException('offline');
      });
      await rig.controller.refresh();
      expect(rig.controller.active!.advisorId, 'orion');
      await rig.controller.refresh();
      expect(rig.controller.active!.advisorId, 'orion');
      expect(rig.controller.quota, isNotNull);
      expect(rig.controller.refreshError, isNotNull);
    });

    test('401 : invalidateSession + active vidé', () async {
      var call = 0;
      final rig = _rig((_) async {
        call++;
        if (call == 1) return _json(_activeState());
        return _json({'error': 'unauthorized'}, 401);
      });
      await rig.controller.refresh();
      expect(rig.controller.active, isNotNull);
      await rig.controller.refresh();
      expect(rig.controller.active, isNull);
      expect(rig.auth.status, AuthStatus.sessionExpired);
      expect(await rig.tokens.read(), isNull);
    });

    test('advisor_id serveur remplace la valeur locale', () async {
      var call = 0;
      final rig = _rig((_) async {
        call++;
        return _json(_activeState(advisorId: call == 1 ? 'maia' : 'orion'));
      });
      await rig.controller.refresh();
      expect(rig.controller.active!.advisorId, 'maia');
      await rig.controller.refresh();
      expect(rig.controller.active!.advisorId, 'orion');
    });

    test('refresh ne fait jamais de POST /api/consultation/message', () async {
      final rig = _rig((_) async => _json(_activeState()));
      await rig.controller.refresh();
      await rig.controller.refresh();
      expect(_stateGets(rig), 2);
      expect(_messagePosts(rig), 0);
    });

    test('updateFromMessageResponse injecte consultation + quota', () {
      final rig = _rig((_) async => _json(_noState()));
      final res = ConsultationMessageResponse.fromJson({
        ..._activeState(advisorId: 'thea', monthlyUsed: 4),
        'reply': 'x',
      });
      rig.controller.updateFromMessageResponse(res);
      expect(rig.controller.active!.advisorId, 'thea');
      expect(rig.controller.quota!.monthlyUsed, 4);
      expect(rig.controller.hasActiveSession, isTrue);
    });

    test('applyNoCredit resynchronise le quota sans fabriquer de session', () {
      final rig = _rig((_) async => _json(_noState()));
      rig.controller
          .applyNoCredit(QuotaDto.fromJson(_quota(monthlyUsed: 10)));
      expect(rig.controller.quota!.monthlyUsed, 10);
      expect(rig.controller.active, isNull);
    });
  });

  // =========================================================================
  // C. Lifecycle
  // =========================================================================
  group('C. Lifecycle', () {
    testWidgets('retour au premier plan = exactement un refresh', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/account') {
          return _json({'user_id': 'u', 'email': 'e@x.co'});
        }
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        return _json({}, 404);
      }, token: 'good');

      await t.pumpWidget(AuryelApp(
        state: _completedState(),
        auth: rig.auth,
        consultation: rig.controller,
      ));
      await t.pump(const Duration(milliseconds: 2100));
      await t.pumpAndSettle();

      final bootGets = _stateGets(rig);
      expect(bootGets, 1); // resync au boot

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();

      expect(_stateGets(rig), bootGets + 1); // un seul refresh de plus
    });
  });

  // =========================================================================
  // D. Accueil
  // =========================================================================
  group('D. Accueil', () {
    testWidgets('consultation active -> "Reprendre ma consultation" + "3 h disponibles"',
        (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_activeState(
              advisorId: 'selena', remaining: const Duration(hours: 3)));
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(t, rig, const HomeScreen());
      await t.pump();
      rig.controller.dispose(); // coupe le Timer.periodic avant les invariants
      await t.pumpAndSettle(); // vide les timers flutter_animate de l'accueil

      expect(find.text('Reprendre ma consultation'), findsOneWidget);
      // TIMER-D.2 — portefeuille d'heures « X h disponibles », pas un countdown.
      expect(find.text('3 h disponibles'), findsOneWidget);
      expect(find.text('Commencer ma consultation'), findsNothing);
      expect(find.textContaining('consultations'), findsNothing);
    });

    testWidgets('aucune session, Premium avec quota restant -> CTA abonné',
        (t) async {
      // _noState() = Premium, 9 consultations restantes -> subscriberAvailable.
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(t, rig, const HomeScreen());
      await t.pumpAndSettle();

      expect(find.text('Ouvrir une consultation'), findsOneWidget);
      expect(find.textContaining('Reprendre ma consultation'), findsNothing);
    });

    // F5-C — états du bloc consultation dérivés du quota RÉEL (lecture seule).
    testWidgets('first_free_available -> "Commencer ma consultation"',
        (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState(isPremium: false, firstFree: true));
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();
      await _pumpWithin(t, rig, const HomeScreen());
      await t.pumpAndSettle();
      expect(find.text('Commencer ma consultation'), findsOneWidget);
      expect(find.textContaining('offerte'), findsOneWidget);
    });

    testWidgets('TIMER-D.1 : crédit gagné SANS temps -> S’abonner (l\'earned ne '
        'déverrouille plus l\'accès)', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState(isPremium: false, earned: 1, timeTotal: 0));
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();
      await _pumpWithin(t, rig, const HomeScreen());
      await t.pumpAndSettle();
      expect(find.text('S’abonner pour consulter'), findsOneWidget);
    });

    testWidgets('temps disponible -> CTA "Ouvrir une consultation"', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState(timeTotal: 12000)); // ~3 h 20
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();
      await _pumpWithin(t, rig, const HomeScreen());
      await t.pumpAndSettle();
      expect(find.text('Ouvrir une consultation'), findsOneWidget);
    });

    testWidgets('ni gratuite, ni temps -> S’abonner', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState(
              isPremium: false, monthlyLimit: 0, monthlyUsed: 0, earned: 0,
              timeTotal: 0));
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();
      await _pumpWithin(t, rig, const HomeScreen());
      await t.pumpAndSettle();
      expect(find.text('S’abonner pour consulter'), findsOneWidget);
    });

    testWidgets('Premium SANS temps restant -> S’abonner', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState(timeTotal: 0)); // Premium mais time.total = 0
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();
      await _pumpWithin(t, rig, const HomeScreen());
      await t.pumpAndSettle();
      expect(find.text('S’abonner pour consulter'), findsOneWidget);
    });

    testWidgets('tap CTA -> ouvre ChatScreen sans POST', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_activeState(
              advisorId: 'selena', remaining: const Duration(hours: 3)));
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(t, rig, const HomeScreen());
      await t.pump();

      await t.tap(find.text('Reprendre ma consultation'));
      await t.pumpAndSettle();
      rig.controller.dispose();

      expect(find.text('Écris ton message…'), findsOneWidget);
      expect(_messagePosts(rig), 0);
    });
  });

  // =========================================================================
  // E. ChatScreen
  // =========================================================================
  group('E. ChatScreen', () {
    testWidgets('session active injectée -> pas de confirmation d\'ouverture',
        (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_activeState(advisorId: 'maia'));
        }
        if (req.url.path == '/api/consultation/message') {
          return _json({..._activeState(advisorId: 'maia'), 'reply': 'ok'});
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(
          t, rig, ChatScreen(advisor: advisorByNameOrNull('Séléna')!));
      await t.pump();

      await t.enterText(find.byType(TextField), 'coucou');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      rig.controller.dispose();

      expect(find.text('Ce premier message ouvre ta consultation. Le temps se décompte '
          'ensuite de ton temps disponible.'),
          findsNothing);
      expect(_messagePosts(rig), 1);
    });

    testWidgets('aucune session -> confirmation F3 au 1er message', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        if (req.url.path == '/api/consultation/message') {
          return _json({..._activeState(), 'reply': 'ok'});
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(
          t, rig, ChatScreen(advisor: advisorByNameOrNull('Séléna')!));
      await t.pump();

      await t.enterText(find.byType(TextField), 'bonjour');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();

      expect(find.text('Ce premier message ouvre ta consultation. Le temps se décompte '
          'ensuite de ton temps disponible.'),
          findsOneWidget);
      expect(_messagePosts(rig), 0);
    });

    testWidgets('POST 200 -> ConsultationController reçoit le nouvel état, un seul POST',
        (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        if (req.url.path == '/api/consultation/message') {
          return _json({
            ..._activeState(advisorId: 'orion', monthlyUsed: 3),
            'reply': 'vu',
          });
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(
          t, rig, ChatScreen(advisor: advisorByNameOrNull('Séléna')!));
      await t.pump();

      await t.enterText(find.byType(TextField), 'salut');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();
      final activeAdvisor = rig.controller.active?.advisorId;
      final usedAfter = rig.controller.quota?.monthlyUsed;
      final hadActive = rig.controller.active != null;
      rig.controller.dispose();

      expect(hadActive, isTrue);
      expect(activeAdvisor, 'orion');
      expect(usedAfter, 3);
      expect(_messagePosts(rig), 1);
      expect(find.text('vu'), findsOneWidget);
    });

    testWidgets('réseau KO -> texte conservé + Réessayer, état contrôleur intact',
        (t) async {
      var call = 0;
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        if (req.url.path == '/api/consultation/message') {
          call++;
          throw http.ClientException('offline');
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(
          t, rig, ChatScreen(advisor: advisorByNameOrNull('Séléna')!));
      await t.pump();

      await t.enterText(find.byType(TextField), 'mon message');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      expect(find.text('mon message'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(call, 1);
      expect(rig.controller.active, isNull);
    });

    testWidgets('402 time_exhausted -> mur Premium + time/quota resync, pas de session',
        (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        if (req.url.path == '/api/consultation/message') {
          return _json(_noCreditBody(monthlyUsed: 10), 402);
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(
          t, rig, ChatScreen(advisor: advisorByNameOrNull('Séléna')!));
      await t.pump();

      await t.enterText(find.byType(TextField), 'coucou');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      // _noCreditBody() est Premium -> mur sobre (titre « disponible épuisé »,
      // pas de prix, pas de « Découvrir Premium »).
      expect(find.text('Ton temps de consultation disponible est épuisé.'),
          findsOneWidget);
      expect(find.text('Premium — 7,99 €/mois'), findsNothing);
      expect(rig.controller.active, isNull);
      // TIMER-D.1 — le corps du 402 resynchronise `time` (0) + `quota`.
      expect(rig.controller.time!.totalRemainingSeconds, 0);
      expect(rig.controller.quota!.monthlyUsed, 10);
    });

    testWidgets('401 -> retour EmailAuthScreen, session purgée', (t) async {
      final rig = _rig((req) async {
        if (req.url.path == '/api/consultation/state') {
          return _json(_noState());
        }
        if (req.url.path == '/api/consultation/message') {
          return _json({'error': 'unauthorized'}, 401);
        }
        return _json({}, 404);
      });
      await rig.controller.refresh();

      await _pumpWithin(
          t, rig, ChatScreen(advisor: advisorByNameOrNull('Séléna')!));
      await t.pump();

      await t.enterText(find.byType(TextField), 'hello');
      await t.pump();
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Commencer'));
      await t.pumpAndSettle();

      expect(find.text('Ton adresse email'), findsOneWidget);
      expect(await rig.tokens.read(), isNull);
      expect(rig.auth.status, AuthStatus.sessionExpired);
    });
  });
}

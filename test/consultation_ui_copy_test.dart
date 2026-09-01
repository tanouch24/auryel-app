import 'dart:convert';
import 'dart:io';

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
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/home_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/consultation_block.dart';

// ===========================================================================
// TIMER-D.2 — cohérence de la copy produit « temps » dans l'UI.
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
    jsonEncode(b), s, headers: {'content-type': 'application/json'});

Map<String, dynamic> _time({
  int firstFree = 0,
  int premium = 0,
  int purchased = 0,
  bool windowActive = false,
}) => {
      'first_free_remaining_seconds': firstFree,
      'premium_remaining_seconds': premium,
      'purchased_remaining_seconds': purchased,
      'total_remaining_seconds': firstFree + premium + purchased,
      'window_active': windowActive,
      'window_expires_at': windowActive ? '2999-01-01T00:05:00Z' : null,
    };

Map<String, dynamic> _quota({bool isPremium = true, bool firstFree = false}) => {
      'is_premium': isPremium,
      'monthly_limit': 8,
      'monthly_used': 1,
      'monthly_remaining': 7,
      'earned_available': 0,
      'first_free_available': firstFree,
      'period_start': '2026-08-01T00:00:00Z',
      'period_end': '2026-09-01T00:00:00Z',
    };

typedef _Rig = ({ConsultationController controller, AuthController auth});

_Rig _rig(Future<http.Response> Function(http.Request) handler) {
  final client = ApiClient(
    httpClient: MockClient(handler),
    baseUrl: 'http://test.local',
  );
  final api = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
        api: AuthApi(client), tokenStore: InMemoryTokenStore('tok')),
    profileApi: ProfileApi(client),
    consultationApi: api,
    tirageApi: TirageApi(client),
  );
  final controller = ConsultationController(api: api, auth: auth);
  addTearDown(controller.dispose);
  return (controller: controller, auth: auth);
}

Future<void> _pumpHome(WidgetTester t, _Rig rig) => t.pumpWidget(
      AuthScope(
        controller: rig.auth,
        child: ConsultationScope(
          controller: rig.controller,
          child: AuryelStateScope(
            state: AuryelState(
              repository: LocalOnboardingRepository(),
              initial: OnboardingRecord(
                userId: 'u',
                selectedAdvisor: 'Séléna',
                firstName: 'N',
                birthDate: DateTime(1994, 1, 1),
                portraitData: 'x',
                portraitFeedback: 'y',
                onboardingCompleted: true,
              ),
            ),
            child: const MaterialApp(home: HomeScreen()),
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  group('Accueil — bloc consultation', () {
    testWidgets('A. première heure disponible -> "1 h ... offerte"', (t) async {
      final rig = _rig((_) async => _json({
            'consultation': null,
            'time': _time(firstFree: 3600),
            'quota': _quota(isPremium: false, firstFree: true),
          }));
      await rig.controller.refresh();
      await _pumpHome(t, rig);
      await t.pumpAndSettle();
      expect(find.text('Ta première heure de consultation est offerte'),
          findsOneWidget);
      expect(find.textContaining('2 h'), findsNothing);
      expect(find.textContaining('consultations'), findsNothing);
    });

    testWidgets('B/E. Premium avec temps -> "7 h 42 min disponibles"',
        (t) async {
      final rig = _rig((_) async => _json({
            'consultation': null,
            'time': _time(premium: 27720), // 7 h 42 min
            'quota': _quota(),
          }));
      await rig.controller.refresh();
      await _pumpHome(t, rig);
      await t.pumpAndSettle();
      expect(find.text('7 h 42 min disponibles'), findsOneWidget);
      expect(find.text('Ouvrir une consultation'), findsOneWidget);
      expect(find.textContaining('/8'), findsNothing);
      expect(find.textContaining('consultations restantes'), findsNothing);
    });

    testWidgets('J. 0 temps -> "S’abonner pour consulter"', (t) async {
      final rig = _rig((_) async => _json({
            'consultation': null,
            'time': _time(), // total 0
            'quota': _quota(isPremium: false),
          }));
      await rig.controller.refresh();
      await _pumpHome(t, rig);
      await t.pumpAndSettle();
      expect(find.text('S’abonner pour consulter'), findsOneWidget);
      expect(find.text('Ton temps de consultation est épuisé.'), findsOneWidget);
    });

    testWidgets('reprise -> "Reprendre ma consultation" + "X disponibles"',
        (t) async {
      final rig = _rig((_) async => _json({
            'consultation': {
              'id': 'c-1',
              'advisor_id': 'selena',
              'started_at': '2026-09-01T10:00:00Z',
              'expires_at': '2026-09-01T12:00:00Z',
              'seconds_remaining': 12000,
              'credit_source': 'time',
              'opened_now': false,
            },
            'time': _time(premium: 12000, windowActive: false),
            'quota': _quota(),
          }));
      await rig.controller.refresh();
      await _pumpHome(t, rig);
      await t.pump();
      rig.controller.dispose();
      await t.pumpAndSettle();
      expect(find.text('Reprendre ma consultation'), findsOneWidget);
      expect(find.text('3 h 20 min disponibles'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('ConsultationBlock — sous-texte temps', () {
    testWidgets('subscriberAvailable + availableTimeText affiché', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ConsultationBlock(
            state: ConsultationState.subscriberAvailable,
            advisorName: 'Séléna',
            advisorAssetPath: 'assets/conseillers/selena.webp',
            availableTimeText: '2 h 05 min disponibles',
          ),
        ),
      ));
      expect(find.text('2 h 05 min disponibles'), findsOneWidget);
    });

    testWidgets('locked -> "temps épuisé" + "S’abonner"', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ConsultationBlock(
            state: ConsultationState.locked,
            advisorName: 'Séléna',
            advisorAssetPath: 'assets/conseillers/selena.webp',
          ),
        ),
      ));
      expect(find.text('Ton temps de consultation est épuisé.'), findsOneWidget);
      expect(find.text('S’abonner pour consulter'), findsOneWidget);
      expect(find.textContaining('consultation de 2 h'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('Chat — statut d\'en-tête', () {
    Future<void> pumpChat(WidgetTester t, _Rig rig, Map<String, dynamic> time) {
      rig.controller.updateFromMessageResponse(
        ConsultationMessageResponse.fromJson({
          'reply': 'x',
          'consultation': {
            'id': 'c-1',
            'advisor_id': 'selena',
            'started_at': '2026-09-01T10:00:00Z',
            'expires_at': '2026-09-01T12:00:00Z',
            'seconds_remaining': time['total_remaining_seconds'],
            'credit_source': 'time',
          },
          'time': time,
          'quota': _quota(),
        }),
      );
      return t.pumpWidget(
        AuthScope(
          controller: rig.auth,
          child: ConsultationScope(
            controller: rig.controller,
            child: AuryelStateScope(
              state: AuryelState(
                repository: LocalOnboardingRepository(),
                initial: OnboardingRecord(
                  userId: 'u',
                  selectedAdvisor: 'Séléna',
                  firstName: 'N',
                  birthDate: DateTime(1994, 1, 1),
                  portraitData: 'x',
                  portraitFeedback: 'y',
                  onboardingCompleted: true,
                ),
              ),
              child: MaterialApp(
                home: ChatScreen(advisor: advisorByNameOrNull('Séléna')!),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('F. windowActive -> "Consultation en cours"', (t) async {
      final rig = _rig((_) async => _json({
            'consultation_id': 'c-1',
            'messages': const [],
          }));
      await pumpChat(t, rig, _time(premium: 27720, windowActive: true));
      await t.pump();
      await t.pump();
      expect(find.textContaining('Consultation en cours'), findsOneWidget);
      expect(find.textContaining('7 h 42 min disponibles'), findsOneWidget);
      expect(find.textContaining('expir'), findsNothing);
      rig.controller.dispose();
    });

    testWidgets('windowInactive -> "X disponibles", jamais "expirée"',
        (t) async {
      final rig = _rig((_) async => _json({
            'consultation_id': 'c-1',
            'messages': const [],
          }));
      await pumpChat(t, rig, _time(premium: 27720, windowActive: false));
      await t.pump();
      await t.pump();
      expect(find.textContaining('7 h 42 min disponibles'), findsOneWidget);
      expect(find.textContaining('Consultation en cours'), findsNothing);
      expect(find.textContaining('expir'), findsNothing);
      expect(find.textContaining('terminée'), findsNothing);
      rig.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  test('R. aucune ancienne copy « 4 consultations » / « consultation(s) de 2 h » '
      '/ « X/Y ce mois » ne subsiste dans lib/', () {
    final banned = <RegExp>[
      RegExp(r'4 consultations'),
      RegExp(r'consultations? de 2\s?h'),
      RegExp(r'consultations? restantes?'),
      RegExp(r'/\$\{?q\.monthlyLimit'), // "X/Y ce mois" interpolé
      RegExp(r'ce mois'),
    ];
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.split('//').first; // ignore les commentaires en fin de ligne
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        for (final re in banned) {
          if (re.hasMatch(code)) {
            offenders.add('${f.path}:${i + 1}  $line');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: 'copy obsolète:\n${offenders.join('\n')}');
  });
}

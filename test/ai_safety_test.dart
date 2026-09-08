import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/ai_report_api.dart';
import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/chat_screen.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/onboarding/advisor_selection_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/ai_transparency_note.dart';

// ===========================================================================
// LOT AUDIT IA / GARDE-FOUS / CONFORMITÉ STORE — transparence IA + signalement.
// ===========================================================================

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _time() => {
  'first_free_remaining_seconds': 0,
  'premium_remaining_seconds': 6000,
  'purchased_remaining_seconds': 0,
  'total_remaining_seconds': 6000,
  'window_active': true,
  'window_expires_at': '2999-01-01T00:05:00Z',
};

Map<String, dynamic> _quota() => {
  'is_premium': true,
  'monthly_limit': 8,
  'monthly_used': 1,
  'monthly_remaining': 7,
  'earned_available': 0,
  'first_free_available': false,
  'period_start': '2026-08-01T00:00:00Z',
  'period_end': '2026-09-01T00:00:00Z',
};

class _ChatRig {
  _ChatRig() {
    final client = ApiClient(
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/consultation/message') {
          return _json({
            'reply': 'Voici ma lecture de ta situation.',
            'consultation': {
              'id': 'c-1',
              'advisor_id': 'selena',
              'started_at': '2026-09-06T10:00:00Z',
              'expires_at': '2026-09-06T12:00:00Z',
              'seconds_remaining': 6000,
              'credit_source': 'time',
              'opened_now': true,
            },
            'quota': _quota(),
            'time': _time(),
          });
        }
        if (p == '/api/consultation/messages') {
          return _json({'consultation_id': null, 'messages': []});
        }
        if (p == '/api/app/ai/report') {
          reportBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({'status': 'ok'});
        }
        return _json({}, 404);
      }),
      baseUrl: 'http://test.local',
    );
    aiReportApi = AiReportApi(client);
    auth = AuthController(
      repository: AuthRepository(
        api: AuthApi(client),
        tokenStore: InMemoryTokenStore('tok'),
      ),
      profileApi: ProfileApi(client),
      consultationApi: ConsultationApi(client),
      tirageApi: TirageApi(client),
    );
  }

  late final AuthController auth;
  late final AiReportApi aiReportApi;
  final List<Map<String, dynamic>> reportBodies = [];
}

AuryelState _state({bool onboarded = true}) => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u',
    selectedAdvisor: 'Séléna',
    firstName: 'N',
    birthDate: DateTime(1994, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: onboarded,
  ),
);

Future<void> _pumpChat(WidgetTester t, _ChatRig rig, {Size? size}) async {
  if (size != null) {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(
    AuthScope(
      controller: rig.auth,
      child: AuryelStateScope(
        state: _state(),
        child: MaterialApp(
          home: ChatScreen(
            advisor: advisorByNameOrNull('Séléna')!,
            aiReportApi: rig.aiReportApi,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _sendAndReceive(WidgetTester t) async {
  await t.enterText(find.byType(TextField).first, 'coucou');
  await t.pump();
  await t.tap(find.byIcon(Icons.send_rounded));
  await t.pumpAndSettle();
  if (find.text('Commencer').evaluate().isNotEmpty) {
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  // TRANSPARENCE IA
  // -------------------------------------------------------------------------
  group('Transparence IA', () {
    test('wording canonique exact', () {
      expect(
        kAiTransparencyText,
        'Une partie de nos échanges est gérée par une intelligence '
        'artificielle.',
      );
    });

    testWidgets('AiTransparencyNote affiche le texte canonique', (t) async {
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: AiTransparencyNote())),
      );
      expect(find.text(kAiTransparencyText), findsOneWidget);
    });

    testWidgets('14 — présente dans le Chat, sous l\'en-tête, sans envoyer '
        'de message', (t) async {
      final rig = _ChatRig();
      addTearDown(rig.auth.dispose);
      await _pumpChat(t, rig);
      expect(find.text(kAiTransparencyText), findsOneWidget);
    });

    testWidgets(
      'présente dans « Mon compte » (Informations & confidentialité)',
      (t) async {
        await t.pumpWidget(
          AuryelStateScope(
            state: _state(),
            child: MaterialApp(
              home: DashboardScreen(
                thoughtRepository: DailyThoughtRepository(
                  seed: [
                    DailyThought(
                      id: 1,
                      publishDate: DateTime(2026, 9, 4),
                      phrase: 'x',
                      interpretation: 'y',
                      imageAsset:
                          'assets/pensees/publications/01_2026-09-04.webp',
                    ),
                  ],
                ),
                showBackButton: false,
              ),
            ),
          ),
        );
        await t.pump();
        await t.ensureVisible(find.text(kAiTransparencyText));
        expect(find.text(kAiTransparencyText), findsOneWidget);
      },
    );

    testWidgets('présente à l\'onboarding (choix du conseiller)', (t) async {
      await t.pumpWidget(
        AuryelStateScope(
          state: _state(onboarded: false),
          child: const MaterialApp(home: AdvisorSelectionScreen()),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text(kAiTransparencyText));
      expect(find.text(kAiTransparencyText), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // SIGNALEMENT — garde-fous UX
  // -------------------------------------------------------------------------
  group('Signalement IA — garde-fous', () {
    testWidgets('19 — le menu ⋯ n\'existe pas sur un message utilisateur', (
      t,
    ) async {
      final rig = _ChatRig();
      addTearDown(rig.auth.dispose);
      await _pumpChat(t, rig);
      await _sendAndReceive(t);
      // Un seul PopupMenuButton -> attaché à la seule réponse conseiller.
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      expect(find.text('coucou'), findsOneWidget); // le message user est là
    });

    testWidgets('15 — le sheet ne promet AUCUNE modération humaine', (t) async {
      final rig = _ChatRig();
      addTearDown(rig.auth.dispose);
      await _pumpChat(t, rig);
      await _sendAndReceive(t);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Signaler cette réponse'));
      await t.pumpAndSettle();

      expect(find.textContaining('notre équipe'), findsNothing);
      expect(find.textContaining('va intervenir'), findsNothing);
      expect(find.textContaining('un humain'), findsNothing);
      expect(find.textContaining('modérateur'), findsNothing);
      // Le texte réel, sobre.
      expect(
        find.textContaining('Ton signalement nous aide à améliorer Auryel'),
        findsOneWidget,
      );
    });

    testWidgets('9/15 — succès : confirmation sobre, sans promesse humaine', (
      t,
    ) async {
      final rig = _ChatRig();
      addTearDown(rig.auth.dispose);
      await _pumpChat(t, rig);
      await _sendAndReceive(t);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Signaler cette réponse'));
      await t.pumpAndSettle();
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();

      expect(rig.reportBodies, hasLength(1));
      expect(rig.reportBodies.single['consultation_id'], 'c-1');
      expect(find.textContaining('Merci'), findsOneWidget);
      expect(find.textContaining('notre équipe'), findsNothing);
    });

    testWidgets('16 — après un signalement, la réponse IA reste et la '
        'consultation continue', (t) async {
      final rig = _ChatRig();
      addTearDown(rig.auth.dispose);
      await _pumpChat(t, rig);
      await _sendAndReceive(t);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Signaler cette réponse'));
      await t.pumpAndSettle();
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();

      // La réponse conseiller est toujours affichée.
      expect(find.text('Voici ma lecture de ta situation.'), findsOneWidget);
      // Le champ de saisie est toujours actif -> on peut continuer.
      expect(find.byType(TextField), findsWidgets);
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    for (final w in const [360.0, 384.0, 430.0]) {
      testWidgets('13/N — sheet de signalement sans overflow à ${w.toInt()} dp '
          '(clavier ouvert)', (t) async {
        final rig = _ChatRig();
        addTearDown(rig.auth.dispose);
        await _pumpChat(t, rig, size: Size(w, 640));
        await _sendAndReceive(t);
        await t.tap(find.byType(PopupMenuButton<String>));
        await t.pumpAndSettle();
        await t.tap(find.text('Signaler cette réponse'));
        await t.pumpAndSettle();

        // Simule un clavier ouvert (viewInsets bottom élevé).
        t.view.viewInsets = FakeViewPadding(
          bottom: 320 * t.view.devicePixelRatio,
        );
        addTearDown(() => t.view.resetViewInsets());
        await t.pump();

        expect(t.takeException(), isNull, reason: '${w.toInt()} dp + clavier');
        expect(find.text('Signaler cette réponse'), findsOneWidget);
        // On peut scroller jusqu'au bouton d'envoi.
        await t.ensureVisible(find.text('Envoyer le signalement'));
      });
    }
  });
}

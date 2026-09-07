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
import 'package:auryel/data/advisor_audio.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/consultation.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/consultation_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/state/consultation_controller.dart';
import 'package:auryel/widgets/advisors_carousel.dart';
import 'package:auryel/widgets/main_nav_scope.dart';

// ===========================================================================
// LOT « ONGLET CENTRAL CONSULTATION » — feed vertical des 10 conseillers +
// audio immersif (un seul lecteur, mute persistant, arrêt hors onglet).
// ===========================================================================

class _FakeAudio implements AdvisorAudio {
  final List<String> calls = [];
  String? lastAsset;

  @override
  Future<void> play(String assetPath, {Duration fadeIn = Duration.zero}) async {
    lastAsset = assetPath;
    calls.add('play:$assetPath');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  void dispose() => calls.add('dispose');
}

AuryelState _state() => AuryelState(
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
);

ConsultationController _controllerNoHttp() {
  final client = ApiClient(
    httpClient: MockClient((_) async => http.Response('{}', 404)),
    baseUrl: 'http://test.local',
  );
  final api = ConsultationApi(client);
  final auth = AuthController(
    repository: AuthRepository(
      api: AuthApi(client),
      tokenStore: InMemoryTokenStore('t'),
    ),
    profileApi: ProfileApi(client),
    consultationApi: api,
    tirageApi: TirageApi(client),
  );
  final c = ConsultationController(api: api, auth: auth);
  addTearDown(c.dispose);
  return c;
}

Map<String, dynamic> _time({int total = 3600, bool windowActive = false}) => {
  'first_free_remaining_seconds': total,
  'premium_remaining_seconds': 0,
  'purchased_remaining_seconds': 0,
  'total_remaining_seconds': total,
  'window_active': windowActive,
  'window_expires_at': windowActive ? '2999-01-01T00:05:00Z' : null,
};

Map<String, dynamic> _quota() => {
  'is_premium': false,
  'monthly_limit': 8,
  'monthly_used': 0,
  'monthly_remaining': 8,
  'earned_available': 0,
  'first_free_available': true,
  'period_start': '2026-08-01T00:00:00Z',
  'period_end': '2026-09-01T00:00:00Z',
};

void _injectActiveSession(ConsultationController c, String advisorId) {
  c.updateFromMessageResponse(
    ConsultationMessageResponse.fromJson({
      'reply': 'x',
      'consultation': {
        'id': 'c-1',
        'advisor_id': advisorId,
        'started_at': '2026-09-01T10:00:00Z',
        'expires_at': '2026-09-01T12:00:00Z',
        'seconds_remaining': 9000,
        'credit_source': 'time',
      },
      'time': _time(total: 9000, windowActive: false),
      'quota': _quota(),
    }),
  );
}

Widget _host({
  ConsultationController? controller,
  _FakeAudio? audio,
  int currentIndex = kTabConsultation,
  ValueChanged<int>? goToTab,
}) {
  Widget screen = ConsultationScreen(audioOverride: audio);
  if (controller != null) {
    screen = ConsultationScope(controller: controller, child: screen);
  }
  return AuryelStateScope(
    state: _state(),
    child: MaterialApp(
      home: MainNavScope(
        goToTab: goToTab ?? (_) {},
        currentIndex: currentIndex,
        child: Scaffold(body: screen),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Feed vertical', () {
    testWidgets(
      '10 conseillers dans un PageView vertical, 1 visible à la fois',
      (t) async {
        final audio = _FakeAudio();
        await t.pumpWidget(_host(audio: audio));
        await t.pumpAndSettle();

        final pv = t.widget<PageView>(find.byType(PageView));
        expect(pv.scrollDirection, Axis.vertical);
        // 1er conseiller visible + son CTA nominatif.
        expect(find.text('Consulter Séléna'), findsOneWidget);
        expect(find.text('Consulter Luna'), findsNothing);
        // temps disponible affiché.
        expect(find.textContaining('Temps disponible'), findsOneWidget);
        expect(find.text('1 h offerte'), findsOneWidget);
      },
    );

    testWidgets('swipe vertical -> conseiller suivant', (t) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await t.pumpAndSettle();

      await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
      await t.pumpAndSettle();

      expect(find.text('Consulter Luna'), findsOneWidget);
      expect(find.text('Consulter Séléna'), findsNothing);
    });
  });

  group('Audio', () {
    testWidgets('autoplay au montage + un seul lecteur ; swipe stoppe le '
        'précédent avant de jouer le suivant', (t) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await t.pumpAndSettle();

      expect(audio.lastAsset, kAdvisors[0].voicePath); // Séléna
      audio.calls.clear();

      await t.fling(find.byType(PageView), const Offset(0, -400), 1200);
      await t.pumpAndSettle();

      final stopIdx = audio.calls.indexOf('stop');
      final playIdx = audio.calls.indexWhere(
        (c) => c == 'play:${kAdvisors[1].voicePath}',
      );
      expect(stopIdx, isNonNegative);
      expect(playIdx, isNonNegative);
      expect(stopIdx, lessThan(playIdx), reason: 'stop AVANT le play suivant');
    });

    testWidgets('quitter l\'onglet CONSULTATION arrête l\'audio', (t) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio, currentIndex: kTabConsultation));
      await t.pumpAndSettle();
      audio.calls.clear();

      // L'utilisateur passe sur un autre onglet.
      await t.pumpWidget(_host(audio: audio, currentIndex: kTabHome));
      await t.pumpAndSettle();

      expect(audio.calls, contains('stop'));
    });

    testWidgets('bouton mute : coupe l\'audio, préférence persistée, pas '
        'd\'autoplay au remontage', (t) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await t.pumpAndSettle();

      await t.tap(find.bySemanticsLabel('Couper le son des présentations'));
      await t.pumpAndSettle();
      expect(audio.calls, contains('stop'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auryel.consultation.audio_muted.v1'), isTrue);

      // Remontage : muted -> aucun play.
      final audio2 = _FakeAudio();
      await t.pumpWidget(_host(audio: audio2));
      await t.pumpAndSettle();
      expect(audio2.calls.where((c) => c.startsWith('play:')), isEmpty);
      expect(
        find.bySemanticsLabel('Activer le son des présentations'),
        findsOneWidget,
      );
    });

    testWidgets('lifecycle : passage en arrière-plan arrête l\'audio', (
      t,
    ) async {
      final audio = _FakeAudio();
      await t.pumpWidget(_host(audio: audio));
      await t.pumpAndSettle();
      audio.calls.clear();

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pumpAndSettle();
      expect(audio.calls, contains('stop'));
    });
  });

  group('Session active', () {
    testWidgets('priorité « Reprendre » ; le conseiller de session est '
        'conservé ; un autre conseiller ne le remplace pas', (t) async {
      final c = _controllerNoHttp();
      _injectActiveSession(c, 'ezra');
      await t.pumpWidget(_host(controller: c, audio: _FakeAudio()));
      await t.pumpAndSettle();

      // Bandeau prioritaire.
      expect(
        find.textContaining('Consultation en cours avec Ezra'),
        findsWidgets,
      );
      expect(find.text('Reprendre ma consultation'), findsWidgets);

      // Page 1 = Séléna (autre conseiller) : PAS de « Consulter Séléna ».
      expect(find.text('Consulter Séléna'), findsNothing);
      expect(
        find.textContaining('Ta consultation en cours reste avec Ezra'),
        findsOneWidget,
      );
      expect(
        find.text('Choisir Séléna pour ma prochaine consultation'),
        findsOneWidget,
      );
    });
  });

  group('Accessibilité & responsive', () {
    testWidgets('CTA principal + bouton mute portent une sémantique bouton', (
      t,
    ) async {
      await t.pumpWidget(_host(audio: _FakeAudio()));
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              (w.properties.label ?? '').contains('Consulter Séléna'),
        ),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel('Couper le son des présentations'),
        findsOneWidget,
      );
    });

    for (final w in const [360.0, 384.0, 430.0]) {
      testWidgets('aucun overflow à ${w.toInt()} dp', (t) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = Size(w, 820);
        addTearDown(t.view.reset);
        await t.pumpWidget(_host(audio: _FakeAudio()));
        await t.pumpAndSettle();
        expect(find.byType(PageView), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}

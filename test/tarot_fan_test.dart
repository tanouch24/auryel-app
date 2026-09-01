import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/auth_api.dart';
import 'package:auryel/api/consultation_api.dart';
import 'package:auryel/api/profile_api.dart';
import 'package:auryel/api/tirage_api.dart';
import 'package:auryel/data/auth_repository.dart';
import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/token_store.dart';
import 'package:auryel/screens/tirage_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/state/auth_controller.dart';
import 'package:auryel/widgets/tarot_fan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rang de sélection (1..n) de la carte d'index [i], ou `null` si non choisie.
/// Le test d'appartenance passe par `contains` (jamais `indexOf(...) == -1`).
int? _posOf(List<int> selected, int i) =>
    selected.contains(i) ? selected.indexOf(i) + 1 : null;

Future<void> _pumpFan(
  WidgetTester tester, {
  int count = 22,
  int? Function(int)? selectionNumberFor,
  void Function(int)? onTap,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TarotFan(
          count: count,
          selectionNumberFor: selectionNumberFor ?? (_) => null,
          onTap: onTap ?? (_) {},
          enabled: enabled,
        ),
      ),
    ),
  );
}

/// Harnais réactif : reproduit le contrat d'un appelant réel de [TarotFan]
/// (comme `_TirageScreenState`) — le tap enregistre la sélection via `setState`,
/// bloque les doublons et plafonne à 3. Permet de vérifier le rendu (pastilles)
/// et la logique de sélection au niveau du widget.
class _FanHarness extends StatefulWidget {
  const _FanHarness({super.key});

  static const int max = 3;

  @override
  State<_FanHarness> createState() => _FanHarnessState();
}

class _FanHarnessState extends State<_FanHarness> {
  final List<int> selected = <int>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: TarotFan(
          count: 22,
          selectionNumberFor: (i) => _posOf(selected, i),
          enabled: selected.length < _FanHarness.max,
          onTap: (i) {
            if (selected.contains(i) || selected.length >= _FanHarness.max) {
              return;
            }
            setState(() => selected.add(i));
          },
        ),
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // =========================================================================
  // INTÉGRATION — TarotFan dans le vrai TirageScreen (logique backend réelle).
  // Prouve, en tapant réellement des cartes : 22 dos ensemble sans scroll,
  // 3 sélections max dans l'ordre des taps, doublon ignoré, bouton « Révéler »
  // après 3 choix, aucune face révélée ni aucun appel réseau avant la
  // sauvegarde backend, et aucun POST consultation pendant la sélection.
  // =========================================================================
  testWidgets(
    'TirageScreen : 22 dos ensemble sans scroll, 3 max dans l’ordre des taps, '
    'doublon ignoré, « Révéler » après 3, aucune face ni appel réseau avant '
    'la sauvegarde backend, aucun POST consultation',
    (tester) async {
      final posts = <String>[];
      final keysSent = <List<String>>[];
      final client = ApiClient(
        httpClient: MockClient((req) async {
          posts.add('${req.method} ${req.url.path}');
          if (req.url.path == '/api/tirages' && req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final keys = (body['card_keys'] as List).cast<String>();
            keysSent.add(keys);
            return http.Response(
              jsonEncode({
                'tirage_id': 'tir-1',
                'card_keys': keys,
                'cards': [
                  for (final k in keys)
                    {'key': k, 'name': 'N-$k', 'interpretation': 'I-$k'},
                ],
                'combined_interpretation': 'LECTURE SERVEUR',
                'advisor_id': 'selena',
                'created_at': '2026-09-01T10:00:00Z',
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            404,
            headers: {'content-type': 'application/json'},
          );
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
      final state = AuryelState(
        repository: LocalOnboardingRepository(),
        initial: OnboardingRecord(
          userId: 'u-1',
          selectedAdvisor: 'Séléna',
          firstName: 'Alice',
          birthDate: null,
          portraitData: 'x',
          portraitFeedback: 'ok',
          onboardingCompleted: true,
        ),
      );

      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: AuryelStateScope(
            state: state,
            child: const MaterialApp(home: TirageScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // --- 22 dos tapables, ensemble, AUCUN scroll horizontal ---------------
      for (var i = 0; i < 22; i++) {
        expect(find.byKey(ValueKey('tarot-back-$i')), findsOneWidget);
      }
      expect(
        find.descendant(
          of: find.byType(TarotFan),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
        reason: 'le TarotFan ne doit contenir aucun Scrollable',
      );

      final st = tester.state(find.byType(TirageScreen)) as dynamic;
      final deck = List<String>.from(st.debugDeckKeys as List);
      expect(deck, hasLength(22));

      // --- sélection : extrémités + milieu, avec un doublon au passage ------
      await tester.tap(find.byKey(const ValueKey('tarot-back-21')));
      await tester.pumpAndSettle();
      // doublon (encore moins de 3 choisies) -> ignoré
      await tester.tap(find.byKey(const ValueKey('tarot-back-21')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tarot-back-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tarot-back-10')));
      await tester.pumpAndSettle();

      // ordre des taps conservé, sans doublon
      expect(st.debugSelectionKeys, [deck[21], deck[0], deck[10]]);

      // --- maximum 3 : un 4e tap sur une carte neuve est ignoré ------------
      await tester.tap(find.byKey(const ValueKey('tarot-back-5')));
      await tester.pumpAndSettle();
      expect(st.debugSelectionKeys, [deck[21], deck[0], deck[10]]);

      // --- après 3 choix : « Révéler » + récap, mais AUCUNE face ni appel --
      expect(find.text('Révéler mon tirage'), findsOneWidget);
      expect(find.text('Tes 3 cartes sont choisies'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(posts, isEmpty);

      // --- « Révéler » -> POST /api/tirages, 3 clés dans l’ordre des taps --
      await tester.tap(find.text('Révéler mon tirage'));
      await tester.pumpAndSettle();

      expect(posts, ['POST /api/tirages']);
      expect(keysSent.single, [deck[21], deck[0], deck[10]]);
      expect(find.byType(Image), findsNWidgets(3));
      expect(
        posts.where((p) => p.contains('/api/consultation')),
        isEmpty,
        reason: 'changer/choisir un tirage ne touche jamais la consultation',
      );
    },
  );

  // =========================================================================
  // UNITÉ — le widget TarotFan isolé.
  // =========================================================================
  testWidgets('les 22 dos portent chacun une ValueKey unique', (tester) async {
    await _pumpFan(tester, count: 22);
    for (var i = 0; i < 22; i++) {
      expect(find.byKey(ValueKey('tarot-back-$i')), findsOneWidget);
    }
  });

  testWidgets(
    'indices 0, 1, 5, 10, 15, 20, 21 réellement tapables (index exact reçu)',
    (tester) async {
      final tapped = <int>[];
      await _pumpFan(
        tester,
        count: 22,
        selectionNumberFor: (i) => _posOf(tapped, i),
        onTap: tapped.add,
      );
      for (final i in const [0, 1, 5, 10, 15, 20, 21]) {
        tapped.clear();
        await tester.tap(find.byKey(ValueKey('tarot-back-$i')));
        await tester.pump();
        expect(tapped, [i], reason: 'tap sur la carte $i');
      }
    },
  );

  testWidgets(
    'pastille de rang 1/2/3, ordre des taps conservé, doublon et 4e tap ignorés',
    (tester) async {
      final key = GlobalKey<_FanHarnessState>();
      await tester.pumpWidget(_FanHarness(key: key));

      for (final i in const [14, 4, 9]) {
        await tester.tap(find.byKey(ValueKey('tarot-back-$i')));
        await tester.pumpAndSettle();
      }
      // doublon puis 4e carte : tous deux ignorés (plafond de 3).
      await tester.tap(find.byKey(const ValueKey('tarot-back-14')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tarot-back-1')));
      await tester.pumpAndSettle();

      expect(key.currentState!.selected, [14, 4, 9]);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets('enabled:false -> les taps sont ignorés', (tester) async {
    var taps = 0;
    await _pumpFan(tester, count: 22, enabled: false, onTap: (_) => taps++);
    await tester.tap(find.byKey(const ValueKey('tarot-back-0')));
    await tester.tap(find.byKey(const ValueKey('tarot-back-21')));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('responsive 320 / 375 / 430 dp : 22 dos, aucun débordement', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1.0;
    for (final width in const [320.0, 375.0, 430.0]) {
      tester.view.physicalSize = Size(width, 800);
      await _pumpFan(tester, count: 22);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'largeur $width dp');
      for (var i = 0; i < 22; i++) {
        expect(find.byKey(ValueKey('tarot-back-$i')), findsOneWidget);
      }
    }
  });
}

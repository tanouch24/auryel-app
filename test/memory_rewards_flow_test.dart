import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/memory_api.dart';
import 'package:auryel/data/memory_game.dart';
import 'package:auryel/data/memory_stats.dart';
import 'package:auryel/screens/jeu_auryel_screen.dart';
import 'package:auryel/state/memory_rewards_controller.dart';

const _base = 'http://test.local';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Serveur factice : start renvoie toujours un game_id ; complete et progress
/// sont pilotés par [onComplete] / [progressBody].
class _FakeServer {
  _FakeServer({this.progressBody});

  Map<String, dynamic>? progressBody;
  Map<String, dynamic> Function(String difficultySeen)? onComplete;
  int completeCalls = 0;
  int startCalls = 0;
  String? lastStartDifficulty;

  MemoryApi get api => MemoryApi(
        ApiClient(
          baseUrl: _base,
          httpClient: MockClient((req) async {
            if (req.url.path.endsWith('/start')) {
              startCalls++;
              final b = jsonDecode(req.body) as Map<String, dynamic>;
              lastStartDifficulty = b['difficulty'] as String?;
              return _json({
                'game_id': 'game-$startCalls',
                'difficulty': b['difficulty'],
                'threshold_seconds': 20,
                'stars_reward': 15,
                'pair_count': 4,
              });
            }
            if (req.url.path.endsWith('/complete')) {
              completeCalls++;
              final fn = onComplete;
              if (fn == null) return _json(const {'error': 'x'}, 503);
              return _json(fn(lastStartDifficulty ?? 'easy'));
            }
            return _json(progressBody ??
                const {
                  'eligible_today': true,
                  'stars_reward': 15,
                  'difficulties': [],
                });
          }),
        ),
      );
}

Widget _host(MemoryRewardsController controller, {MemoryStats? stats}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: JeuAuryelScreen(
            random: Random(7),
            stats: stats,
            rewardsController: controller,
            resolveDelay: Duration.zero,
            enableTicker: false,
          ),
        ),
      ),
    );

MemoryRewardsController _controller(_FakeServer s) =>
    MemoryRewardsController(api: s.api, tokenProvider: () async => 'tok');

dynamic _state(WidgetTester t) => t.state(find.byType(JeuAuryelScreen));

Future<void> _startLevel(WidgetTester t, String label) async {
  await t.tap(find.widgetWithText(InkWell, label).first);
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(InkWell, 'Commencer').first);
  await t.pumpAndSettle();
}

/// Gagne la partie EN COURS en pilotant le moteur de jeu directement
/// (`MemoryGame.flip`) : l'écran écoute le moteur exactement comme sur un tap
/// réel, donc `_recordResult` + `_finalizeReward` s'enchaînent pareil. Le
/// câblage tap -> flip est couvert par `jeu_auryel_test.dart`.
Future<void> _winCurrentGame(WidgetTester t) async {
  final MemoryGame game = _state(t).debugGame;
  final byPair = <String, List<int>>{};
  for (final c in game.cards) {
    byPair.putIfAbsent(c.pairKey, () => <int>[]).add(c.slotId);
  }
  for (final slots in byPair.values) {
    game.flip(slots[0]);
    game.flip(slots[1]);
  }
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('start appelle le serveur avec la bonne difficulté', (t) async {
    final s = _FakeServer()..onComplete = (_) => {'status': 'completed'};
    await t.pumpWidget(_host(_controller(s)));
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');
    expect(s.startCalls, 1);
    expect(s.lastStartDifficulty, 'easy');
  });

  testWidgets('victoire sous le seuil -> « Bravo » + Étoiles gagnées', (t) async {
    final s = _FakeServer()
      ..onComplete = (_) => {
            'status': 'completed',
            'difficulty': 'easy',
            'elapsed_seconds': 12,
            'reward_credited': true,
            'stars_awarded': 15,
            'stars_reward': 15,
            'outcome': 'rewarded',
          };
    await t.pumpWidget(_host(_controller(s)));
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');
    await _winCurrentGame(t);

    expect(s.completeCalls, 1);
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Tu as gagné 15 ⭐.'), findsOneWidget);
    expect(find.textContaining('solde d’Étoiles a été mis à jour'),
        findsOneWidget);
    expect(find.text('Rejouer'), findsOneWidget);
    expect(find.text('Changer de niveau'), findsOneWidget);
    // Pas de vocabulaire casino / jackpot.
    expect(find.textContaining('jackpot'), findsNothing);
    expect(find.textContaining('€'), findsNothing);
  });

  testWidgets('victoire trop lente -> message seuil, aucune promesse tenue',
      (t) async {
    final s = _FakeServer()
      ..onComplete = (_) => {
            'status': 'completed',
            'difficulty': 'easy',
            'elapsed_seconds': 30,
            'reward_credited': false,
            'stars_awarded': 0,
            'stars_reward': 15,
            'outcome': 'time_limit_exceeded',
          };
    await t.pumpWidget(_host(_controller(s)));
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');
    await _winCurrentGame(t);

    expect(find.text('Partie terminée'), findsOneWidget);
    expect(
      find.text('Termine en moins de 20 secondes pour gagner 15 ⭐.'),
      findsOneWidget,
    );
    expect(find.text('Rejouer'), findsOneWidget);
  });

  testWidgets(
      'récompense déjà obtenue aujourd’hui -> message, aucun cooldown 7 j',
      (t) async {
    final s = _FakeServer()
      ..onComplete = (_) => {
            'status': 'completed',
            'difficulty': 'easy',
            'reward_credited': false,
            'stars_awarded': 0,
            'stars_reward': 15,
            'outcome': 'daily_limit_reached',
          };
    await t.pumpWidget(_host(_controller(s)));
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');
    await _winCurrentGame(t);

    expect(find.text('Partie terminée'), findsOneWidget);
    expect(find.text('Tu as déjà obtenu la récompense mini-jeu du jour.'),
        findsOneWidget);
    expect(find.text('Reviens demain pour une nouvelle récompense.'),
        findsOneWidget);
  });

  testWidgets('échec réseau sur complete -> fin neutre, jeu rejouable',
      (t) async {
    final s = _FakeServer(); // onComplete null -> 503
    await t.pumpWidget(_host(_controller(s)));
    await t.pumpAndSettle();
    await _startLevel(t, 'Facile');
    await _winCurrentGame(t);

    expect(find.text('Partie terminée'), findsOneWidget);
    expect(find.textContaining('n’a pas pu être validée'), findsOneWidget);
    expect(find.text('Rejouer'), findsOneWidget);

    await t.tap(find.text('Rejouer'));
    await t.pumpAndSettle();
    expect(_state(t).debugGame.isWon, isFalse);
  });

  testWidgets(
      'menu : seuils 20/40/80 + Étoiles PARTAGÉES + niveau non éligible marqué',
      (t) async {
    final future = DateTime.now().add(const Duration(days: 1));
    final s = _FakeServer(
      progressBody: {
        'eligible_today': false,
        'stars_reward': 15,
        'next_reset_at': future.toIso8601String(),
        'difficulties': [
          {'difficulty': 'easy', 'threshold_seconds': 20, 'pair_count': 4},
          {'difficulty': 'medium', 'threshold_seconds': 40, 'pair_count': 6},
          {'difficulty': 'hard', 'threshold_seconds': 80, 'pair_count': 8},
        ],
      },
    );
    await t.pumpWidget(_host(_controller(s)));
    await t.pumpAndSettle();

    expect(find.text('Moins de 20 sec · +15 ⭐'), findsOneWidget);
    expect(find.text('Moins de 40 sec · +15 ⭐'), findsOneWidget);
    expect(find.text('Moins de 80 sec · +15 ⭐'), findsOneWidget);
    // Plafond PARTAGÉ : les 3 niveaux affichent le MÊME statut verrouillé.
    expect(find.textContaining('Récompense déjà obtenue'), findsNWidgets(3));
    // Le niveau reste jouable malgré le plafond du jour.
    await _startLevel(t, 'Facile');
    expect(_state(t).debugGame.hasStarted, isTrue);
  });

  for (final w in const [360.0, 384.0, 430.0]) {
    testWidgets('menu récompenses sans overflow à ${w.toInt()} dp', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 900);
      addTearDown(t.view.reset);

      final s = _FakeServer(progressBody: {
        'eligible_today': false,
        'stars_reward': 15,
        'next_reset_at':
            DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        'difficulties': [
          {'difficulty': 'easy', 'threshold_seconds': 20, 'pair_count': 4},
          {'difficulty': 'medium', 'threshold_seconds': 40, 'pair_count': 6},
          {'difficulty': 'hard', 'threshold_seconds': 80, 'pair_count': 8},
        ],
      });
      await t.pumpWidget(_host(_controller(s)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '${w.toInt()} dp');
    });
  }
}

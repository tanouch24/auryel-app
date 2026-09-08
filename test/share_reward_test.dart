import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/data/daily_share_tracker.dart';
import 'package:auryel/data/daily_thought.dart';
import 'package:auryel/data/share_reward_repository.dart';
import 'package:auryel/widgets/daily_message_sheet.dart';

// ===========================================================================
// PARTIE L — PROGRESSION PARTAGE 30 JOURS, SERVEUR-AUTORITATIVE
// ===========================================================================

final _thought = DailyThought(
  id: 1,
  publishDate: DateTime(2026, 9, 4),
  phrase: 'x',
  interpretation: 'y',
  imageAsset: 'assets/pensees/publications/01_2026-09-04.webp',
);

class _FakeBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      Uint8List.fromList(const [1, 2, 3]).buffer.asByteData();
  @override
  Future<String> loadString(String key, {bool cache = true}) async => '[]';
}

Future<void> _noopShare({Uint8List? imageBytes, required String text}) async {}

http.Response _json(Map<String, dynamic> b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

/// [postResponses] : réponses successives de POST /api/app/rewards/daily-share.
/// [getResponse] : réponse de GET /api/app/rewards/share-progress (ou null=503).
ShareRewardRepository _repo({
  List<Map<String, dynamic>?>? postResponses,
  Map<String, dynamic>? getResponse,
  bool available = true,
}) {
  final posts = List<Map<String, dynamic>?>.from(postResponses ?? const []);
  final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/app/rewards/share-progress') {
        return getResponse == null ? _json({}, 503) : _json(getResponse);
      }
      if (req.url.path == '/api/app/rewards/daily-share') {
        if (posts.isEmpty) return _json({}, 503);
        final next = posts.removeAt(0);
        return next == null ? _json({}, 503) : _json(next);
      }
      return _json({}, 404);
    }),
    baseUrl: 'http://test.local',
  );
  return ShareRewardRepository(
    api: available ? RewardsApi(client) : null,
    tokenProvider: () async => 'tok',
  );
}

Widget _host({
  required ShareRewardRepository reward,
  VoidCallback? onRewardCredited,
  DailyShareTracker? tracker,
}) => MaterialApp(
  home: Scaffold(
    body: DailyMessageSheet(
      thought: _thought,
      onShare: _noopShare,
      tracker: tracker ?? DailyShareTracker(),
      bundle: _FakeBundle(),
      shareReward: reward,
      onRewardCredited: onRewardCredited,
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('L20/L21 — partager appelle le repository récompense et affiche '
      'la progression serveur', (t) async {
    final reward = _repo(
      postResponses: [
        {'count': 12, 'target': 30, 'credited': false, 'credited_seconds': 0},
      ],
    );
    await t.pumpWidget(_host(reward: reward));
    await t.pumpAndSettle();

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();

    expect(
      find.text('Partage avec l’application de ton choix. 12 / 30 jours.'),
      findsOneWidget,
    );
  });

  testWidgets('L22 — le count serveur prévaut sur le cache local', (t) async {
    // cache local = 3 jours ; serveur dira 12 -> l\'UI montre 12.
    SharedPreferences.setMockInitialValues({
      'auryel.daily_share.days': ['a', 'b', 'c'],
    });
    final reward = _repo(
      postResponses: [
        {'count': 12, 'target': 30, 'credited': false},
      ],
    );
    await t.pumpWidget(_host(reward: reward));
    await t.pumpAndSettle();
    // avant partage : cache local visible
    expect(find.textContaining('3 / 30 jours'), findsOneWidget);

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    expect(find.textContaining('12 / 30 jours'), findsOneWidget);
    expect(find.textContaining('3 / 30 jours'), findsNothing);
  });

  testWidgets('L23/L26 — credited=false : AUCUN message d\'heure, '
      'onRewardCredited PAS appelé', (t) async {
    var refreshCalls = 0;
    final reward = _repo(
      postResponses: [
        {'count': 20, 'target': 30, 'credited': false, 'credited_seconds': 0},
      ],
    );
    await t.pumpWidget(
      _host(reward: reward, onRewardCredited: () => refreshCalls++),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();

    expect(find.textContaining('1 heure de consultation'), findsNothing);
    expect(refreshCalls, 0);
    // aucune clé de crédit/secondes écrite par la feuille
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().any(
        (k) =>
            k.contains('seconds') ||
            k.contains('credit') ||
            k.contains('available') ||
            k.contains('reward'),
      ),
      isFalse,
    );
  });

  testWidgets('L24/L25 — credited=true : message « 1 heure… » + '
      'onRewardCredited (refresh portefeuille) appelé UNE fois', (t) async {
    var refreshCalls = 0;
    final reward = _repo(
      postResponses: [
        {'count': 30, 'target': 30, 'credited': true, 'credited_seconds': 3600},
      ],
    );
    await t.pumpWidget(
      _host(reward: reward, onRewardCredited: () => refreshCalls++),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();

    expect(
      find.textContaining(
        'Bravo ! 1 heure de consultation vient d’être ajoutée à ton compte.',
      ),
      findsOneWidget,
    );
    expect(refreshCalls, 1);
  });

  testWidgets('L27 — backend indisponible : le partage fonctionne, aucune '
      'progression serveur inventée (repli cache local)', (t) async {
    SharedPreferences.setMockInitialValues({
      'auryel.daily_share.days': ['a', 'b'],
    });
    final reward = _repo(postResponses: [null]); // 503
    await t.pumpWidget(_host(reward: reward));
    await t.pumpAndSettle();

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // cache local incrémenté à 3, aucune valeur serveur affichée
    expect(find.textContaining('3 / 30 jours'), findsOneWidget);
  });

  testWidgets('L28 — deux partages : la progression UI suit le serveur, '
      'pas de double comptage local', (t) async {
    final reward = _repo(
      postResponses: [
        {'count': 5, 'target': 30, 'credited': false},
        {'count': 5, 'target': 30, 'credited': false},
      ],
    );
    await t.pumpWidget(_host(reward: reward));
    await t.pumpAndSettle();

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    expect(find.textContaining('5 / 30 jours'), findsOneWidget);

    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    // le serveur renvoie toujours 5 -> l\'UI reste à 5 (pas 6, pas 10).
    expect(find.textContaining('5 / 30 jours'), findsOneWidget);
  });

  testWidgets('L-repo — repository non câblé : recordShare() -> null, '
      'la feuille retombe sur le cache local', (t) async {
    final reward = _repo(available: false);
    await t.pumpWidget(_host(reward: reward));
    await t.pumpAndSettle();
    await t.tap(find.text('Partager'));
    await t.pumpAndSettle();
    expect(find.textContaining('1 / 30 jours'), findsOneWidget);
  });
}

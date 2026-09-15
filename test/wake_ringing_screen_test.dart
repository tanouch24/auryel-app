import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/api/api_client.dart';
import 'package:auryel/api/rewards_api.dart';
import 'package:auryel/data/wake_message.dart';
import 'package:auryel/data/wake_message_catalog.dart';
import 'package:auryel/data/wake_message_selector.dart';
import 'package:auryel/screens/wake_after_screen.dart';
import 'package:auryel/screens/wake_ringing_screen.dart';
import 'package:auryel/services/wake_alarm_channel.dart';
import 'package:auryel/state/rewards_controller.dart';

class _FakeVoice implements WakeVoicePlayer {
  final List<String> calls = [];
  WakeMessage? spoken;

  @override
  Future<void> speak(WakeMessage message) async {
    spoken = message;
    calls.add('speak:${message.id}');
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

class _FakeChannel implements WakeAlarmChannel {
  final List<String> calls = [];
  int? lastSnoozeMinutes;

  @override
  Future<void> setAlarmSound(String soundId) async {}

  @override
  Future<bool> canScheduleExactAlarms() async => true;
  @override
  Future<void> requestExactAlarmPermission() async {}
  @override
  Future<bool> canUseFullScreenIntent() async => true;
  @override
  Future<void> requestFullScreenIntentPermission() async {}
  @override
  Future<bool> saveAlarm({
    required bool enabled,
    required int hour,
    required int minute,
    required List<int> days,
  }) async => true;
  @override
  Future<void> cancelAlarm() async {}
  @override
  Future<void> snoozeAlarm({int minutes = 10}) async {
    lastSnoozeMinutes = minutes;
    calls.add('snoozeAlarm');
  }

  @override
  Future<bool> consumeWakeRingingLaunch() async => false;
  @override
  Future<void> stopRinging() async => calls.add('stopRinging');
}

/// Héberge l'écran de sonnerie DERRIÈRE une page initiale, pour observer un
/// « pop » réel (Répéter/Snooze) sans dépendre d'une route racine.
Widget _hostWithBackStack({
  required _FakeVoice voice,
  required _FakeChannel channel,
  List<WakeMessage>? messagesOverride,
  WakeMessageSelector? selector,
  DateTime? now,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WakeRingingScreen(
                  voicePlayer: voice,
                  alarmChannel: channel,
                  messagesOverride: messagesOverride,
                  messageSelector: selector,
                  now: now,
                ),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('affiche l\'heure et parle le message choisi', (t) async {
    final voice = _FakeVoice();
    final channel = _FakeChannel();
    await t.pumpWidget(
      MaterialApp(
        home: WakeRingingScreen(
          voicePlayer: voice,
          alarmChannel: channel,
          messagesOverride: const [
            WakeMessage(id: 'x', text: 'Douce phrase du matin.'),
          ],
          now: DateTime(2026, 1, 1, 6, 45),
        ),
      ),
    );
    await t.pump();
    expect(find.text('06:45'), findsOneWidget);
    await t.pump(const Duration(seconds: 8));

    expect(find.text('Douce phrase du matin.'), findsOneWidget);
    expect(voice.calls, contains('speak:x'));
  });

  testWidgets(
    'sans messagesOverride ni ContentScope -> repli sur le catalogue embarqué',
    (t) async {
      final voice = _FakeVoice();
      await t.pumpWidget(
        MaterialApp(
          home: WakeRingingScreen(
            voicePlayer: voice,
            alarmChannel: _FakeChannel(),
            now: DateTime(2026, 1, 1, 7, 0),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(seconds: 8));

      expect(voice.spoken, isNotNull);
      expect(
        WakeMessageCatalog.items.map((m) => m.id),
        contains(voice.spoken!.id),
      );
    },
  );

  testWidgets(
    '« Éteindre » stoppe la voix, coupe la notif native, puis ouvre « Belle '
    'journée » (jamais une fenêtre système non bloquée)',
    (t) async {
      final voice = _FakeVoice();
      final channel = _FakeChannel();
      await t.pumpWidget(
        MaterialApp(
          home: WakeRingingScreen(
            voicePlayer: voice,
            alarmChannel: channel,
            messagesOverride: const [WakeMessage(id: 'x', text: 'x')],
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      await t.tap(find.bySemanticsLabel('Éteindre le réveil'));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      expect(voice.calls, contains('stop'));
      expect(channel.calls, contains('stopRinging'));
      expect(find.byType(WakeAfterScreen), findsOneWidget);
      expect(find.byType(WakeRingingScreen), findsNothing);
    },
  );

  testWidgets(
    '« Répéter dans 10 min » stoppe la voix, reporte l\'alarme de 10 min, '
    'puis quitte l\'écran (retour à ce qui précédait)',
    (t) async {
      final voice = _FakeVoice();
      final channel = _FakeChannel();
      await t.pumpWidget(
        _hostWithBackStack(
          voice: voice,
          channel: channel,
          messagesOverride: const [WakeMessage(id: 'x', text: 'x')],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      expect(find.byType(WakeRingingScreen), findsOneWidget);

      await t.tap(find.text('Répéter dans 10 min'));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      expect(voice.calls, contains('stop'));
      expect(channel.calls, containsAll(['stopRinging', 'snoozeAlarm']));
      expect(channel.lastSnoozeMinutes, 10);
      expect(find.byType(WakeRingingScreen), findsNothing);
    },
  );

  testWidgets('le retour système est bloqué (jamais de sortie accidentelle)', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: WakeRingingScreen(
          voicePlayer: _FakeVoice(),
          alarmChannel: _FakeChannel(),
          messagesOverride: const [WakeMessage(id: 'x', text: 'x')],
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    final popScope = t.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
  });

  testWidgets(
    'double-tap sur « Éteindre » -> une seule navigation, jamais deux',
    (t) async {
      final voice = _FakeVoice();
      final channel = _FakeChannel();
      await t.pumpWidget(
        MaterialApp(
          home: WakeRingingScreen(
            voicePlayer: voice,
            alarmChannel: channel,
            messagesOverride: const [WakeMessage(id: 'x', text: 'x')],
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      final btn = find.bySemanticsLabel('Éteindre le réveil');
      await t.tap(btn);
      await t.tap(btn, warnIfMissed: false);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }

      expect(channel.calls.where((c) => c == 'stopRinging').length, 1);
      expect(find.byType(WakeAfterScreen), findsOneWidget);
    },
  );

  // ===========================================================================
  // GROS CHANTIER AURYEL (Prompt 2/5) — ÉTOILES `wake_completed`.
  // ===========================================================================
  group('ÉTOILES wake_completed', () {
    testWidgets(
      '« Éteindre » réclame wake_completed (RewardsScope câblé) — jamais sur '
      '« Répéter »',
      (t) async {
        final hits = <String>[];
        final client = ApiClient(
          httpClient: MockClient((req) async {
            hits.add('${req.method} ${req.url.path}');
            return http.Response(
              jsonEncode({
                'awarded': true,
                'reason': null,
                'stars_awarded': 5,
                'new_balance': 5,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
          baseUrl: 'http://test.local',
        );
        final rewards = RewardsController(
          api: RewardsApi(client),
          tokenProvider: () async => 'tok',
        );
        addTearDown(rewards.dispose);
        final voice = _FakeVoice();
        final channel = _FakeChannel();

        await t.pumpWidget(
          MaterialApp(
            home: RewardsScope(
              controller: rewards,
              child: WakeRingingScreen(
                voicePlayer: voice,
                alarmChannel: channel,
                messagesOverride: const [WakeMessage(id: 'x', text: 'x')],
              ),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));

        await t.tap(find.bySemanticsLabel('Éteindre le réveil'));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 50));

        expect(
          hits,
          contains('POST /api/app/rewards/claim'),
          reason: 'extinction réelle -> claim(wake_completed) déclenché',
        );
      },
    );

    testWidgets(
      '« Répéter dans 10 min » NE réclame JAMAIS wake_completed (répéter '
      'n\'est pas terminer le réveil)',
      (t) async {
        final hits = <String>[];
        final client = ApiClient(
          httpClient: MockClient((req) async {
            hits.add('${req.method} ${req.url.path}');
            return http.Response('{}', 200);
          }),
          baseUrl: 'http://test.local',
        );
        final rewards = RewardsController(
          api: RewardsApi(client),
          tokenProvider: () async => 'tok',
        );
        addTearDown(rewards.dispose);
        final voice = _FakeVoice();
        final channel = _FakeChannel();

        await t.pumpWidget(
          RewardsScope(
            controller: rewards,
            child: _hostWithBackStack(voice: voice, channel: channel),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('ouvrir'));
        await t.pumpAndSettle();

        await t.tap(find.text('Répéter dans 10 min'));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 50));

        expect(hits, isEmpty, reason: 'jamais de claim sur un simple snooze');
      },
    );

    testWidgets(
      'sans RewardsScope câblé (tests hérités) -> « Éteindre » fonctionne '
      'quand même normalement (repli silencieux, aucun crash)',
      (t) async {
        final voice = _FakeVoice();
        final channel = _FakeChannel();
        await t.pumpWidget(
          MaterialApp(
            home: WakeRingingScreen(
              voicePlayer: voice,
              alarmChannel: channel,
              messagesOverride: const [WakeMessage(id: 'x', text: 'x')],
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));

        await t.tap(find.bySemanticsLabel('Éteindre le réveil'));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }

        expect(find.byType(WakeAfterScreen), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  });
}

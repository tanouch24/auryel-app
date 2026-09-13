import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/wake_alarm_prefs.dart';
import 'package:auryel/screens/wake_settings_screen.dart';
import 'package:auryel/services/wake_alarm_channel.dart';

class _FakeChannel implements WakeAlarmChannel {
  _FakeChannel({this.canScheduleExact = true});

  bool canScheduleExact;
  final List<String> calls = [];
  ({bool enabled, int hour, int minute, List<int> days})? lastSaved;

  @override
  Future<bool> canScheduleExactAlarms() async {
    calls.add('canScheduleExactAlarms');
    return canScheduleExact;
  }

  @override
  Future<void> requestExactAlarmPermission() async {
    calls.add('requestExactAlarmPermission');
  }

  @override
  Future<bool> canUseFullScreenIntent() async => true;

  @override
  Future<void> requestFullScreenIntentPermission() async {
    calls.add('requestFullScreenIntentPermission');
  }

  @override
  Future<bool> saveAlarm({
    required bool enabled,
    required int hour,
    required int minute,
    required List<int> days,
  }) async {
    calls.add('saveAlarm');
    lastSaved = (enabled: enabled, hour: hour, minute: minute, days: days);
    return true;
  }

  @override
  Future<void> cancelAlarm() async => calls.add('cancelAlarm');

  @override
  Future<void> snoozeAlarm({int minutes = 10}) async =>
      calls.add('snoozeAlarm');

  @override
  Future<bool> consumeWakeRingingLaunch() async => false;

  @override
  Future<void> stopRinging() async => calls.add('stopRinging');
}

Widget _host({required _FakeChannel channel, WakeAlarmPrefsStore? store}) {
  return MaterialApp(
    home: Scaffold(
      body: WakeSettingsScreen(channel: channel, prefsStore: store),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('affiche le titre, l\'explication, l\'heure par défaut 07:00', (
    t,
  ) async {
    await t.pumpWidget(_host(channel: _FakeChannel()));
    await t.pumpAndSettle();

    expect(find.text('Commence ta journée avec Auryel'), findsOneWidget);
    expect(
      find.textContaining("Choisis l'heure de ton réveil"),
      findsOneWidget,
    );
    expect(find.text('07:00'), findsOneWidget);
    expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isFalse);
  });

  testWidgets(
    'activer avec permission exacte déjà accordée -> saveAlarm appelé, '
    'switch coché',
    (t) async {
      final channel = _FakeChannel(canScheduleExact: true);
      final store = WakeAlarmPrefsStore(prefs: await SharedPreferences.getInstance());
      await t.pumpWidget(_host(channel: channel, store: store));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('wake-enabled-switch')));
      await t.pumpAndSettle();

      expect(channel.calls, contains('saveAlarm'));
      expect(channel.lastSaved!.enabled, isTrue);
      expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isTrue);
      final reloaded = await store.load();
      expect(reloaded.enabled, isTrue);
    },
  );

  testWidgets(
    'désactiver -> cancelAlarm appelé, réglage local persisté désactivé',
    (t) async {
      final channel = _FakeChannel(canScheduleExact: true);
      final store = WakeAlarmPrefsStore(prefs: await SharedPreferences.getInstance());
      await store.save(WakeAlarmSettings.defaults.copyWith(enabled: true));
      await t.pumpWidget(_host(channel: channel, store: store));
      await t.pumpAndSettle();
      expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isTrue);

      await t.tap(find.byKey(const Key('wake-enabled-switch')));
      await t.pumpAndSettle();

      expect(channel.calls, contains('cancelAlarm'));
      expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isFalse);
      expect((await store.load()).enabled, isFalse);
    },
  );

  testWidgets(
    'permission exacte MANQUANTE -> dialogue d\'autorisation, PAS de '
    'saveAlarm immédiat, switch reste décoché',
    (t) async {
      final channel = _FakeChannel(canScheduleExact: false);
      await t.pumpWidget(_host(channel: channel));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('wake-enabled-switch')));
      await t.pumpAndSettle();

      expect(find.text('Autorisation nécessaire'), findsOneWidget);
      expect(channel.calls, isNot(contains('saveAlarm')));
      expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isFalse);
    },
  );

  testWidgets(
    '« Ouvrir les réglages » demande la permission système, ne crashe jamais',
    (t) async {
      final channel = _FakeChannel(canScheduleExact: false);
      await t.pumpWidget(_host(channel: channel));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('wake-enabled-switch')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ouvrir les réglages'));
      await t.pumpAndSettle();

      expect(channel.calls, contains('requestExactAlarmPermission'));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('« Plus tard » ferme le dialogue sans rien activer', (t) async {
    final channel = _FakeChannel(canScheduleExact: false);
    await t.pumpWidget(_host(channel: channel));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('wake-enabled-switch')));
    await t.pumpAndSettle();
    await t.tap(find.text('Plus tard'));
    await t.pumpAndSettle();

    expect(find.text('Autorisation nécessaire'), findsNothing);
    expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isFalse);
  });

  testWidgets('choisir un jour le persiste dans le réglage', (t) async {
    final channel = _FakeChannel();
    final store = WakeAlarmPrefsStore(prefs: await SharedPreferences.getInstance());
    await t.pumpWidget(_host(channel: channel, store: store));
    await t.pumpAndSettle();

    await t.tap(find.text('L')); // lundi -> Calendar.DAY_OF_WEEK = 2
    await t.pumpAndSettle();

    final reloaded = await store.load();
    expect(reloaded.days, {2});
  });

  testWidgets('réglage déjà activé au chargement -> saveAlarm réarmé '
      'avec ce réglage', (t) async {
    final channel = _FakeChannel();
    final store = WakeAlarmPrefsStore(prefs: await SharedPreferences.getInstance());
    await store.save(
      const WakeAlarmSettings(enabled: true, hour: 6, minute: 15, days: {2, 3}),
    );
    await t.pumpWidget(_host(channel: channel, store: store));
    await t.pumpAndSettle();

    expect(find.text('06:15'), findsOneWidget);
    expect(t.widget<Switch>(find.byKey(const Key('wake-enabled-switch'))).value, isTrue);
  });
}

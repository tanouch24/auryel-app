import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/data/wake_video.dart';
import 'package:auryel/screens/wake_after_screen.dart';
import 'package:auryel/screens/wake_ringing_screen.dart';
import 'package:auryel/services/wake_alarm_channel.dart';

class _FakeChannel implements WakeAlarmChannel {
  final calls = <String>[];
  int? snoozeMinutes;

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
    snoozeMinutes = minutes;
    calls.add('snooze');
  }

  @override
  Future<bool> consumeWakeRingingLaunch() async => false;
  @override
  Future<void> stopRinging() async => calls.add('stop');
}

WakeVideoCache _cache() {
  final directory = Directory.systemTemp.createTempSync('auryel-wake-test-');
  addTearDown(() => directory.delete(recursive: true));
  return WakeVideoCache(directory: directory);
}

void main() {
  testWidgets('mode test affiche Éteindre et ne propose pas de snooze', (
    t,
  ) async {
    final channel = _FakeChannel();
    await t.pumpWidget(
      MaterialApp(
        home: WakeRingingScreen(
          testMode: true,
          now: DateTime(2026, 1, 1, 6, 45),
          alarmChannel: channel,
          cache: _cache(),
        ),
      ),
    );
    await t.pump();
    expect(find.text('06:45'), findsOneWidget);
    expect(find.text('Éteindre'), findsOneWidget);
    expect(find.text('Répéter dans 10 min'), findsNothing);
  });

  testWidgets('Éteindre est exposé sur le mode alarme', (t) async {
    final channel = _FakeChannel();
    await t.pumpWidget(
      MaterialApp(
        home: WakeRingingScreen(alarmChannel: channel, cache: _cache()),
      ),
    );
    await t.pump();
    expect(find.bySemanticsLabel('Éteindre le réveil'), findsOneWidget);
    expect(find.byType(WakeAfterScreen), findsNothing);
  });

  testWidgets('Snooze réel est exposé hors mode test', (t) async {
    final channel = _FakeChannel();
    await t.pumpWidget(
      MaterialApp(
        home: WakeRingingScreen(alarmChannel: channel, cache: _cache()),
      ),
    );
    await t.pump();
    expect(find.text('Répéter dans 10 min'), findsOneWidget);
    expect(channel.snoozeMinutes, isNull);
  });
}

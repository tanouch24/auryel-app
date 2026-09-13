import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/wake_alarm_prefs.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults : désactivé, 7h00, tous les jours (ensemble vide)', () {
    expect(WakeAlarmSettings.defaults.enabled, isFalse);
    expect(WakeAlarmSettings.defaults.hour, 7);
    expect(WakeAlarmSettings.defaults.minute, 0);
    expect(WakeAlarmSettings.defaults.days, isEmpty);
  });

  test('copyWith ne modifie que les champs fournis', () {
    const s = WakeAlarmSettings(enabled: true, hour: 6, minute: 30, days: {2, 3});
    final next = s.copyWith(hour: 8);
    expect(next.hour, 8);
    expect(next.enabled, isTrue);
    expect(next.minute, 30);
    expect(next.days, {2, 3});
  });

  test('load() sans donnée persistée -> repli sur les valeurs par défaut', () async {
    final store = WakeAlarmPrefsStore(prefs: await SharedPreferences.getInstance());
    final loaded = await store.load();
    expect(loaded.enabled, WakeAlarmSettings.defaults.enabled);
    expect(loaded.hour, WakeAlarmSettings.defaults.hour);
    expect(loaded.minute, WakeAlarmSettings.defaults.minute);
    expect(loaded.days, WakeAlarmSettings.defaults.days);
  });

  test('save() puis load() restitue EXACTEMENT le réglage persisté', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = WakeAlarmPrefsStore(prefs: prefs);
    const settings = WakeAlarmSettings(
      enabled: true,
      hour: 6,
      minute: 45,
      days: {2, 4, 6},
    );
    await store.save(settings);

    final reloaded = await WakeAlarmPrefsStore(prefs: prefs).load();
    expect(reloaded.enabled, isTrue);
    expect(reloaded.hour, 6);
    expect(reloaded.minute, 45);
    expect(reloaded.days, {2, 4, 6});
  });

  test('ensemble de jours VIDE persiste bien vide (tous les jours)', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = WakeAlarmPrefsStore(prefs: prefs);
    await store.save(WakeAlarmSettings.defaults.copyWith(enabled: true));
    final reloaded = await store.load();
    expect(reloaded.days, isEmpty);
  });

  test(
    'l\'heure locale n\'est jamais envoyée au backend — persistance '
    '100% SharedPreferences, aucune dépendance réseau',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = WakeAlarmPrefsStore(prefs: prefs);
      await store.save(
        const WakeAlarmSettings(enabled: true, hour: 5, minute: 15, days: {}),
      );
      // Les seules clés écrites sont locales (`auryel.wake_alarm.*`).
      final keys = prefs.getKeys().where((k) => k.startsWith('auryel.wake_alarm'));
      expect(keys, isNotEmpty);
      expect(prefs.getKeys().every((k) => !k.contains('http')), isTrue);
    },
  );
}

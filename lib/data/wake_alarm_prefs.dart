import 'package:shared_preferences/shared_preferences.dart';

/// Réglage LOCAL du Réveil Auryel — l'heure choisie n'a aucune nécessité
/// backend réelle (cf. « Données / confidentialité » du lot), elle reste sur
/// l'appareil uniquement (SharedPreferences), jamais envoyée au serveur.
///
/// Jours : convention `Calendar.DAY_OF_WEEK` d'Android (1 = dimanche ...
/// 7 = samedi), pour rester directement compatible avec le code natif
/// (`AlarmScheduler.kt`) qui recalcule la même chose de son côté après un
/// redémarrage. Ensemble VIDE = tous les jours.
class WakeAlarmSettings {
  const WakeAlarmSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
    required this.days,
  });

  final bool enabled;
  final int hour;
  final int minute;

  /// `Calendar.DAY_OF_WEEK` (1=dimanche..7=samedi). Vide -> tous les jours.
  final Set<int> days;

  static const WakeAlarmSettings defaults = WakeAlarmSettings(
    enabled: false,
    hour: 7,
    minute: 0,
    days: {},
  );

  WakeAlarmSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? days,
  }) => WakeAlarmSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
  );
}

/// Persistance locale des réglages du Réveil Auryel.
class WakeAlarmPrefsStore {
  WakeAlarmPrefsStore({SharedPreferences? prefs}) : _injected = prefs;

  static const String _enabledKey = 'auryel.wake_alarm.enabled';
  static const String _hourKey = 'auryel.wake_alarm.hour';
  static const String _minuteKey = 'auryel.wake_alarm.minute';
  static const String _daysKey = 'auryel.wake_alarm.days';

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  Future<WakeAlarmSettings> load() async {
    try {
      final p = await _prefs;
      final days = p
          .getStringList(_daysKey)
          ?.map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();
      return WakeAlarmSettings(
        enabled: p.getBool(_enabledKey) ?? WakeAlarmSettings.defaults.enabled,
        hour: p.getInt(_hourKey) ?? WakeAlarmSettings.defaults.hour,
        minute: p.getInt(_minuteKey) ?? WakeAlarmSettings.defaults.minute,
        days: days ?? WakeAlarmSettings.defaults.days,
      );
    } catch (_) {
      return WakeAlarmSettings.defaults;
    }
  }

  Future<void> save(WakeAlarmSettings settings) async {
    try {
      final p = await _prefs;
      await p.setBool(_enabledKey, settings.enabled);
      await p.setInt(_hourKey, settings.hour);
      await p.setInt(_minuteKey, settings.minute);
      await p.setStringList(
        _daysKey,
        settings.days.map((d) => d.toString()).toList(),
      );
    } catch (_) {
      /* réglage local best-effort — le natif reste la source d'exécution */
    }
  }
}

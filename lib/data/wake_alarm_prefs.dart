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
    this.soundId = kDefaultWakeSoundId,
    this.wakeVideoId,
    this.wakeVideoUrl,
    this.wakeVideoTitle,
    this.wakeTargetDate,
  });

  final bool enabled;
  final int hour;
  final int minute;

  /// `Calendar.DAY_OF_WEEK` (1=dimanche..7=samedi). Vide -> tous les jours.
  final Set<int> days;
  final String soundId;
  final String? wakeVideoId;
  final String? wakeVideoUrl;
  final String? wakeVideoTitle;
  final String? wakeTargetDate;

  static const WakeAlarmSettings defaults = WakeAlarmSettings(
    enabled: false,
    hour: 7,
    minute: 0,
    days: {},
    soundId: kDefaultWakeSoundId,
  );

  WakeAlarmSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    Set<int>? days,
    String? soundId,
    String? wakeVideoId,
    String? wakeVideoUrl,
    String? wakeVideoTitle,
    String? wakeTargetDate,
  }) => WakeAlarmSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    soundId: soundId ?? this.soundId,
    wakeVideoId: wakeVideoId ?? this.wakeVideoId,
    wakeVideoUrl: wakeVideoUrl ?? this.wakeVideoUrl,
    wakeVideoTitle: wakeVideoTitle ?? this.wakeVideoTitle,
    wakeTargetDate: wakeTargetDate ?? this.wakeTargetDate,
  );
}

const String kDefaultWakeSoundId = 'freesound_community-wake-up-33353';

/// Persistance locale des réglages du Réveil Auryel.
class WakeAlarmPrefsStore {
  WakeAlarmPrefsStore({SharedPreferences? prefs}) : _injected = prefs;

  static const String _enabledKey = 'auryel.wake_alarm.enabled';
  static const String _hourKey = 'auryel.wake_alarm.hour';
  static const String _minuteKey = 'auryel.wake_alarm.minute';
  static const String _daysKey = 'auryel.wake_alarm.days';
  static const String _soundKey = 'auryel.wake_alarm.sound';
  static const String _wakeVideoIdKey = 'auryel.wake_alarm.video_id';
  static const String _wakeVideoUrlKey = 'auryel.wake_alarm.video_url';
  static const String _wakeVideoTitleKey = 'auryel.wake_alarm.video_title';
  static const String _wakeTargetDateKey = 'auryel.wake_alarm.target_date';

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
        soundId: p.getString(_soundKey) ?? kDefaultWakeSoundId,
        wakeVideoId: p.getString(_wakeVideoIdKey),
        wakeVideoUrl: p.getString(_wakeVideoUrlKey),
        wakeVideoTitle: p.getString(_wakeVideoTitleKey),
        wakeTargetDate: p.getString(_wakeTargetDateKey),
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
      await p.setString(_soundKey, settings.soundId);
      await _setNullable(p, _wakeVideoIdKey, settings.wakeVideoId);
      await _setNullable(p, _wakeVideoUrlKey, settings.wakeVideoUrl);
      await _setNullable(p, _wakeVideoTitleKey, settings.wakeVideoTitle);
      await _setNullable(p, _wakeTargetDateKey, settings.wakeTargetDate);
    } catch (_) {
      /* réglage local best-effort — le natif reste la source d'exécution */
    }
  }

  Future<void> _setNullable(
    SharedPreferences p,
    String key,
    String? value,
  ) async {
    if (value == null || value.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, value);
    }
  }
}

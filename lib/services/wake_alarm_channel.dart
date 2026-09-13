import 'package:flutter/services.dart';

/// Pont natif du Réveil Auryel (`MainActivity.kt` / `AlarmScheduler.kt`) —
/// interface abstraite pour rester testable en `flutter_test` (aucun canal
/// de plateforme réel en test). Toute méthode est best-effort : un échec de
/// canal ne doit jamais faire planter l'app ni bloquer les réglages.
abstract class WakeAlarmChannel {
  /// `true` si l'app peut programmer une alarme EXACTE. Toujours `true` avant
  /// Android 12 (permission spéciale inexistante).
  Future<bool> canScheduleExactAlarms();

  /// Ouvre le réglage système spécial « Alarmes et rappels »
  /// (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`). Sans effet avant Android 12.
  Future<void> requestExactAlarmPermission();

  /// `true` si l'app peut poster une notification plein écran (toujours
  /// `true` avant Android 14, vérifié nativement à partir de la 14).
  Future<bool> canUseFullScreenIntent();

  /// Ouvre le réglage système de la permission plein écran (Android 14+).
  Future<void> requestFullScreenIntentPermission();

  /// Enregistre le réglage ET (ré)arme l'alarme si `enabled`. Renvoie `false`
  /// si l'alarme exacte n'a pas pu être programmée (permission manquante) —
  /// le réglage lui-même reste enregistré côté natif dans ce cas.
  Future<bool> saveAlarm({
    required bool enabled,
    required int hour,
    required int minute,
    required List<int> days,
  });

  Future<void> cancelAlarm();

  /// Répète dans [minutes] minutes (défaut 10), sans modifier le réglage
  /// récurrent normal.
  Future<void> snoozeAlarm({int minutes = 10});

  /// `true` UNE SEULE FOIS si cette ouverture de l'app vient du déclenchement
  /// du réveil (consommé au premier appel : un second appel renvoie `false`
  /// tant qu'une nouvelle sonnerie n'a pas eu lieu).
  Future<bool> consumeWakeRingingLaunch();

  /// Efface la notification plein écran active (si l'utilisateur éteint
  /// depuis l'écran de sonnerie sans avoir tapé la notification elle-même).
  Future<void> stopRinging();
}

/// Implémentation réelle — `MethodChannel("auryel/wake_alarm")`.
class MethodChannelWakeAlarm implements WakeAlarmChannel {
  MethodChannelWakeAlarm({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('auryel/wake_alarm');

  final MethodChannel _channel;

  @override
  Future<bool> canScheduleExactAlarms() async {
    try {
      return (await _channel.invokeMethod<bool>('canScheduleExactAlarms')) ??
          true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> requestExactAlarmPermission() async {
    try {
      await _channel.invokeMethod('requestExactAlarmPermission');
    } catch (_) {
      /* jamais bloquant */
    }
  }

  @override
  Future<bool> canUseFullScreenIntent() async {
    try {
      return (await _channel.invokeMethod<bool>('canUseFullScreenIntent')) ??
          true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> requestFullScreenIntentPermission() async {
    try {
      await _channel.invokeMethod('requestFullScreenIntentPermission');
    } catch (_) {
      /* jamais bloquant */
    }
  }

  @override
  Future<bool> saveAlarm({
    required bool enabled,
    required int hour,
    required int minute,
    required List<int> days,
  }) async {
    try {
      return (await _channel.invokeMethod<bool>('saveAlarm', {
            'enabled': enabled,
            'hour': hour,
            'minute': minute,
            'days': days,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancelAlarm() async {
    try {
      await _channel.invokeMethod('cancelAlarm');
    } catch (_) {
      /* jamais bloquant */
    }
  }

  @override
  Future<void> snoozeAlarm({int minutes = 10}) async {
    try {
      await _channel.invokeMethod('snoozeAlarm', {'minutes': minutes});
    } catch (_) {
      /* jamais bloquant */
    }
  }

  @override
  Future<bool> consumeWakeRingingLaunch() async {
    try {
      return (await _channel.invokeMethod<bool>(
            'consumeWakeRingingLaunch',
          )) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stopRinging() async {
    try {
      await _channel.invokeMethod('stopRinging');
    } catch (_) {
      /* jamais bloquant */
    }
  }
}

package com.auryel.auryel

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Réveil Auryel — programmation de l'alarme exacte, côté natif.
 *
 * Autonome par rapport à Dart : les préférences (activé, heure, minute,
 * jours) sont dupliquées ici dans un fichier SharedPreferences NATIF dédié
 * ("auryel_wake_alarm", distinct de FlutterSharedPreferences) écrit UNIQUEMENT
 * par [MainActivity] (méthode `scheduleExactAlarm`/`cancelExactAlarm` du
 * MethodChannel). [WakeBootReceiver] relit ces mêmes préférences pour
 * reprogrammer l'alarme après un redémarrage, SANS dépendre d'un moteur
 * Flutter démarré à ce moment-là.
 *
 * SCHEDULE_EXACT_ALARM (jamais USE_EXACT_ALARM) : `setExactAndAllowWhileIdle`
 * fonctionne même en Doze. Aucune alarme n'est programmée si la permission
 * n'est pas accordée (vérifiée côté Dart avant tout appel ici).
 */
object AlarmScheduler {
    private const val PREFS = "auryel_wake_alarm"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_DAYS = "days" // Set<String> de Calendar.DAY_OF_WEEK (1=dimanche..7=samedi)
    private const val KEY_SOUND = "sound"
    private const val KEY_SNOOZE_EPOCH = "snooze_epoch_millis"
    const val EXTRA_WAKE_RINGING = "auryel.wake_ringing"
    const val DEFAULT_SOUND = "wake_freesound_community_wake_up_33353"

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun alarmManager(ctx: Context) =
        ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pendingIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, WakeAlarmReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, 1001, intent, flags)
    }

    /** `true` si l'app peut programmer une alarme EXACTE (toujours `true`
     * avant Android 12 : la permission spéciale n'existait pas). */
    fun canScheduleExactAlarms(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return alarmManager(ctx).canScheduleExactAlarms()
    }

    /** Enregistre le réglage (activé, heure, minute, jours) ET (ré)arme
     * l'alarme si activé. Renvoie `false` sans planifier si la permission
     * d'alarme exacte manque (l'appelant Dart doit alors guider l'utilisateur
     * vers le réglage spécial avant de réessayer). */
    fun save(ctx: Context, enabled: Boolean, hour: Int, minute: Int, days: Set<Int>): Boolean {
        prefs(ctx).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .putStringSet(KEY_DAYS, days.map { it.toString() }.toSet())
            .remove(KEY_SNOOZE_EPOCH)
            .apply()
        if (!enabled) {
            cancelSystemAlarm(ctx)
            return true
        }
        if (!canScheduleExactAlarms(ctx)) return false
        armNext(ctx)
        return true
    }

    fun cancel(ctx: Context) {
        prefs(ctx).edit().putBoolean(KEY_ENABLED, false).remove(KEY_SNOOZE_EPOCH).apply()
        cancelSystemAlarm(ctx)
    }

    fun setSound(ctx: Context, soundId: String) {
        prefs(ctx).edit().putString(KEY_SOUND, soundId).apply()
    }

    fun soundResourceName(ctx: Context): String =
        prefs(ctx).getString(KEY_SOUND, DEFAULT_SOUND) ?: DEFAULT_SOUND

    private fun cancelSystemAlarm(ctx: Context) {
        try {
            alarmManager(ctx).cancel(pendingIntent(ctx))
        } catch (_: Exception) {
            /* jamais bloquant */
        }
    }

    /** Répète dans [minutes] minutes (défaut 10) — UNE seule fois, sans
     * modifier le réglage récurrent normal (jours/heure). */
    fun snooze(ctx: Context, minutes: Int = 10) {
        val p = prefs(ctx)
        if (!p.getBoolean(KEY_ENABLED, false)) return
        val epoch = System.currentTimeMillis() + minutes * 60_000L
        p.edit().putLong(KEY_SNOOZE_EPOCH, epoch).apply()
        armAt(ctx, epoch)
    }

    /** Recalcule et (ré)arme la PROCHAINE occurrence — utilisée après avoir
     * sonné (jour suivant), après un redémarrage, ou juste après `save()`.
     * Ne fait rien si désactivé. */
    fun armNext(ctx: Context) {
        val p = prefs(ctx)
        if (!p.getBoolean(KEY_ENABLED, false)) return
        val snoozeEpoch = p.getLong(KEY_SNOOZE_EPOCH, 0L)
        if (snoozeEpoch > System.currentTimeMillis()) {
            armAt(ctx, snoozeEpoch)
            return
        }
        p.edit().remove(KEY_SNOOZE_EPOCH).apply()
        val hour = p.getInt(KEY_HOUR, 7)
        val minute = p.getInt(KEY_MINUTE, 0)
        val days = p.getStringSet(KEY_DAYS, emptySet())!!.mapNotNull { it.toIntOrNull() }.toSet()
        val next = computeNextEpoch(hour, minute, days, Calendar.getInstance())
        armAt(ctx, next)
    }

    private fun armAt(ctx: Context, epochMillis: Long) {
        if (!canScheduleExactAlarms(ctx)) return
        try {
            alarmManager(ctx).setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, epochMillis, pendingIntent(ctx)
            )
        } catch (_: SecurityException) {
            /* permission retirée entre-temps par l'utilisateur -> jamais de crash */
        }
    }

    /** Prochain instant (epoch ms) >= maintenant correspondant à [hour]:[minute]
     * un jour de [days] (Calendar.DAY_OF_WEEK, 1=dimanche..7=samedi). [days]
     * vide -> tous les jours. Cherche au plus 8 jours en avant (jamais de
     * boucle infinie). */
    fun computeNextEpoch(hour: Int, minute: Int, days: Set<Int>, from: Calendar): Long {
        val cal = from.clone() as Calendar
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        if (cal.timeInMillis <= from.timeInMillis) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        if (days.isEmpty()) return cal.timeInMillis
        for (i in 0 until 8) {
            if (days.contains(cal.get(Calendar.DAY_OF_WEEK))) return cal.timeInMillis
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return cal.timeInMillis // repli défensif, inatteignable (days non vide <= 7 valeurs)
    }
}

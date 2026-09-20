package com.auryel.auryel

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat

/**
 * Réveil Auryel — reçoit le déclenchement exact d'AlarmManager. Poste une
 * notification PLEIN ÉCRAN (canal dédié, catégorie ALARM) : c'est le chemin
 * le plus fiable pour afficher l'écran d'alarme même téléphone verrouillé,
 * y compris sur des constructeurs stricts (Samsung). Bref réveil CPU
 * (WAKE_LOCK, quelques secondes) le temps que l'écran s'affiche réellement.
 *
 * Reprogramme IMMÉDIATEMENT l'occurrence SUIVANTE (jour suivant selon les
 * jours choisis) — comportement récurrent sans dépendre d'un
 * `setRepeating` imprécis.
 */
class WakeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "auryel:wake_alarm"
        )
        try {
            wakeLock.acquire(15_000L)
            postFullScreenAlarm(context)
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
        if (!AlarmScheduler.isSnoozeAlarm(context)) {
            AlarmScheduler.advanceWakeSnapshot(context)
        }
        // Occurrence suivante programmée tout de suite : l'alarme reste
        // récurrente même si l'utilisateur ne rouvre jamais l'app.
        AlarmScheduler.armNext(context)
    }

    private fun postFullScreenAlarm(context: Context) {
        // Le son et la vibration sont portés par le canal natif Android : ils
        // démarrent dans le receiver, même si Flutter n'est pas encore prêt.
        // Un canal distinct par son est nécessaire car Android fige le son
        // d'un NotificationChannel après sa création.
        val resourceName = AlarmScheduler.soundResourceName(context)
        val resourceId = context.resources.getIdentifier(resourceName, "raw", context.packageName)
        val channelId = "auryel_wake_alarm_$resourceName"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "Réveil Auryel", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Sonnerie du Réveil Auryel"
                setBypassDnd(false)
                if (resourceId != 0) {
                    val soundUri = Uri.parse("android.resource://${context.packageName}/$resourceId")
                    setSound(soundUri, AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                }
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 700, 500, 700, 1200)
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_WAKE_RINGING, true)
            for ((key, value) in AlarmScheduler.wakeVideoSnapshot(context)) {
                if (value != null) putExtra(key, value)
            }
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context, 1002, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_auryel)
            .setContentTitle("Réveil Auryel")
            .setContentText("C'est l'heure de commencer ta journée.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        nm.notify(1002, notification)

        // Tentative directe en complément lorsque Android l'autorise. Le
        // Full Screen Intent reste le mécanisme principal compatible écran
        // verrouillé et le canal garde un son local si l'activité est bloquée.
        try {
            context.startActivity(fullScreenIntent)
        } catch (_: Exception) {
            /* la notification plein écran suffit */
        }
    }
}

package com.auryel.auryel

import android.app.NotificationManager
import android.app.Notification
import android.app.NotificationChannel
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Réveil Auryel — pont natif MethodChannel ("auryel/wake_alarm") : la
 * programmation d'alarme EXACTE (SCHEDULE_EXACT_ALARM, jamais
 * USE_EXACT_ALARM) et l'affichage plein écran par-dessus le verrouillage
 * sont des API Android natives, hors de portée d'un plugin Dart pur.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "auryel/wake_alarm"
    private var pendingWakeRinging = false
    private var pendingWakeVideo: Map<String, String?>? = null
    private var wakeRingingChannel: MethodChannel? = null
    private val launcherBadgeChannel = "auryel_unread_badge"
    private val launcherBadgeNotificationId = 19001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyWakeRingingFlagsIfNeeded(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyWakeRingingFlagsIfNeeded(intent)
        dispatchWakeRingingIntentIfReady()
    }

    /** Affiche l'activité PAR-DESSUS l'écran verrouillé + rallume l'écran
     * quand cette ouverture vient du Réveil Auryel. Sans effet sur une
     * ouverture normale (aucune fenêtre spéciale). */
    private fun applyWakeRingingFlagsIfNeeded(intent: Intent) {
        if (!intent.getBooleanExtra(AlarmScheduler.EXTRA_WAKE_RINGING, false)) return
        pendingWakeRinging = true
        pendingWakeVideo = mapOf(
            "wakeVideoId" to intent.getStringExtra(AlarmScheduler.EXTRA_WAKE_VIDEO_ID),
            "wakeVideoUrl" to intent.getStringExtra(AlarmScheduler.EXTRA_WAKE_VIDEO_URL),
            "wakeVideoTitle" to intent.getStringExtra(AlarmScheduler.EXTRA_WAKE_VIDEO_TITLE),
            "wakeTargetDate" to intent.getStringExtra(AlarmScheduler.EXTRA_WAKE_TARGET_DATE),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    private fun dispatchWakeRingingIntentIfReady() {
        val channel = wakeRingingChannel ?: return
        if (!pendingWakeRinging) return
        channel.invokeMethod("wakeRingingIntent", pendingWakeVideo ?: emptyMap<String, String?>())
        pendingWakeRinging = false
        pendingWakeVideo = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        wakeRingingChannel = channel
        channel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                info.longVersionCode
                            } else {
                                @Suppress("DEPRECATION")
                                info.versionCode.toLong()
                            }
                            result.success("${info.versionName ?: ""}+$code")
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }

                    "syncLauncherBadge" -> {
                        syncLauncherBadge(call.argument<Int>("count") ?: 0)
                        result.success(null)
                    }

                    "setAlarmSound" -> {
                        AlarmScheduler.setSound(this, call.argument<String>("soundId") ?: AlarmScheduler.DEFAULT_SOUND)
                        result.success(null)
                    }
                    "canScheduleExactAlarms" ->
                        result.success(AlarmScheduler.canScheduleExactAlarms(this))

                    "requestExactAlarmPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                        Uri.parse("package:$packageName")
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            } catch (_: Exception) {
                                /* jamais bloquant */
                            }
                        }
                        result.success(null)
                    }

                    "canUseFullScreenIntent" -> {
                        val ok = if (Build.VERSION.SDK_INT >= 34) {
                            try {
                                val nm = getSystemService(NotificationManager::class.java)
                                nm?.canUseFullScreenIntent() ?: true
                            } catch (_: Exception) {
                                true
                            }
                        } else true
                        result.success(ok)
                    }

                    "requestFullScreenIntentPermission" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            try {
                                startActivity(
                                    Intent(
                                        "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",
                                        Uri.parse("package:$packageName")
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            } catch (_: Exception) {
                                /* jamais bloquant */
                            }
                        }
                        result.success(null)
                    }

                    "saveAlarm" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val hour = call.argument<Int>("hour") ?: 7
                        val minute = call.argument<Int>("minute") ?: 0
                        @Suppress("UNCHECKED_CAST")
                        val days = (call.argument<List<Int>>("days") ?: emptyList()).toSet()
                        result.success(AlarmScheduler.save(
                            this, enabled, hour, minute, days,
                            call.argument<String>("wakeVideoId"),
                            call.argument<String>("wakeVideoUrl"),
                            call.argument<String>("wakeVideoTitle"),
                            call.argument<String>("wakeTargetDate"),
                            call.argument<String>("wakeScheduleJson"),
                        ))
                    }

                    "cancelAlarm" -> {
                        AlarmScheduler.cancel(this)
                        result.success(null)
                    }

                    "snoozeAlarm" -> {
                        val minutes = call.argument<Int>("minutes") ?: 10
                        AlarmScheduler.snooze(this, minutes)
                        result.success(null)
                    }

                    "consumeWakeRingingLaunch" -> {
                        val was = pendingWakeRinging
                        pendingWakeRinging = false
                        result.success(was)
                    }

                    "consumeWakeRingingLaunchDetails" -> {
                        val details = if (pendingWakeRinging) pendingWakeVideo else null
                        pendingWakeRinging = false
                        pendingWakeVideo = null
                        result.success(details)
                    }

                    "stopRinging" -> {
                        try {
                            val nm = getSystemService(NotificationManager::class.java)
                            nm?.cancel(1002)
                        } catch (_: Exception) {
                            /* jamais bloquant */
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun syncLauncherBadge(count: Int) {
        try {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            if (count <= 0) {
                manager.cancel(launcherBadgeNotificationId)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    launcherBadgeChannel,
                    "Auryel — nouveautés",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setShowBadge(true)
                    description = "Indicateur des contenus Auryel non lus."
                }
                manager.createNotificationChannel(channel)
            }
            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, launcherBadgeChannel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
                .setSmallIcon(R.drawable.ic_stat_auryel)
                .setContentTitle("Auryel")
                .setContentText("Une nouveauté t'attend dans Consultation.")
                .setNumber(count)
                .setShowWhen(false)
                .setOnlyAlertOnce(true)
                .setAutoCancel(false)
                .setCategory(Notification.CATEGORY_SOCIAL)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .build()
            manager.notify(launcherBadgeNotificationId, notification)
        } catch (_: Exception) {
            // Permission refusée / launcher incompatible : badge best-effort.
        }
    }
}

package com.auryel.auryel

import android.app.NotificationManager
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyWakeRingingFlagsIfNeeded(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyWakeRingingFlagsIfNeeded(intent)
    }

    /** Affiche l'activité PAR-DESSUS l'écran verrouillé + rallume l'écran
     * quand cette ouverture vient du Réveil Auryel. Sans effet sur une
     * ouverture normale (aucune fenêtre spéciale). */
    private fun applyWakeRingingFlagsIfNeeded(intent: Intent) {
        if (!intent.getBooleanExtra(AlarmScheduler.EXTRA_WAKE_RINGING, false)) return
        pendingWakeRinging = true
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                        result.success(AlarmScheduler.save(this, enabled, hour, minute, days))
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
}

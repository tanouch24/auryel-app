package com.auryel.auryel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Réveil Auryel — reprogramme l'alarme après un redémarrage du téléphone
 * (ou une mise à jour de l'app) : AlarmManager ne survit PAS un reboot par
 * lui-même. Lit les préférences natives déjà écrites par [AlarmScheduler]
 * (jamais Dart directement) : fonctionne même si l'app n'a jamais été
 * rouverte depuis le redémarrage.
 */
class WakeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        AlarmScheduler.armNext(context)
    }
}

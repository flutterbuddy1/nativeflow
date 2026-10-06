package com.nativeflow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import org.json.JSONObject

/** Background notification action taps (no app launch). */
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RuntimeSupervisor.ensure(context)
        val id = intent.getIntExtra(NotificationPresenter.EXTRA_NOTIFICATION_ID, 0)
        RuntimeSupervisor.emitNotificationEvent(intent, isTap = false)
        if (intent.getBooleanExtra(NotificationPresenter.EXTRA_CANCEL, false)) {
            context.getSystemService(NotificationManager::class.java).cancel(id)
        }
    }

    internal companion object {
        fun payloadOf(intent: Intent): Map<String, Any?> = mapOf(
            "notificationId" to intent.getIntExtra(NotificationPresenter.EXTRA_NOTIFICATION_ID, 0),
            "actionId" to intent.getStringExtra(NotificationPresenter.EXTRA_ACTION_ID),
            "deepLink" to intent.dataString,
            "data" to intent.getStringExtra(NotificationPresenter.EXTRA_DATA)?.let {
                try { Json.toMap(JSONObject(it)) } catch (_: Exception) { null }
            },
        )
    }
}

/** Restores the runtime after reboot/app update, only if the app asked for it. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val trigger = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> RecoveryManager.Trigger.BOOT
            Intent.ACTION_MY_PACKAGE_REPLACED -> RecoveryManager.Trigger.PACKAGE_REPLACED
            else -> return
        }
        RuntimeSupervisor.ensure(context)
        RuntimeSupervisor.restoreFromSystem(trigger)
    }
}

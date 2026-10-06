package com.nativeflow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.nativeflow.capability.Status
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native notification rendering. Everything here works without Flutter:
 * taps and actions are routed through intents/receivers into the event
 * store and delivered to Dart when it is (or next becomes) available.
 */
internal class NotificationPresenter(private val context: Context) {
    private val nm = context.getSystemService(NotificationManager::class.java)

    companion object {
        const val FOREGROUND_ID = 1
        const val PRESENTATION_ID = Int.MAX_VALUE - 1
        const val RESUME_ID = Int.MAX_VALUE - 2
        const val RUNTIME_CHANNEL = "nativeflow_runtime"
        const val DEFAULT_CHANNEL = "nativeflow_default"
        const val URGENT_CHANNEL = "nativeflow_urgent"

        const val EXTRA_NOTIFICATION_ID = "dev.nativeflow.notificationId"
        const val EXTRA_ACTION_ID = "dev.nativeflow.actionId"
        const val EXTRA_DATA = "dev.nativeflow.data"
        const val EXTRA_CANCEL = "dev.nativeflow.cancel"
    }

    fun ensureDefaultChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        if (nm.getNotificationChannel(RUNTIME_CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(RUNTIME_CHANNEL, "Background activity", NotificationManager.IMPORTANCE_LOW)
            )
        }
        if (nm.getNotificationChannel(DEFAULT_CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(DEFAULT_CHANNEL, "Notifications", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        if (nm.getNotificationChannel(URGENT_CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(URGENT_CHANNEL, "Urgent", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }

    fun createChannel(spec: Map<*, *>) {
        if (Build.VERSION.SDK_INT < 26) return
        val importance = when (spec["importance"]) {
            "min" -> NotificationManager.IMPORTANCE_MIN
            "low" -> NotificationManager.IMPORTANCE_LOW
            "high" -> NotificationManager.IMPORTANCE_HIGH
            else -> NotificationManager.IMPORTANCE_DEFAULT
        }
        nm.createNotificationChannel(
            NotificationChannel(spec["id"] as String, spec["name"] as String, importance).apply {
                description = spec["description"] as String?
            }
        )
    }

    /** The foreground-service notification, from persisted [spec]. */
    fun foreground(spec: JSONObject): Notification {
        ensureDefaultChannels()
        val b = builder(spec.str("channelId") ?: RUNTIME_CHANNEL)
            .setContentTitle(spec.str("title") ?: appLabel())
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setSmallIcon(smallIcon(spec.str("smallIcon")))
            .setContentIntent(launchIntent(FOREGROUND_ID, null, null, null))
        spec.str("body")?.let(b::setContentText)
        if (!spec.isNull("progress")) {
            b.setProgress(1000, (spec.getDouble("progress") * 1000).toInt(), false)
        }
        if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        addActions(b, FOREGROUND_ID, spec.optJSONArray("actions"), null, cancel = false)
        return b.build()
    }

    fun updateForeground(spec: JSONObject) = nm.notify(FOREGROUND_ID, foreground(spec))

    fun show(spec: Map<*, *>, fullScreenStatus: () -> String) {
        ensureDefaultChannels()
        val id = (spec["id"] as Number).toInt()
        val data = (spec["payload"] as Map<*, *>?)?.let(Json::fromMap)?.toString()
        val deepLink = spec["deepLink"] as String?
        val fullScreen = spec["fullScreen"] as String?
        val channel = spec["channelId"] as String? ?: if (fullScreen != null) URGENT_CHANNEL else DEFAULT_CHANNEL
        val ongoing = spec["ongoing"] == true
        val tap = launchIntent(id, null, deepLink, data)
        val b = builder(channel)
            .setContentTitle(spec["title"] as String)
            .setSmallIcon(smallIcon(null))
            .setContentIntent(tap)
            .setAutoCancel(!ongoing)
            .setOngoing(ongoing)
        (spec["body"] as String?)?.let(b::setContentText)
        (spec["group"] as String?)?.let(b::setGroup)
        if (fullScreen != null) {
            b.setCategory(if (fullScreen == "alarm") Notification.CATEGORY_ALARM else Notification.CATEGORY_CALL)
            @Suppress("DEPRECATION")
            b.setPriority(Notification.PRIORITY_HIGH) // heads-up on < 26
            // Only legitimate call/alarm use; silently degrades to heads-up
            // when the user has not granted full-screen intents.
            if (fullScreenStatus() == Status.SUPPORTED) b.setFullScreenIntent(tap, true)
        }
        addActions(b, id, (spec["actions"] as List<*>?)?.let { JSONArray(it.map { a -> Json.fromMap(a as Map<*, *>) }) }, data, cancel = !ongoing)
        nm.notify(id, b.build())
    }

    fun cancel(id: Int) = nm.cancel(id)

    /** Shown when the OS refused to restore the runtime without the user. */
    fun showResume() {
        ensureDefaultChannels()
        nm.notify(
            RESUME_ID,
            builder(DEFAULT_CHANNEL)
                .setContentTitle(appLabel())
                .setContentText("Tap to resume background activity")
                .setSmallIcon(smallIcon(null))
                .setAutoCancel(true)
                .setContentIntent(launchIntent(RESUME_ID, null, null, null))
                .build()
        )
    }

    private fun addActions(b: Notification.Builder, id: Int, actions: JSONArray?, data: String?, cancel: Boolean) {
        if (actions == null) return
        for (i in 0 until minOf(actions.length(), 3)) {
            val a = actions.getJSONObject(i)
            val actionId = a.getString("id")
            val intent = if (a.optBoolean("opensApp")) {
                launchIntent(id, actionId, null, data, requestSlot = i + 1)
            } else {
                val broadcast = Intent(context, NotificationActionReceiver::class.java)
                    .putExtra(EXTRA_NOTIFICATION_ID, id)
                    .putExtra(EXTRA_ACTION_ID, actionId)
                    .putExtra(EXTRA_DATA, data)
                    .putExtra(EXTRA_CANCEL, cancel)
                PendingIntent.getBroadcast(context, requestCode(id, i + 1), broadcast, FLAGS)
            }
            @Suppress("DEPRECATION")
            b.addAction(Notification.Action.Builder(0, a.getString("label"), intent).build())
        }
    }

    /** Direct activity PendingIntent (no trampoline, allowed on Android 12+). */
    private fun launchIntent(id: Int, actionId: String?, deepLink: String?, data: String?, requestSlot: Int = 0): PendingIntent {
        val intent = (context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent())
            .setPackage(context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_NOTIFICATION_ID, id)
            .putExtra(EXTRA_ACTION_ID, actionId)
            .putExtra(EXTRA_DATA, data)
        deepLink?.let { intent.data = Uri.parse(it) }
        return PendingIntent.getActivity(context, requestCode(id, requestSlot), intent, FLAGS)
    }

    private fun requestCode(id: Int, slot: Int) = id * 8 + slot

    @Suppress("DEPRECATION")
    private fun builder(channel: String) =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)

    private fun smallIcon(name: String?): Int {
        if (!name.isNullOrEmpty()) {
            val id = context.resources.getIdentifier(name, "drawable", context.packageName)
            if (id != 0) return id
            NFLog.w("smallIcon '$name' not found; using app icon")
        }
        return context.applicationInfo.icon
    }

    private fun appLabel() = context.packageManager.getApplicationLabel(context.applicationInfo).toString()

    private val FLAGS = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
}

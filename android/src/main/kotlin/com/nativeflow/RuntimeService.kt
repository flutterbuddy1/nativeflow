package com.nativeflow

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * The ONE foreground service backing the runtime, whatever the number of
 * adapters. Thin: all decisions live in [RuntimeSupervisor].
 */
class RuntimeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        RuntimeSupervisor.ensure(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        RuntimeSupervisor.onServiceCommand(this, intent)

    /** Android 15+: the OS time limit for this FGS type was reached. */
    override fun onTimeout(startId: Int, fgsType: Int) = RuntimeSupervisor.onServiceTimeout(this)

    override fun onDestroy() {
        RuntimeSupervisor.onServiceDestroyed()
        super.onDestroy()
    }

    internal fun goForeground(notification: Notification, types: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NotificationPresenter.FOREGROUND_ID, notification, types)
        } else {
            startForeground(NotificationPresenter.FOREGROUND_ID, notification)
        }
    }

    internal fun leave() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    internal companion object {
        const val ACTION_START = "dev.nativeflow.START"
        const val ACTION_UPDATE = "dev.nativeflow.UPDATE"
        const val ACTION_RESTORE = "dev.nativeflow.RESTORE"
        const val EXTRA_REASON = "dev.nativeflow.reason"
    }
}

package com.nativeflow.capability

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.provider.Settings
import com.nativeflow.RequirementManager
import com.nativeflow.RuntimeService

/** Wire values of Dart's CapabilityStatus. */
object Status {
    const val SUPPORTED = "supported"
    const val PARTIAL = "partiallySupported"
    const val PERMISSION_REQUIRED = "permissionRequired"
    const val RESTRICTED = "restricted"
    const val UNAVAILABLE = "unavailable"
}

/**
 * Honest per-device capability report. A capability is only "supported" if
 * the app declared what the OS needs AND the user granted it.
 */
class CapabilityManager(private val context: Context) {
    private val declaredPermissions: Set<String> by lazy {
        context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions?.toSet() ?: emptySet()
    }

    /** The RuntimeService's merged-manifest foregroundServiceType mask. */
    val declaredServiceTypes: Int by lazy {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return@lazy ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        context.packageManager.getServiceInfo(ComponentName(context, RuntimeService::class.java), 0)
            .foregroundServiceType
    }

    fun declared(permission: String) = permission in declaredPermissions

    fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun report(): Map<String, String> = ALL.associateWith(::status)

    fun status(capability: String): String = when (capability) {
        "backgroundExecution" -> Status.SUPPORTED
        "persistentRuntime" ->
            // dataSync-only runtimes are capped at 6h/24h on Android 15+.
            if (Build.VERSION.SDK_INT >= 35 &&
                RequirementManager.isTimeLimited(RequirementManager.serviceTypes(emptySet(), declaredServiceTypes))
            ) Status.PARTIAL else Status.SUPPORTED
        "network" -> if (declared(Manifest.permission.ACCESS_NETWORK_STATE)) Status.SUPPORTED else Status.UNAVAILABLE
        "location" -> runtimePermission(
            listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
        )
        "microphone" -> runtimePermission(
            listOf(Manifest.permission.RECORD_AUDIO), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
        )
        "audio" ->
            if (declaredServiceTypes and ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK != 0) Status.SUPPORTED
            else Status.UNAVAILABLE
        "notifications" -> notifications()
        "overlay" -> overlay()
        "fullscreen" -> fullscreen()
        "bootRecovery" ->
            // Android 15 forbids starting several FGS types from BOOT_COMPLETED,
            // and force-stopped apps never receive it.
            if (declared(Manifest.permission.RECEIVE_BOOT_COMPLETED)) Status.PARTIAL else Status.UNAVAILABLE
        "backgroundProcessing" -> Status.PARTIAL // JobScheduler: the OS decides when
        else -> Status.UNAVAILABLE // liveActivity, widget
    }

    private fun runtimePermission(permissions: List<String>, serviceType: Int): String = when {
        permissions.none(::declared) -> Status.UNAVAILABLE
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && declaredServiceTypes and serviceType == 0 ->
            Status.UNAVAILABLE
        permissions.any(::granted) -> Status.SUPPORTED
        else -> Status.PERMISSION_REQUIRED
    }

    private fun notifications(): String {
        val nm = context.getSystemService(NotificationManager::class.java)
        return when {
            Build.VERSION.SDK_INT >= 33 && !granted(Manifest.permission.POST_NOTIFICATIONS) ->
                Status.PERMISSION_REQUIRED
            !nm.areNotificationsEnabled() -> Status.RESTRICTED
            else -> Status.SUPPORTED
        }
    }

    private fun overlay(): String {
        val am = context.getSystemService(ActivityManager::class.java)
        return when {
            !declared(Manifest.permission.SYSTEM_ALERT_WINDOW) -> Status.UNAVAILABLE
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && am.isLowRamDevice -> Status.UNAVAILABLE
            Settings.canDrawOverlays(context) -> Status.SUPPORTED
            else -> Status.PERMISSION_REQUIRED
        }
    }

    fun fullscreen(): String {
        if (!declared(Manifest.permission.USE_FULL_SCREEN_INTENT)) return Status.UNAVAILABLE
        if (Build.VERSION.SDK_INT >= 34) {
            val nm = context.getSystemService(NotificationManager::class.java)
            return if (nm.canUseFullScreenIntent()) Status.SUPPORTED else Status.PERMISSION_REQUIRED
        }
        return Status.SUPPORTED
    }

    companion object {
        val ALL = listOf(
            "backgroundExecution", "persistentRuntime", "network", "location", "microphone", "audio",
            "notifications", "overlay", "fullscreen", "bootRecovery", "liveActivity", "widget",
            "backgroundProcessing",
        )
    }
}

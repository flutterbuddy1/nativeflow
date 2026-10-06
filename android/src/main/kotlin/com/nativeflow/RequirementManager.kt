package com.nativeflow

import android.Manifest
import android.content.pm.ServiceInfo

/**
 * Turns the aggregated capability set of all adapters into ONE foreground
 * service type mask. Pure logic, unit tested.
 */
object RequirementManager {
    /** Capabilities that map to a specific foreground service type. */
    private val specific = linkedMapOf(
        "location" to ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
        "microphone" to ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
        "audio" to ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
    )

    /**
     * Generic types for "keep running" workloads, in preference order:
     * specialUse and remoteMessaging have no OS time limit; dataSync is
     * limited to 6h/24h on Android 15+.
     */
    private val generic = listOf(
        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
    )

    /** Runtime permissions the OS checks when starting a typed FGS. */
    val requiredPermissions = mapOf(
        "location" to listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
        "microphone" to listOf(Manifest.permission.RECORD_AUDIO),
    )

    /**
     * @param declared the service's `foregroundServiceType` from the merged
     *   manifest. We never pass a type the app did not declare: that throws.
     * @return types to pass to `startForeground`. Specific types replace the
     *   generic one so a location-only runtime is not subject to dataSync
     *   time limits.
     */
    fun serviceTypes(capabilities: Set<String>, declared: Int): Int {
        var mask = 0
        for ((cap, type) in specific) {
            if (cap in capabilities && declared and type != 0) mask = mask or type
        }
        if (mask != 0) return mask
        return generic.firstOrNull { declared and it != 0 } ?: 0
    }

    /** Capabilities whose FGS type would throw SecurityException right now. */
    fun missingPermissions(capabilities: Set<String>, granted: (String) -> Boolean): List<String> =
        requiredPermissions.filter { (cap, perms) -> cap in capabilities && perms.none(granted) }.keys.toList()

    /** Types time-limited by Android 15+ (onTimeout will be called). */
    fun isTimeLimited(mask: Int): Boolean =
        mask == ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
}

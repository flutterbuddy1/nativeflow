package com.nativeflow

/**
 * Decides whether the runtime should be restored after the OS interrupted
 * it. Pure logic, unit tested. Recovery only ever restores an explicit
 * intent the app recorded with `NativeFlow.start()`; `stop()` clears it.
 */
object RecoveryManager {
    enum class Trigger { SERVICE_RESTART, BOOT, PACKAGE_REPLACED }

    /** Sticky restarts tolerated inside [CRASH_WINDOW_MS] before giving up. */
    const val MAX_RESTARTS = 5
    const val CRASH_WINDOW_MS = 10 * 60 * 1000L

    data class Decision(val restore: Boolean, val reason: String)

    fun decide(
        trigger: Trigger,
        active: Boolean,
        restoreOnBoot: Boolean,
        recentRestarts: List<Long>,
        now: Long,
    ): Decision = when {
        !active -> Decision(false, "notActive")
        trigger == Trigger.BOOT && !restoreOnBoot -> Decision(false, "bootRestoreDisabled")
        trigger == Trigger.SERVICE_RESTART &&
            recentRestarts.count { now - it < CRASH_WINDOW_MS } >= MAX_RESTARTS ->
            Decision(false, "restartLoop")
        else -> Decision(true, trigger.name.lowercase())
    }

    /** Restart timestamps to keep after recording one at [now]. */
    fun recordRestart(recentRestarts: List<Long>, now: Long): List<Long> =
        (recentRestarts + now).filter { now - it < CRASH_WINDOW_MS }.takeLast(MAX_RESTARTS * 2)
}

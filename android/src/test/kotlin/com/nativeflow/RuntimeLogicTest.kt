package com.nativeflow

import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC as DATA_SYNC
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION as LOCATION
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE as MICROPHONE
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE as SPECIAL_USE
import com.nativeflow.RecoveryManager.Trigger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RequirementManagerTest {
    @Test
    fun `driver requirements collapse into one location service`() {
        val caps = setOf("backgroundExecution", "network", "location", "notifications", "overlay")
        assertEquals(LOCATION, RequirementManager.serviceTypes(caps, LOCATION or DATA_SYNC))
    }

    @Test
    fun `undeclared types are never requested`() {
        // App did not override the manifest: only dataSync is declared.
        assertEquals(DATA_SYNC, RequirementManager.serviceTypes(setOf("location"), DATA_SYNC))
        assertEquals(0, RequirementManager.serviceTypes(setOf("network"), 0))
    }

    @Test
    fun `generic workloads prefer types without time limits`() {
        assertEquals(SPECIAL_USE, RequirementManager.serviceTypes(setOf("network"), SPECIAL_USE or DATA_SYNC))
        assertTrue(RequirementManager.isTimeLimited(DATA_SYNC))
        assertFalse(RequirementManager.isTimeLimited(LOCATION))
    }

    @Test
    fun `multiple specific capabilities combine`() {
        assertEquals(
            LOCATION or MICROPHONE,
            RequirementManager.serviceTypes(setOf("location", "microphone"), LOCATION or MICROPHONE or DATA_SYNC),
        )
    }

    @Test
    fun `missing runtime permissions are reported per capability`() {
        val granted = setOf(android.Manifest.permission.ACCESS_COARSE_LOCATION)
        assertEquals(
            listOf("microphone"),
            RequirementManager.missingPermissions(setOf("location", "microphone", "network")) { it in granted },
        )
    }
}

class RecoveryManagerTest {
    private val now = 100_000_000L

    @Test
    fun `never restores without recorded intent`() {
        for (t in Trigger.values()) {
            assertFalse(RecoveryManager.decide(t, active = false, restoreOnBoot = true, emptyList(), now).restore)
        }
    }

    @Test
    fun `boot restore requires explicit opt-in`() {
        assertFalse(RecoveryManager.decide(Trigger.BOOT, true, restoreOnBoot = false, emptyList(), now).restore)
        assertTrue(RecoveryManager.decide(Trigger.BOOT, true, restoreOnBoot = true, emptyList(), now).restore)
        assertTrue(RecoveryManager.decide(Trigger.PACKAGE_REPLACED, true, false, emptyList(), now).restore)
    }

    @Test
    fun `restart loop guard gives up and old restarts age out`() {
        val recent = List(RecoveryManager.MAX_RESTARTS) { now - it * 1000L }
        val d = RecoveryManager.decide(Trigger.SERVICE_RESTART, true, false, recent, now)
        assertFalse(d.restore)
        assertEquals("restartLoop", d.reason)

        val old = List(RecoveryManager.MAX_RESTARTS) { now - RecoveryManager.CRASH_WINDOW_MS - it }
        assertTrue(RecoveryManager.decide(Trigger.SERVICE_RESTART, true, false, old, now).restore)
        assertEquals(listOf(now), RecoveryManager.recordRestart(old, now))
    }
}

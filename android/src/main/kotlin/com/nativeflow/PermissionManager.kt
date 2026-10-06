package com.nativeflow

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.nativeflow.capability.CapabilityManager
import com.nativeflow.capability.Status
import io.flutter.plugin.common.PluginRegistry

/**
 * Requests permissions only when the app explicitly asks for a capability,
 * and only if that capability's status is `permissionRequired`.
 */
internal class PermissionManager(private val capabilities: CapabilityManager) :
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    var activity: Activity? = null
    private val pending = mutableMapOf<Int, Pair<String, (String) -> Unit>>()
    private var nextCode = 0

    fun request(capability: String, done: (String) -> Unit) {
        val status = capabilities.status(capability)
        val act = activity
        if (status != Status.PERMISSION_REQUIRED || act == null) return done(status)
        val code = REQUEST_BASE + (nextCode++ % 256)
        pending[code] = capability to done
        val pkg = Uri.parse("package:${act.packageName}")
        when (capability) {
            "overlay" -> act.startActivityForResult(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg), code)
            "fullscreen" ->
                if (Build.VERSION.SDK_INT >= 34) {
                    act.startActivityForResult(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg), code)
                } else finish(code)
            "notifications" ->
                if (Build.VERSION.SDK_INT >= 33) act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), code)
                else finish(code)
            "location", "microphone" -> {
                val perms = RequirementManager.requiredPermissions.getValue(capability).filter(capabilities::declared)
                act.requestPermissions(perms.toTypedArray(), code)
            }
            else -> finish(code)
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) = finish(code)

    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?) = finish(code)

    private fun finish(code: Int): Boolean {
        val (capability, done) = pending.remove(code) ?: return false
        done(capabilities.status(capability))
        return true
    }

    private companion object {
        const val REQUEST_BASE = 0x4E00
    }
}

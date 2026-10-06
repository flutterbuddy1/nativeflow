package com.nativeflow

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Durable runtime intent and configuration, so the runtime can be restored
 * after process death or reboot without Flutter. Holds no secrets: only
 * flags, capability names, notification text and overlay layout.
 */
internal class RuntimeStore(context: Context) {
    private val prefs = context.getSharedPreferences("dev.nativeflow.runtime", Context.MODE_PRIVATE)

    /** The app asked the runtime to run (set by start, cleared by stop). */
    var active: Boolean
        get() = prefs.getBoolean("active", false)
        set(v) { prefs.edit().putBoolean("active", v).commit() }

    var persistent: Boolean
        get() = prefs.getBoolean("persistent", true)
        set(v) { prefs.edit().putBoolean("persistent", v).apply() }

    var restoreOnBoot: Boolean
        get() = prefs.getBoolean("restoreOnBoot", false)
        set(v) { prefs.edit().putBoolean("restoreOnBoot", v).apply() }

    var capabilities: Set<String>
        get() = prefs.getStringSet("capabilities", emptySet())!!.toSet()
        set(v) { prefs.edit().putStringSet("capabilities", v).apply() }

    var notification: JSONObject
        get() = prefs.getString("notification", null)?.let(::JSONObject) ?: JSONObject()
        set(v) { prefs.edit().putString("notification", v.toString()).apply() }

    var backgroundHandle: Long
        get() = prefs.getLong("backgroundHandle", 0)
        set(v) { prefs.edit().putLong("backgroundHandle", v).apply() }

    var logLevel: Int
        get() = prefs.getInt("logLevel", 1)
        set(v) { prefs.edit().putInt("logLevel", v).apply() }

    /** Visible overlay spec + position, or null. */
    var overlay: JSONObject?
        get() = prefs.getString("overlay", null)?.let(::JSONObject)
        set(v) { prefs.edit().putString("overlay", v?.toString()).apply() }

    var restarts: List<Long>
        get() = prefs.getString("restarts", null)?.let { s ->
            val a = JSONArray(s); (0 until a.length()).map { a.getLong(it) }
        } ?: emptyList()
        set(v) { prefs.edit().putString("restarts", JSONArray(v).toString()).apply() }
}

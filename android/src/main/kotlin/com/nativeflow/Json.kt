package com.nativeflow

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** Converts between Flutter codec values and org.json, which we persist. */
internal object Json {
    fun toMap(o: JSONObject): Map<String, Any?> =
        o.keys().asSequence().associateWith { unwrap(o.get(it)) }

    fun fromMap(map: Map<*, *>): JSONObject {
        val o = JSONObject()
        for ((k, v) in map) o.put(k as String, wrap(v))
        return o
    }

    private fun wrap(v: Any?): Any = when (v) {
        null -> JSONObject.NULL
        is Map<*, *> -> fromMap(v)
        is List<*> -> JSONArray().also { a -> v.forEach { a.put(wrap(it)) } }
        is String, is Boolean, is Int, is Long, is Double -> v
        is Number -> v.toDouble()
        is ByteArray -> android.util.Base64.encodeToString(v, android.util.Base64.NO_WRAP) // overlay images
        else -> throw IllegalArgumentException("Unsupported JSON value ${v.javaClass.simpleName}")
    }

    private fun unwrap(v: Any?): Any? = when (v) {
        JSONObject.NULL, null -> null
        is JSONObject -> toMap(v)
        is JSONArray -> (0 until v.length()).map { unwrap(v.get(it)) }
        else -> v
    }
}

/** Native logging gated by the Dart-side LogVerbosity index. */
internal object NFLog {
    private const val TAG = "NativeFlow"

    /** 0 disabled, 1 errors, 2 normal, 3 verbose. */
    @Volatile
    var level = 1

    fun d(msg: String) { if (level >= 3) Log.d(TAG, msg) }
    fun i(msg: String) { if (level >= 2) Log.i(TAG, msg) }
    fun w(msg: String) { if (level >= 2) Log.w(TAG, msg) }
    fun e(msg: String, t: Throwable? = null) { if (level >= 1) Log.e(TAG, msg, t) }
}

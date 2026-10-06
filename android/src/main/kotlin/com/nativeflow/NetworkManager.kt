package com.nativeflow

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

/**
 * Default-network observer built on ConnectivityManager callbacks (no
 * polling). Reports only when (connected, type, metered) actually changes.
 * NativeFlow never touches the app's sockets; adapters react to events.
 */
internal class NetworkManager(
    context: Context,
    private val onChange: (previous: Map<String, Any>, current: Map<String, Any>) -> Unit,
) {
    private val cm = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var state: Map<String, Any> = describe(cm.getNetworkCapabilities(cm.activeNetwork))
        private set

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            update(describe(caps))
        }

        override fun onLost(network: Network) {
            update(OFFLINE)
        }
    }

    init {
        cm.registerDefaultNetworkCallback(callback)
    }

    private fun update(next: Map<String, Any>) = main.post {
        val previous = state
        if (previous == next) return@post
        state = next
        onChange(previous, next)
    }

    companion object {
        private val OFFLINE = mapOf("connected" to false, "type" to "none", "metered" to false)

        fun describe(caps: NetworkCapabilities?): Map<String, Any> {
            if (caps == null) return OFFLINE
            val connected = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            val type = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                else -> "other"
            }
            return mapOf(
                "connected" to connected,
                "type" to if (connected) type else "none",
                "metered" to !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
            )
        }
    }
}

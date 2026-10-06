package com.nativeflow

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.view.FlutterCallbackInformation

/**
 * The background Flutter engine that runs adapters while no UI engine is
 * attached. Created lazily and only when the runtime is active, a
 * background entrypoint was registered, and no engine participates.
 * Destroyed as soon as a UI engine initializes or the runtime stops.
 */
internal object NativeFlowEngine {
    private var engine: FlutterEngine? = null

    /** True while the engine constructor auto-registers plugins, so the
     * plugin instance created for it knows it is the background engine. */
    var spawning = false
        private set

    val isRunning get() = engine != null

    fun spawn(context: Context, handle: Long) {
        if (engine != null) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
        if (info == null) {
            NFLog.e("Background entrypoint not found; was the app rebuilt without it?")
            return
        }
        spawning = true
        val created = try {
            FlutterEngine(context.applicationContext)
        } finally {
            spawning = false
        }
        engine = created
        created.dartExecutor.executeDartCallback(
            DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), info)
        )
        NFLog.i("Background engine started")
    }

    fun destroy() {
        engine?.destroy() ?: return
        engine = null
        NFLog.i("Background engine destroyed")
    }
}

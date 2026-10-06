package com.nativeflow

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.nativeflow.capability.CapabilityManager
import io.flutter.plugin.common.EventChannel
import java.io.File

/**
 * Process-wide owner of the runtime: state machine, the single foreground
 * service, recovery decisions, the event store/outbox and Flutter engine
 * ownership. Everything runs on the main thread.
 */
@SuppressLint("StaticFieldLeak") // holds the application context only
object RuntimeSupervisor {
    enum class State(val wire: String) {
        STOPPED("stopped"), STARTING("starting"), RUNNING("running"),
        STOPPING("stopping"), INTERRUPTED("interrupted"), RECOVERING("recovering"),
    }

    private const val START_TIMEOUT_MS = 10_000L
    private const val SPAWN_DELAY_MS = 1_000L
    private const val RELEASE_TIMEOUT_MS = 3_000L

    private val main = Handler(Looper.getMainLooper())
    private lateinit var context: Context
    internal lateinit var store: RuntimeStore
    internal lateinit var events: EventStore
    internal lateinit var capabilities: CapabilityManager
    internal lateinit var notifications: NotificationPresenter
    internal lateinit var overlay: OverlayManager
    private var network: NetworkManager? = null

    var state = State.STOPPED
        private set

    private var service: RuntimeService? = null
    private var pendingStart: ((error: Pair<String, String>?) -> Unit)? = null
    private var restoring: String? = null

    private val participants = linkedSetOf<NativeFlowPlugin>()
    private val sinks = linkedSetOf<EventChannel.EventSink>()
    private val outbox = mutableListOf<Map<String, Any?>>()

    @Synchronized
    fun ensure(ctx: Context) {
        if (::context.isInitialized) return
        context = ctx.applicationContext
        store = RuntimeStore(context)
        NFLog.level = store.logLevel
        events = EventStore(File(context.noBackupFilesDir, "nativeflow/events.jsonl"))
        capabilities = CapabilityManager(context)
        notifications = NotificationPresenter(context)
        overlay = OverlayManager(context, store) { type, payload -> emit(type, payload, persist = true) }
        // A fresh process with a recorded intent means the OS killed us.
        if (store.active) state = State.INTERRUPTED
    }

    private fun startNetwork() {
        if (network != null) return
        network = NetworkManager(context) { previous, current ->
            val type = when {
                current["connected"] == true && previous["connected"] != true -> "nativeflow.network.available"
                current["connected"] != true && previous["connected"] == true -> "nativeflow.network.lost"
                else -> "nativeflow.network.changed"
            }
            emit(type, current)
        }
    }

    // ------------------------------------------------------------- commands

    fun snapshot(plugin: NativeFlowPlugin): Map<String, Any?> = mapOf(
        "state" to state.wire,
        "network" to network?.state,
        "backgroundEngine" to plugin.isBackground,
        "lastAck" to events.lastAck,
        "capabilities" to store.capabilities.toList(),
    )

    fun initialize(plugin: NativeFlowPlugin, logLevel: Int, handle: Long?, reply: (Map<String, Any?>) -> Unit) {
        NFLog.level = logLevel
        store.logLevel = logLevel
        if (handle != null) store.backgroundHandle = handle
        startNetwork()
        participants += plugin

        val proceed = {
            // App relaunch after the OS killed the runtime: restore it now
            // that we are in the foreground and allowed to start an FGS.
            if (!plugin.isBackground && state == State.INTERRUPTED && store.active) {
                restore("appLaunch")
            }
            reply(snapshot(plugin))
        }
        val background = participants.firstOrNull { it.isBackground }
        if (!plugin.isBackground && background != null) {
            handOff(background, proceed)
        } else {
            proceed()
        }
    }

    fun start(config: Map<*, *>, done: (error: Pair<String, String>?) -> Unit) {
        val caps = requirementsOf(config)
        val missing = RequirementManager.missingPermissions(caps, capabilities::granted)
        if (missing.isNotEmpty()) return done("permission_required" to "Not granted: ${missing.joinToString()}")

        store.capabilities = caps
        store.notification = Json.fromMap(config["notification"] as Map<*, *>? ?: emptyMap<String, Any>())
        store.persistent = config["persistent"] != false
        store.restoreOnBoot = config["restoreOnBoot"] == true
        store.restarts = emptyList()
        store.active = true

        if (service != null && state == State.RUNNING) {
            sendToService(RuntimeService.ACTION_UPDATE)
            return done(null)
        }
        state = State.STARTING
        pendingStart = done
        if (!sendToService(RuntimeService.ACTION_START)) return
        main.postDelayed({
            if (pendingStart === done) failStart("platform" to "Runtime service did not start in time")
        }, START_TIMEOUT_MS)
    }

    fun setRequirements(config: Map<*, *>): Pair<String, String>? {
        val caps = requirementsOf(config)
        val missing = RequirementManager.missingPermissions(caps, capabilities::granted)
        if (missing.isNotEmpty()) return "permission_required" to "Not granted: ${missing.joinToString()}"
        store.capabilities = caps
        if (service != null) sendToService(RuntimeService.ACTION_UPDATE)
        return null
    }

    fun stop() {
        store.active = false
        failStart("not_allowed" to "Stopped while starting")
        val s = service
        if (s != null) {
            state = State.STOPPING
            s.leave() // onDestroy -> onServiceDestroyed -> STOPPED
        } else {
            setStopped()
        }
        // The background engine only exists to run adapters for an active runtime.
        main.post { if (!store.active) dropBackgroundEngine() }
    }

    /** Foreground notification update (Android side of RuntimePresentation). */
    fun present(spec: Map<*, *>) {
        val merged = store.notification
        val incoming = Json.fromMap(spec)
        for (key in listOf("title", "body", "progress", "actions")) {
            if (incoming.isNull(key)) merged.remove(key) else merged.put(key, incoming.get(key))
        }
        if (service != null) {
            store.notification = merged
            notifications.updateForeground(merged)
        } else {
            notifications.show(
                mapOf("id" to NotificationPresenter.PRESENTATION_ID, "title" to spec["title"], "body" to spec["body"],
                    "actions" to spec["actions"], "ongoing" to false),
                capabilities::fullscreen,
            )
        }
    }

    // ------------------------------------------------------ service callbacks

    internal fun onServiceCommand(s: RuntimeService, intent: Intent?): Int {
        service = s
        val restart = intent == null // sticky restart after the OS killed the process
        var restoreReason = if (intent?.action == RuntimeService.ACTION_RESTORE) {
            intent.getStringExtra(RuntimeService.EXTRA_REASON)
        } else null
        if (restart) {
            val now = System.currentTimeMillis()
            val decision = RecoveryManager.decide(
                RecoveryManager.Trigger.SERVICE_RESTART, store.active, store.restoreOnBoot, store.restarts, now,
            )
            store.restarts = RecoveryManager.recordRestart(store.restarts, now)
            restoreReason = decision.reason
            if (!decision.restore) {
                // We must still enter the foreground before stopping.
                tryForeground(s)
                s.leave()
                if (store.active) interrupt(decision.reason)
                return Service.START_NOT_STICKY
            }
        }
        if (!tryForeground(s)) return Service.START_NOT_STICKY
        startNetwork()
        overlay.restore()
        val wasRestoring = restoreReason ?: restoring
        restoring = null
        val previous = state
        state = State.RUNNING
        if (wasRestoring != null) {
            emit("nativeflow.runtime.recovered", mapOf("reason" to wasRestoring), persist = true)
            scheduleBackgroundEngine()
        } else if (previous != State.RUNNING) {
            emit("nativeflow.runtime.started")
        }
        pendingStart?.let { pendingStart = null; it(null) }
        return if (store.persistent) Service.START_STICKY else Service.START_NOT_STICKY
    }

    private fun tryForeground(s: RuntimeService): Boolean {
        val types = RequirementManager.serviceTypes(store.capabilities, capabilities.declaredServiceTypes)
        return try {
            s.goForeground(notifications.foreground(store.notification), types)
            true
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException, SecurityException
            // (permission revoked), MissingForegroundServiceTypeException.
            NFLog.e("startForeground failed", e)
            failStart("not_allowed" to (e.message ?: e.javaClass.simpleName))
            s.leave()
            interrupt("foregroundNotAllowed")
            false
        }
    }

    internal fun onServiceTimeout(s: RuntimeService) {
        interrupt("timeLimit")
        s.leave()
    }

    internal fun onServiceDestroyed() {
        service = null
        when (state) {
            State.STOPPING, State.STOPPED -> setStopped()
            State.INTERRUPTED -> Unit
            else -> interrupt("serviceDestroyed")
        }
    }

    // --------------------------------------------------------------- recovery

    /** Boot / app update. Only restores an intent the app recorded. */
    fun restoreFromSystem(trigger: RecoveryManager.Trigger) {
        val d = RecoveryManager.decide(trigger, store.active, store.restoreOnBoot, store.restarts, System.currentTimeMillis())
        NFLog.i("Restore ${trigger.name}: ${d.reason}")
        if (d.restore) restore(d.reason)
    }

    private fun restore(reason: String) {
        state = State.RECOVERING
        restoring = reason
        sendToService(RuntimeService.ACTION_RESTORE, reason)
    }

    private fun interrupt(reason: String) {
        if (state == State.INTERRUPTED) return
        state = State.INTERRUPTED
        emit("nativeflow.runtime.interrupted", mapOf("reason" to reason), persist = true)
    }

    private fun setStopped() {
        if (state == State.STOPPED) return
        state = State.STOPPED
        emit("nativeflow.runtime.stopped")
    }

    private fun failStart(error: Pair<String, String>) {
        val done = pendingStart ?: return
        pendingStart = null
        if (state == State.STARTING) state = State.STOPPED
        done(error)
    }

    /** @return false if the OS refused to start the service. */
    private fun sendToService(action: String, reason: String? = null): Boolean {
        val intent = Intent(context, RuntimeService::class.java).setAction(action).putExtra(RuntimeService.EXTRA_REASON, reason)
        return try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            true
        } catch (e: Exception) {
            // Android 12+: background FGS start not allowed (e.g. boot restore
            // of a restricted type). Tell the user instead of failing silently.
            NFLog.e("Starting runtime service failed", e)
            failStart("not_allowed" to (e.message ?: "Foreground service start not allowed"))
            if (action == RuntimeService.ACTION_RESTORE) {
                restoring = null
                state = State.STOPPED
                interrupt("restoreNotAllowed")
                notifications.showResume()
            }
            false
        }
    }

    // ------------------------------------------------- Flutter engine ownership

    fun addSink(sink: EventChannel.EventSink) {
        sinks += sink
    }

    fun removeSink(sink: EventChannel.EventSink?) {
        sinks.remove(sink)
    }

    fun onEngineDetached(plugin: NativeFlowPlugin) {
        participants -= plugin
        scheduleBackgroundEngine()
    }

    /** Spawn the background engine if the runtime is active and nobody runs adapters. */
    private fun scheduleBackgroundEngine() = main.postDelayed({
        if (participants.isEmpty() && state == State.RUNNING && store.backgroundHandle != 0L) {
            try {
                NativeFlowEngine.spawn(context, store.backgroundHandle)
            } catch (e: Exception) {
                NFLog.e("Background engine failed to start", e)
            }
        }
    }, SPAWN_DELAY_MS)

    private fun handOff(background: NativeFlowPlugin, then: () -> Unit) {
        var finished = false
        val finish = {
            if (!finished) {
                finished = true
                dropBackgroundEngine()
                then()
            }
        }
        background.release(finish)
        main.postDelayed(finish, RELEASE_TIMEOUT_MS)
    }

    private fun dropBackgroundEngine() {
        participants.removeAll { it.isBackground }
        NativeFlowEngine.destroy()
    }

    // ------------------------------------------------------------------ events

    fun appendEvent(type: String, adapterId: String?, payload: Map<*, *>): Long {
        val json = Json.fromMap(payload)
        require(json.toString().length <= 32 * 1024) { "Event payload exceeds 32 KB" }
        return emit(type, Json.toMap(json), adapterId, persist = true)!!
    }

    fun emitNotificationEvent(intent: Intent, isTap: Boolean) {
        val payload = NotificationActionReceiver.payloadOf(intent)
        val type = if (isTap || payload["actionId"] == null) "nativeflow.notification.tap" else "nativeflow.notification.action"
        emit(type, payload, persist = true)
    }

    /**
     * Persisted events are written to the store first (survive Flutter and
     * process death); all events are batched per main-loop turn to Dart.
     * @return the store id for persisted events.
     */
    fun emit(type: String, payload: Map<String, Any?> = emptyMap(), adapterId: String? = null, persist: Boolean = false): Long? {
        val event = if (persist) {
            events.append(type, adapterId, Json.fromMap(payload)).toMap()
        } else {
            mapOf("type" to type, "ts" to System.currentTimeMillis(), "adapterId" to adapterId, "payload" to payload)
        }
        NFLog.d("event $type")
        val first = outbox.isEmpty()
        outbox += event
        if (first) main.post(::flush)
        return event["id"] as Long?
    }

    private fun flush() {
        if (outbox.isEmpty()) return
        val batch = outbox.toList()
        outbox.clear()
        // No listener: persisted events wait in the store for the next sync.
        for (sink in sinks) sink.success(batch)
    }
}

package com.nativeflow

import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * One instance per Flutter engine. Translates a closed set of channel
 * commands into [RuntimeSupervisor] calls; there is no generic dispatch.
 */
class NativeFlowPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.NewIntentListener {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var activity: ActivityPluginBinding? = null
    private lateinit var permissions: PermissionManager

    /** True for the background engine NativeFlow spawned itself. */
    var isBackground = false
        private set

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        isBackground = NativeFlowEngine.spawning
        RuntimeSupervisor.ensure(binding.applicationContext)
        permissions = PermissionManager(RuntimeSupervisor.capabilities)
        channel = MethodChannel(binding.binaryMessenger, "dev.nativeflow/runtime")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "dev.nativeflow/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        RuntimeSupervisor.removeSink(sink)
        sink = null
        RuntimeSupervisor.onEngineDetached(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        RuntimeSupervisor.addSink(events)
    }

    override fun onCancel(arguments: Any?) {
        RuntimeSupervisor.removeSink(sink)
        sink = null
    }

    /** Ask this engine's Dart side to stop its adapters (engine hand-off). */
    internal fun release(done: () -> Unit) {
        channel.invokeMethod("release", null, object : MethodChannel.Result {
            override fun success(result: Any?) = done()
            override fun error(code: String, message: String?, details: Any?) = done()
            override fun notImplemented() = done()
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val s = RuntimeSupervisor
        try {
            when (call.method) {
                "initialize" -> s.initialize(
                    this,
                    call.argument<Int>("logLevel") ?: 1,
                    call.argument<Number>("backgroundHandle")?.toLong(),
                ) { result.success(it) }
                "capabilities" -> result.success(s.capabilities.report())
                "start" -> s.start(call.arguments as Map<*, *>) { error ->
                    if (error == null) result.success(s.state.wire) else result.error(error.first, error.second, null)
                }
                "stop" -> { s.stop(); result.success(s.state.wire) }
                "setRequirements" -> {
                    val error = s.setRequirements(call.arguments as Map<*, *>)
                    if (error == null) result.success(null) else result.error(error.first, error.second, null)
                }
                "appendEvent" -> result.success(
                    s.appendEvent(
                        call.argument<String>("type")!!.also(::validateId),
                        call.argument<String>("adapterId")?.also(::validateId),
                        call.argument<Map<*, *>>("payload") ?: emptyMap<String, Any>(),
                    )
                )
                "pendingEvents" -> result.success(
                    s.events.pending(
                        call.argument<Number>("after")?.toLong() ?: 0,
                        call.argument<Int>("limit") ?: 100,
                    ).map { it.toMap() }
                )
                "ackEvents" -> { s.events.ack(call.argument<Number>("upTo")!!.toLong()); result.success(null) }
                "permissionStatus" -> result.success(s.capabilities.status(call.argument<String>("capability")!!))
                "requestPermission" -> permissions.request(call.argument<String>("capability")!!) { result.success(it) }
                "createChannel" -> { s.notifications.createChannel(call.arguments as Map<*, *>); result.success(null) }
                "showNotification" -> {
                    s.notifications.show(call.arguments as Map<*, *>, s.capabilities::fullscreen)
                    result.success(null)
                }
                "cancelNotification" -> { s.notifications.cancel(call.argument<Int>("id")!!); result.success(null) }
                "overlayShow" -> {
                    if (!s.overlay.canShow()) return result.error("permission_required", "Overlay permission not granted", null)
                    s.overlay.show(Json.fromMap(call.arguments as Map<*, *>)); result.success(null)
                }
                "overlayUpdate" -> {
                    s.overlay.update(Json.fromMap(call.arguments as Map<*, *>).getJSONObject("content"))
                    result.success(null)
                }
                "overlayHide" -> { s.overlay.hide(byUser = false); result.success(null) }
                "overlayMove" -> {
                    s.overlay.move(call.argument<Double>("x")!!, call.argument<Double>("y")!!); result.success(null)
                }
                "overlayResize" -> {
                    s.overlay.resize(call.argument<Double>("width"), call.argument<Double>("height")); result.success(null)
                }
                "overlayState" -> result.success(s.overlay.state())
                "present" -> { s.present(call.arguments as Map<*, *>); result.success(null) }
                "activityStart", "activityUpdate", "activityEnd", "widgetUpdate",
                "scheduleBackgroundTask", "completeBackgroundTask" ->
                    result.error("unavailable", "${call.method} is iOS-only", null)
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("invalid_argument", e.message, null)
        } catch (e: SecurityException) {
            result.error("permission_required", e.message, null)
        } catch (e: Exception) {
            NFLog.e("${call.method} failed", e)
            result.error("platform", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ------------------------------------------------------------- activity

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        permissions.activity = binding.activity
        binding.addRequestPermissionsResultListener(permissions)
        binding.addActivityResultListener(permissions)
        binding.addOnNewIntentListener(this)
        handleLaunchIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(permissions)
        activity?.removeActivityResultListener(permissions)
        activity?.removeOnNewIntentListener(this)
        activity = null
        permissions.activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onNewIntent(intent: Intent): Boolean {
        handleLaunchIntent(intent)
        return false // let the app (deep-link handlers) see it too
    }

    /** Notification taps / opensApp actions arrive as activity intents. */
    private fun handleLaunchIntent(intent: Intent?) {
        if (intent == null || !intent.hasExtra(NotificationPresenter.EXTRA_NOTIFICATION_ID)) return
        val isTap = intent.getStringExtra(NotificationPresenter.EXTRA_ACTION_ID) == null
        RuntimeSupervisor.emitNotificationEvent(intent, isTap)
        // Consume so activity recreation does not report the tap twice.
        intent.removeExtra(NotificationPresenter.EXTRA_NOTIFICATION_ID)
    }

    private fun validateId(id: String) =
        require(ID.matches(id)) { "Invalid id '$id'" }

    private companion object {
        val ID = Regex("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$")
    }
}

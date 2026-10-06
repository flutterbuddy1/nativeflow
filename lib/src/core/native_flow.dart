import 'dart:ui' show PluginUtilities;

import 'package:flutter/foundation.dart';

import '../adapter/runtime_adapter.dart';
import '../events/runtime_event_bus.dart';
import '../logging/logger.dart';
import '../network/network_state.dart';
import '../notification/notifications.dart';
import '../overlay/overlay.dart';
import '../permissions/permissions.dart';
import '../platform/native_flow_platform.dart';
import '../presentation/presentation.dart';
import 'errors.dart';
import 'runtime.dart';
import 'runtime_capability.dart';
import 'runtime_session.dart';
import 'runtime_state.dart';

/// Entry point of the NativeFlow runtime.
///
/// ```dart
/// await NativeFlow.initialize();
/// await NativeFlow.attach(RuntimeAdapter(id: 'chat', start: connect, stop: disconnect));
/// await NativeFlow.start();
/// ```
abstract final class NativeFlow {
  static NativeFlowRuntime? _instance;

  static NativeFlowRuntime get _runtime =>
      _instance ??= NativeFlowRuntime(MethodChannelNativeFlowPlatform());

  /// Connects to the native runtime and synchronizes state and any events
  /// that arrived while Flutter was not running. Safe to call repeatedly;
  /// a call without [config] keeps the configuration already in effect.
  ///
  /// [backgroundEntrypoint] (Android) is a top-level or static function
  /// annotated `@pragma('vm:entry-point')`. When the runtime is running but
  /// no Flutter UI is attached (app swiped away, process restarted by the
  /// OS, reboot restore), NativeFlow starts a background Flutter engine
  /// that runs it. It should call [initialize] and re-[attach] the same
  /// adapters; they receive `recover`. When the UI returns, the background
  /// engine releases its adapters and is destroyed, so adapters run in
  /// exactly one engine at a time.
  static Future<void> initialize({
    NativeFlowConfig? config,
    void Function()? backgroundEntrypoint,
  }) {
    int? handle;
    if (backgroundEntrypoint != null) {
      handle = PluginUtilities.getCallbackHandle(backgroundEntrypoint)
          ?.toRawHandle();
      if (handle == null) {
        throw const NativeFlowException(
          NativeFlowErrorCode.invalidArgument,
          'backgroundEntrypoint must be a top-level or static function.',
        );
      }
    }
    return _runtime.initialize(config: config, backgroundHandle: handle);
  }

  /// What this device can deliver for every [RuntimeCapability].
  static Future<CapabilityReport> capabilities() => _runtime.capabilities();

  /// Starts the single native runtime with the aggregated requirements of
  /// all attached adapters, then starts the adapters.
  ///
  /// On Android this starts one foreground service and must be called while
  /// the app is in the foreground. Throws [NativeFlowException] with
  /// `permissionRequired` if a required capability (location, microphone)
  /// is not granted.
  static Future<void> start([
    RuntimeOptions options = const RuntimeOptions(),
  ]) => _runtime.start(options);

  /// Stops adapters (in reverse attach order) and the native runtime, and
  /// clears the persisted intent to keep running.
  static Future<void> stop() => _runtime.stop();

  /// Attaches [adapter]. If the runtime is already running the adapter is
  /// started immediately (or recovered, if the runtime predates this
  /// Flutter engine) and the native requirements are updated.
  static Future<RuntimeSession> attach(RuntimeAdapter adapter) =>
      _runtime.attach(adapter);

  /// Stops the adapter with [adapterId], removes it and updates the native
  /// requirements. Throws [NativeFlowException] with `unknownAdapter` if no
  /// such adapter is attached.
  static Future<void> detach(String adapterId) => _runtime.detach(adapterId);

  /// Sessions of all attached adapters, in attach order.
  static List<RuntimeSession> get sessions => _runtime.sessions;

  /// Last known state of the native runtime. The native layer owns it;
  /// Dart mirrors it.
  static RuntimeState get state => _runtime.state;

  /// Emits whenever [state] changes.
  static Stream<RuntimeState> get states => _runtime.states;

  /// Last connectivity reported by the OS.
  static NetworkState get network => _runtime.network;

  /// Emits whenever [network] changes.
  static Stream<NetworkState> get networkChanges => _runtime.networkChanges;

  /// Every runtime event, system and custom, delivered to this engine.
  static RuntimeEventBus get events => _runtime.bus;

  /// See [NativeFlowRuntime.isBackgroundEngine].
  static bool get isBackgroundEngine => _runtime.isBackgroundEngine;

  /// Native notifications. See [NativeFlowNotifications].
  static NativeFlowNotifications get notifications => _runtime.notifications;

  /// Floating overlay window (Android only). See [NativeFlowOverlay].
  static NativeFlowOverlay get overlay => _runtime.overlay;

  /// Live Activities and widget refresh (iOS only). See
  /// [NativeFlowActivities].
  static NativeFlowActivities get activities => _runtime.activities;

  /// Permission status and explicit request flows. See
  /// [NativeFlowPermissions].
  static NativeFlowPermissions get permissions => _runtime.permissions;

  /// The logger NativeFlow writes to. Set [NativeFlowLogger.sink] to route
  /// records into your own logging.
  static NativeFlowLogger get logger => _runtime.logger;

  /// Publishes an application event. See `AdapterContext.emit`.
  static Future<int?> emit(
    String name, {
    Map<String, Object?> payload = const {},
    bool persist = false,
  }) => _runtime.emit(name, payload: payload, persist: persist);

  /// See [RuntimePresentation].
  static Future<void> present(RuntimePresentation presentation) =>
      _runtime.present(presentation);

  /// Asks the OS for a future background window of [kind], no earlier than
  /// [earliestIn] from now.
  ///
  /// iOS uses BGTaskScheduler; Android uses JobScheduler. The OS decides when,
  /// and whether, the task runs. When it does, a
  /// [RuntimeEventType.backgroundTask] event is delivered whose payload has
  /// `taskId` and `kind`; the app must then call [completeBackgroundTask].
  static Future<void> scheduleBackgroundTask({
    BackgroundTaskKind kind = BackgroundTaskKind.refresh,
    Duration earliestIn = const Duration(minutes: 15),
  }) => _runtime.scheduleBackgroundTask(kind: kind, earliestIn: earliestIn);

  /// Tells the OS the background task [taskId] (from the
  /// [RuntimeEventType.backgroundTask] event payload) has finished, with
  /// [success] reporting the outcome. Call it for every such event, before the
  /// OS deadline.
  static Future<void> completeBackgroundTask(
    String taskId, {
    bool success = true,
  }) => _runtime.completeBackgroundTask(taskId, success: success);

  /// Replaces the runtime (e.g. with a fake platform) in tests.
  @visibleForTesting
  static set debugRuntime(NativeFlowRuntime? runtime) => _instance = runtime;
}

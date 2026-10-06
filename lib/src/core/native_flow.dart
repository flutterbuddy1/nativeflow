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
  /// that arrived while Flutter was not running. Safe to call repeatedly.
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
    NativeFlowConfig config = const NativeFlowConfig(),
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

  static Future<void> detach(String adapterId) => _runtime.detach(adapterId);

  static List<RuntimeSession> get sessions => _runtime.sessions;

  static RuntimeState get state => _runtime.state;
  static Stream<RuntimeState> get states => _runtime.states;

  static NetworkState get network => _runtime.network;
  static Stream<NetworkState> get networkChanges => _runtime.networkChanges;

  static RuntimeEventBus get events => _runtime.bus;

  /// See [NativeFlowRuntime.isBackgroundEngine].
  static bool get isBackgroundEngine => _runtime.isBackgroundEngine;

  static NativeFlowNotifications get notifications => _runtime.notifications;
  static NativeFlowOverlay get overlay => _runtime.overlay;
  static NativeFlowActivities get activities => _runtime.activities;
  static NativeFlowPermissions get permissions => _runtime.permissions;
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

  static Future<void> scheduleBackgroundTask({
    BackgroundTaskKind kind = BackgroundTaskKind.refresh,
    Duration earliestIn = const Duration(minutes: 15),
  }) => _runtime.scheduleBackgroundTask(kind: kind, earliestIn: earliestIn);

  static Future<void> completeBackgroundTask(
    String taskId, {
    bool success = true,
  }) => _runtime.completeBackgroundTask(taskId, success: success);

  /// Replaces the runtime (e.g. with a fake platform) in tests.
  @visibleForTesting
  static set debugRuntime(NativeFlowRuntime? runtime) => _instance = runtime;
}

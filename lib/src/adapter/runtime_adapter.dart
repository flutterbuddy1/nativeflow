import 'dart:async';

import '../core/runtime_requirement.dart';
import '../recovery/recovery_policy.dart';
import 'adapter_context.dart';

typedef AdapterCallback = FutureOr<void> Function(AdapterContext context);

/// Your workload, plugged into the NativeFlow runtime.
///
/// An adapter wraps whatever *you* already use — a WebSocket, Socket.IO,
/// MQTT, BLE, a location stream, a sync loop, an AI agent. NativeFlow owns
/// the runtime (service, lifecycle, recovery, events); the adapter owns the
/// protocol, including how to connect and reconnect.
///
/// Use callbacks:
///
/// ```dart
/// RuntimeAdapter(id: 'chat', start: connect, stop: disconnect)
/// ```
///
/// or subclass and override the lifecycle methods.
class RuntimeAdapter {
  RuntimeAdapter({
    required this.id,
    this.requirements = RuntimeRequirements.none,
    this.recoveryPolicy,
    this._start,
    this._stop,
    this._pause,
    this._resume,
    this._recover,
  });

  /// Unique, stable id (`[A-Za-z0-9_.:-]{1,64}`). Used to route events and
  /// to persist runtime state across process death.
  final String id;
  final RuntimeRequirements requirements;

  /// Overrides `NativeFlowConfig.recoveryPolicy` for this adapter.
  final RecoveryPolicy? recoveryPolicy;

  final AdapterCallback? _start, _stop, _pause, _resume, _recover;

  /// Begin work. Throwing schedules recovery per [recoveryPolicy].
  Future<void> start(AdapterContext context) async => _start?.call(context);

  /// Release everything. Errors are logged, never retried.
  Future<void> stop(AdapterContext context) async => _stop?.call(context);

  /// The runtime is being paused by the OS (e.g. iOS suspension). Close
  /// what cannot survive suspension. Defaults to doing nothing.
  Future<void> pause(AdapterContext context) async => _pause?.call(context);

  /// Undo [pause]. Defaults to doing nothing.
  Future<void> resume(AdapterContext context) async => _resume?.call(context);

  /// Re-establish work after a failure, process recreation or engine
  /// hand-off. See [AdapterContext.recoveryReason]. Defaults to [start].
  Future<void> recover(AdapterContext context) async =>
      _recover != null ? _recover(context) : start(context);
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/runtime_session.dart';
import '../core/runtime_state.dart';
import '../events/runtime_event.dart';
import '../logging/logger.dart';
import '../network/network_state.dart';

/// Why [RuntimeAdapter.recover] is being called.
enum RecoveryReason {
  /// The adapter threw or called [AdapterContext.reportFailure].
  adapterFailure,

  /// Connectivity returned while recovery was waiting for it.
  networkRestored,

  /// The native runtime was already running when this adapter attached:
  /// the process or Flutter engine was recreated (app relaunch, Android
  /// service restart, reboot restore, background-engine hand-off).
  runtimeRestored,
}

/// What a running adapter can see and do.
///
/// Subscriptions made through [on] / [onNamed] are cancelled automatically
/// before the next start/recover and on stop, so adapters never leak
/// listeners across restarts.
class AdapterContext {
  /// Creates the context for one session. Created by the runtime.
  AdapterContext(this._session, this._host);

  final RuntimeSession _session;
  final AdapterHost _host;
  final _subscriptions = <StreamSubscription<RuntimeEvent>>[];

  RecoveryReason? _reason;

  /// Id of the adapter this context belongs to.
  String get adapterId => _session.id;

  /// Current state of the native runtime.
  RuntimeState get runtimeState => _host.state;

  /// Last connectivity reported by the OS.
  NetworkState get network => _host.network;

  /// The NativeFlow logger.
  NativeFlowLogger get logger => _host.logger;

  /// Failed attempts since the last successful start (0 on a clean start).
  int get attempt => _session.attempts;

  /// Set while [RuntimeAdapter.recover] runs; `null` during start.
  RecoveryReason? get recoveryReason => _reason;

  /// Listens to system events of [type] until the next restart or stop.
  void on(RuntimeEventType type, void Function(RuntimeEvent event) handler) =>
      _subscriptions.add(_host.events(type).listen(handler));

  /// Listens to events with wire [name] until the next restart or stop.
  void onNamed(String name, void Function(RuntimeEvent event) handler) =>
      _subscriptions.add(_host.named(name).listen(handler));

  /// Publishes an application event tagged with this adapter's id.
  ///
  /// With [persist], the event is written to the native event store first
  /// and is redelivered after process death until acknowledged; returns its
  /// id. Otherwise it is delivered in-memory only and `null` is returned.
  Future<int?> emit(
    String name, {
    Map<String, Object?> payload = const {},
    bool persist = false,
  }) => _host.emit(
    name,
    adapterId: adapterId,
    payload: payload,
    persist: persist,
  );

  /// Tells the runtime this adapter's work broke (socket closed, stream
  /// error). The runtime schedules [RuntimeAdapter.recover] per policy.
  void reportFailure(Object error, [StackTrace? stackTrace]) =>
      _session.reportFailure(error, stackTrace);

  /// Cancels listeners and records [reason] before a start or recovery.
  @internal
  void prepare(RecoveryReason? reason) {
    clearSubscriptions();
    _reason = reason;
  }

  /// Cancels every listener registered through [on] and [onNamed].
  @internal
  void clearSubscriptions() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }
}

/// The slice of the runtime adapters and sessions depend on.
abstract interface class AdapterHost {
  /// Current state of the native runtime.
  RuntimeState get state;

  /// Last connectivity reported by the OS.
  NetworkState get network;

  /// The NativeFlow logger.
  NativeFlowLogger get logger;

  /// Events of system [type].
  Stream<RuntimeEvent> events(RuntimeEventType type);

  /// Events with wire [name].
  Stream<RuntimeEvent> named(String name);

  /// Publishes an application event; see [AdapterContext.emit].
  Future<int?> emit(
    String name, {
    String? adapterId,
    Map<String, Object?> payload,
    bool persist,
  });

  /// Delivers [event] to local listeners without persisting it.
  void dispatchLocal(RuntimeEvent event);
}

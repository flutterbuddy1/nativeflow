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
  AdapterContext(this._session, this._host);

  final RuntimeSession _session;
  final AdapterHost _host;
  final _subscriptions = <StreamSubscription<RuntimeEvent>>[];

  RecoveryReason? _reason;

  String get adapterId => _session.id;
  RuntimeState get runtimeState => _host.state;
  NetworkState get network => _host.network;
  NativeFlowLogger get logger => _host.logger;

  /// Failed attempts since the last successful start (0 on a clean start).
  int get attempt => _session.attempts;

  /// Set while [RuntimeAdapter.recover] runs; `null` during start.
  RecoveryReason? get recoveryReason => _reason;

  void on(RuntimeEventType type, void Function(RuntimeEvent event) handler) =>
      _subscriptions.add(_host.events(type).listen(handler));

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

  @internal
  void prepare(RecoveryReason? reason) {
    clearSubscriptions();
    _reason = reason;
  }

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
  RuntimeState get state;
  NetworkState get network;
  NativeFlowLogger get logger;
  Stream<RuntimeEvent> events(RuntimeEventType type);
  Stream<RuntimeEvent> named(String name);
  Future<int?> emit(
    String name, {
    String? adapterId,
    Map<String, Object?> payload,
    bool persist,
  });
  void dispatchLocal(RuntimeEvent event);
}

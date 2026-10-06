import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../adapter/adapter_context.dart';
import '../adapter/runtime_adapter.dart';
import '../events/runtime_event.dart';
import '../recovery/recovery_policy.dart';
import 'runtime_state.dart';

/// The live record of one attached [RuntimeAdapter]: its state, failure
/// count and recovery schedule. All adapters share one native runtime.
class RuntimeSession {
  /// Creates a session for [adapter] hosted by [host]. Uses the adapter's
  /// own [RuntimeAdapter.recoveryPolicy], or [defaultPolicy] if it has none.
  /// Sessions are created by the runtime when an adapter is attached.
  RuntimeSession(
    this.adapter,
    AdapterHost host, {
    required RecoveryPolicy defaultPolicy,
    this._random,
  }) : _host = host,
       _policy = adapter.recoveryPolicy ?? defaultPolicy {
    context = AdapterContext(this, host);
  }

  /// The adapter this session runs.
  final RuntimeAdapter adapter;
  final AdapterHost _host;
  final RecoveryPolicy _policy;
  final Random? _random;

  /// The context passed to every lifecycle call of [adapter].
  @internal
  late final AdapterContext context;

  final _states = StreamController<SessionState>.broadcast();
  SessionState _state = SessionState.idle;
  int _attempts = 0;
  Object? _lastError;
  Timer? _retry;

  /// Bumped on stop so in-flight async work from a previous lifecycle
  /// cannot overwrite the state of the current one.
  int _generation = 0;

  /// The adapter's id.
  String get id => adapter.id;

  /// Current lifecycle state.
  SessionState get state => _state;

  /// Emits whenever [state] changes.
  Stream<SessionState> get states => _states.stream;

  /// Failed attempts since the last successful start or recovery.
  int get attempts => _attempts;

  /// The most recent failure, or `null` after a successful start.
  Object? get lastError => _lastError;

  /// Runs [RuntimeAdapter.start]; a failure schedules recovery.
  @internal
  Future<void> start() => _run(SessionState.starting, null, adapter.start);

  /// Runs [RuntimeAdapter.recover] with [reason]. Does nothing while
  /// stopping or stopped.
  @internal
  Future<void> recover(RecoveryReason reason) {
    if (_state == SessionState.stopping || _state == SessionState.stopped) {
      return Future.value();
    }
    return _run(SessionState.recovering, reason, adapter.recover);
  }

  /// Cancels pending retries and runs [RuntimeAdapter.stop]. Errors are
  /// logged, not retried.
  @internal
  Future<void> stop() async {
    _cancelRetry();
    final gen = ++_generation;
    if (_state == SessionState.idle || _state == SessionState.stopped) {
      _transition(SessionState.stopped);
      return;
    }
    _transition(SessionState.stopping);
    try {
      await adapter.stop(context);
    } catch (e, st) {
      _host.logger.error(
        'Adapter stop failed',
        error: e,
        fields: {'adapter': id},
      );
      assert(() {
        debugPrintStack(stackTrace: st, label: '$e');
        return true;
      }());
    }
    context.clearSubscriptions();
    if (gen == _generation) _transition(SessionState.stopped);
  }

  /// Runs [RuntimeAdapter.pause] if running. Errors are logged.
  @internal
  Future<void> pause() async {
    if (_state != SessionState.running) return;
    try {
      await adapter.pause(context);
    } catch (e) {
      _host.logger.warning('Adapter pause failed', {
        'adapter': id,
        'error': '$e',
      });
    }
    if (_state == SessionState.running) _transition(SessionState.paused);
  }

  /// Runs [RuntimeAdapter.resume] if paused; a failure schedules recovery.
  @internal
  Future<void> resume() async {
    if (_state != SessionState.paused) return;
    final gen = _generation;
    try {
      await adapter.resume(context);
      if (gen == _generation && _state == SessionState.paused) {
        _transition(SessionState.running);
      }
    } catch (e, st) {
      if (gen == _generation) _fail(e, st);
    }
  }

  /// Connectivity returned; resume a recovery that was waiting for it.
  @internal
  void onNetworkAvailable() {
    if (_state == SessionState.waitingForNetwork) {
      recover(RecoveryReason.networkRestored);
    }
  }

  /// Records a failure reported by the adapter and schedules recovery.
  /// Ignored unless running or paused.
  @internal
  void reportFailure(Object error, [StackTrace? stackTrace]) {
    if (_state == SessionState.running || _state == SessionState.paused) {
      _fail(error, stackTrace);
    }
  }

  /// Cancels retries and subscriptions and closes [states].
  @internal
  void dispose() {
    _cancelRetry();
    context.clearSubscriptions();
    _states.close();
  }

  Future<void> _run(
    SessionState entry,
    RecoveryReason? reason,
    Future<void> Function(AdapterContext) body,
  ) async {
    _cancelRetry();
    final gen = _generation;
    if (_state != entry) _transition(entry);
    context.prepare(reason);
    try {
      await body(context);
      if (gen != _generation) return;
      _attempts = 0;
      _lastError = null;
      _transition(SessionState.running);
    } catch (e, st) {
      if (gen == _generation) _fail(e, st);
    }
  }

  void _fail(Object error, StackTrace? stackTrace) {
    _lastError = error;
    _attempts++;
    _host.logger.warning('Adapter failed', {
      'adapter': id,
      'attempt': _attempts,
      'error': error.runtimeType.toString(),
    });
    if (!_policy.allowsAttempt(_attempts)) {
      _transition(SessionState.failed);
      _host.dispatchLocal(
        RuntimeEvent(
          name: RuntimeEventType.adapterFailed.wireName,
          adapterId: id,
          payload: {'attempts': _attempts, 'error': '$error'},
        ),
      );
      return;
    }
    _transition(SessionState.recovering);
    if (_policy.waitForNetwork && !_host.network.connected) {
      _transition(SessionState.waitingForNetwork);
      return;
    }
    final delay = _policy.delayFor(_attempts, _random);
    _retry = Timer(delay, () => recover(RecoveryReason.adapterFailure));
  }

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
  }

  void _transition(SessionState next) {
    if (next == _state) return;
    if (!_state.canTransitionTo(next)) {
      _host.logger.error(
        'Illegal session transition',
        fields: {'adapter': id, 'from': _state.name, 'to': next.name},
      );
      assert(false, 'Illegal session transition $_state -> $next for $id');
      return;
    }
    _state = next;
    _host.logger.debug('Session state', {'adapter': id, 'state': next.name});
    _states.add(next);
  }
}

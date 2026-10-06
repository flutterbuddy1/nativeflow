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
  RuntimeSession(
    this.adapter,
    AdapterHost host, {
    required RecoveryPolicy defaultPolicy,
    this._random,
  }) : _host = host,
       _policy = adapter.recoveryPolicy ?? defaultPolicy {
    context = AdapterContext(this, host);
  }

  final RuntimeAdapter adapter;
  final AdapterHost _host;
  final RecoveryPolicy _policy;
  final Random? _random;

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

  String get id => adapter.id;
  SessionState get state => _state;
  Stream<SessionState> get states => _states.stream;
  int get attempts => _attempts;
  Object? get lastError => _lastError;

  @internal
  Future<void> start() => _run(SessionState.starting, null, adapter.start);

  @internal
  Future<void> recover(RecoveryReason reason) {
    if (_state == SessionState.stopping || _state == SessionState.stopped) {
      return Future.value();
    }
    return _run(SessionState.recovering, reason, adapter.recover);
  }

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

  @internal
  void reportFailure(Object error, [StackTrace? stackTrace]) {
    if (_state == SessionState.running || _state == SessionState.paused) {
      _fail(error, stackTrace);
    }
  }

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

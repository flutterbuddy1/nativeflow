import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../adapter/adapter_context.dart';
import '../adapter/runtime_adapter.dart';
import '../events/runtime_event.dart';
import '../events/runtime_event_bus.dart';
import '../logging/logger.dart';
import '../network/network_state.dart';
import '../notification/notifications.dart';
import '../overlay/overlay.dart';
import '../permissions/permissions.dart';
import '../platform/native_flow_platform.dart';
import '../presentation/presentation.dart';
import '../recovery/recovery_policy.dart';
import 'errors.dart';
import 'runtime_capability.dart';
import 'runtime_requirement.dart';
import 'runtime_session.dart';
import 'runtime_state.dart';
import 'validation.dart';

/// Process-wide settings passed to `NativeFlow.initialize`.
@immutable
class NativeFlowConfig {
  const NativeFlowConfig({
    this.logVerbosity = LogVerbosity.errors,
    this.recoveryPolicy = const RecoveryPolicy(),
  });

  final LogVerbosity logVerbosity;

  /// Default for adapters that do not set their own policy.
  final RecoveryPolicy recoveryPolicy;
}

/// iOS BGTaskScheduler task kinds. `refresh` is short (~30 s);
/// `processing` is longer but typically runs while charging and idle.
enum BackgroundTaskKind { refresh, processing }

/// Options for `NativeFlow.start`.
@immutable
class RuntimeOptions {
  const RuntimeOptions({
    this.notification = const ForegroundNotification(),
    this.persistent = true,
    this.restoreOnBoot = false,
  });

  /// Android: the foreground-service notification (required by the OS).
  /// iOS: ignored.
  final ForegroundNotification notification;

  /// Android: ask the OS to restart the runtime if it kills the process
  /// (`START_STICKY`). Best effort; OEM policies may still prevent it.
  final bool persistent;

  /// Restore the runtime after reboot if it was running at shutdown. This
  /// records the user's explicit intent; it is cleared by [NativeFlow.stop].
  final bool restoreOnBoot;

  Map<String, Object?> toMap() => {
    'notification': notification.toMap(),
    'persistent': persistent,
    'restoreOnBoot': restoreOnBoot,
  };
}

/// The engine behind the `NativeFlow` facade. One per Flutter engine.
class NativeFlowRuntime implements AdapterHost {
  NativeFlowRuntime(this.platform, {NativeFlowLogger? logger, this._random})
    : logger = logger ?? NativeFlowLogger() {
    notifications = NativeFlowNotifications(this);
    overlay = NativeFlowOverlay(this);
    activities = NativeFlowActivities(this);
    permissions = NativeFlowPermissions(this);
  }

  final NativeFlowPlatform platform;
  @override
  final NativeFlowLogger logger;
  final Random? _random;
  final bus = RuntimeEventBus();

  late final NativeFlowNotifications notifications;
  late final NativeFlowOverlay overlay;
  late final NativeFlowActivities activities;
  late final NativeFlowPermissions permissions;

  final _sessions = <String, RuntimeSession>{};
  final _stateController = StreamController<RuntimeState>.broadcast();
  final _networkController = StreamController<NetworkState>.broadcast();
  RuntimeState _state = RuntimeState.stopped;
  NetworkState _network = NetworkState.unknown;
  NativeFlowConfig _config = const NativeFlowConfig();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _isBackgroundEngine = false;

  /// True once this isolate started the runtime itself; adapters attached
  /// to a runtime that was already running get `recover` instead.
  bool _startedHere = false;

  StreamSubscription<List<Object?>>? _eventSubscription;
  int _lastDelivered = 0;
  List<Object?>? _bufferedWhileDraining;
  Future<void> _lock = Future.value();

  @override
  RuntimeState get state => _state;
  Stream<RuntimeState> get states => _stateController.stream;
  @override
  NetworkState get network => _network;
  Stream<NetworkState> get networkChanges => _networkController.stream;
  List<RuntimeSession> get sessions => List.unmodifiable(_sessions.values);
  bool get isInitialized => _initialized;

  /// True inside the Android background engine NativeFlow spawned to run
  /// adapters while no UI is attached.
  bool get isBackgroundEngine => _isBackgroundEngine;

  RuntimeRequirements get requirements => RuntimeRequirements.merge(
    _sessions.values.map((s) => s.adapter.requirements),
  );

  // ---------------------------------------------------------------- lifecycle

  Future<void> initialize({
    NativeFlowConfig config = const NativeFlowConfig(),
    int? backgroundHandle,
  }) {
    _config = config;
    logger.verbosity = config.logVerbosity;
    return _initializing ??= () async {
      try {
        await _initialize(backgroundHandle);
      } catch (_) {
        _initializing = null;
        await _eventSubscription?.cancel();
        _eventSubscription = null;
        rethrow;
      }
    }();
  }

  Future<void> _initialize(int? backgroundHandle) async {
    // Subscribe before asking for the snapshot so nothing emitted in between
    // is lost; anything arriving while we drain the backlog is buffered.
    _bufferedWhileDraining = [];
    _eventSubscription = platform.events.listen(
      _onBatch,
      onError: (Object e) =>
          logger.error('Native event stream error', error: e),
    );
    platform.setCallHandler(_onNativeCall);

    final snapshot = await platform.invoke<Map<Object?, Object?>>(
      NativeMethod.initialize,
      {
        'logLevel': config.logVerbosity.index,
        'backgroundHandle': ?backgroundHandle,
      },
    );
    _applySnapshot(snapshot ?? const {});
    await _drainPending();
    _initialized = true;
    logger.info('Initialized', {
      'state': _state.name,
      'backgroundEngine': _isBackgroundEngine,
    });
  }

  NativeFlowConfig get config => _config;

  void _applySnapshot(Map<Object?, Object?> s) {
    _setState(RuntimeState.parse(s['state']));
    _setNetwork(NetworkState.fromMap(s['network'] as Map<Object?, Object?>?));
    _isBackgroundEngine = s['backgroundEngine'] == true;
    _lastDelivered = (s['lastAck'] as num?)?.toInt() ?? 0;
  }

  Future<void> _drainPending() async {
    while (true) {
      final batch = await platform.invoke<List<Object?>>(
        NativeMethod.pendingEvents,
        {'after': _lastDelivered, 'limit': 100},
      );
      if (batch == null || batch.isEmpty) break;
      await _deliver(batch);
      if (batch.length < 100) break;
    }
    final buffered = _bufferedWhileDraining!;
    _bufferedWhileDraining = null;
    if (buffered.isNotEmpty) await _deliver(buffered);
  }

  Future<void> start([RuntimeOptions options = const RuntimeOptions()]) =>
      _serial(() async {
        _ensureInitialized();
        final reported = await platform.invoke<String>(NativeMethod.start, {
          'requirements': requirements.toMap(),
          ...options.toMap(),
        });
        _setState(RuntimeState.parse(reported ?? RuntimeState.running.name));
        _startedHere = true;
        for (final s in _sessions.values) {
          switch (s.state) {
            case SessionState.idle ||
                SessionState.stopped ||
                SessionState.failed:
              await s.start();
            case SessionState.paused:
              await s.resume();
            default:
          }
        }
      });

  Future<void> stop() => _serial(() async {
    _ensureInitialized();
    await _stopSessions();
    final reported = await platform.invoke<String>(NativeMethod.stop);
    _setState(RuntimeState.parse(reported ?? RuntimeState.stopped.name));
    _startedHere = false;
  });

  Future<RuntimeSession> attach(RuntimeAdapter adapter) => _serial(() async {
    _ensureInitialized();
    validateId(adapter.id, 'adapter id');
    if (_sessions.containsKey(adapter.id)) {
      throw NativeFlowException(
        NativeFlowErrorCode.duplicateAdapter,
        'An adapter with id "${adapter.id}" is already attached.',
      );
    }
    final session = RuntimeSession(
      adapter,
      this,
      defaultPolicy: _config.recoveryPolicy,
      random: _random,
    );
    _sessions[adapter.id] = session;
    if (_state.isActive) {
      try {
        await _pushRequirements();
      } catch (_) {
        _sessions.remove(adapter.id)?.dispose();
        rethrow;
      }
      if (_startedHere) {
        await session.start();
      } else {
        await session.recover(RecoveryReason.runtimeRestored);
      }
    }
    return session;
  });

  Future<void> detach(String adapterId) => _serial(() async {
    _ensureInitialized();
    final session = _sessions[adapterId];
    if (session == null) {
      throw NativeFlowException(
        NativeFlowErrorCode.unknownAdapter,
        'No adapter with id "$adapterId" is attached.',
      );
    }
    await session.stop();
    _sessions.remove(adapterId);
    session.dispose();
    if (_state.isActive) await _pushRequirements();
  });

  Future<CapabilityReport> capabilities() async {
    _ensureInitialized();
    final raw = await platform.invoke<Map<Object?, Object?>>(
      NativeMethod.capabilities,
    );
    return {
      for (final c in RuntimeCapability.values)
        c: CapabilityStatus.parse(raw?[c.name]),
    };
  }

  Future<void> present(RuntimePresentation presentation) {
    _ensureInitialized();
    return platform.invoke<void>(NativeMethod.present, presentation.toMap());
  }

  /// iOS: asks BGTaskScheduler for a future background window. The OS
  /// decides when (and whether) it runs; it arrives as a
  /// [RuntimeEventType.backgroundTask] event.
  Future<void> scheduleBackgroundTask({
    BackgroundTaskKind kind = BackgroundTaskKind.refresh,
    Duration earliestIn = const Duration(minutes: 15),
  }) {
    _ensureInitialized();
    return platform.invoke<void>(NativeMethod.scheduleBackgroundTask, {
      'kind': kind.name,
      'earliestSeconds': earliestIn.inSeconds,
    });
  }

  /// Must be called for every [RuntimeEventType.backgroundTask] event,
  /// before the OS deadline, with `payload['taskId']`.
  Future<void> completeBackgroundTask(String taskId, {bool success = true}) {
    _ensureInitialized();
    return platform.invoke<void>(NativeMethod.completeBackgroundTask, {
      'taskId': taskId,
      'success': success,
    });
  }

  // ------------------------------------------------------------------ events

  @override
  Stream<RuntimeEvent> events(RuntimeEventType type) => bus.on(type);

  @override
  Stream<RuntimeEvent> named(String name) => bus.named(name);

  @override
  Future<int?> emit(
    String name, {
    String? adapterId,
    Map<String, Object?> payload = const {},
    bool persist = false,
  }) async {
    validateId(name, 'event name');
    if (name.startsWith('nativeflow.')) {
      throw const NativeFlowException(
        NativeFlowErrorCode.invalidArgument,
        'Event names starting with "nativeflow." are reserved.',
      );
    }
    validatePayload(payload);
    if (!persist) {
      dispatchLocal(
        RuntimeEvent(name: name, adapterId: adapterId, payload: payload),
      );
      return null;
    }
    _ensureInitialized();
    // The native store echoes the event back through the event channel, so
    // it is delivered (and acknowledged) by the same path as native events.
    return platform.invoke<int>(NativeMethod.appendEvent, {
      'type': name,
      'adapterId': adapterId,
      'payload': payload,
    });
  }

  @override
  void dispatchLocal(RuntimeEvent event) => bus.dispatch(event);

  void _onBatch(List<Object?> batch) {
    final buffer = _bufferedWhileDraining;
    if (buffer != null) {
      buffer.addAll(batch);
    } else {
      _deliver(batch);
    }
  }

  Future<void> _deliver(List<Object?> batch) async {
    var maxPersisted = 0;
    for (final raw in batch) {
      final event = RuntimeEvent.fromMap(raw! as Map<Object?, Object?>);
      final id = event.id;
      if (id != null) {
        if (id <= _lastDelivered) continue; // already delivered (redelivery)
        _lastDelivered = id;
        maxPersisted = id;
      }
      _applySystemEvent(event);
      bus.dispatch(event);
    }
    if (maxPersisted > 0) {
      // ponytail: auto-ack after synchronous dispatch (at-least-once up to
      // the listener returning). Add manual ack mode if apps need to ack
      // after async processing.
      try {
        await platform.invoke<void>(NativeMethod.ackEvents, {
          'upTo': maxPersisted,
        });
      } on NativeFlowException catch (e) {
        logger.warning('Event ack failed; events will be redelivered', {
          'code': e.code.name,
        });
      }
    }
  }

  void _applySystemEvent(RuntimeEvent event) {
    switch (event.type) {
      case RuntimeEventType.runtimeStarted:
        _setState(RuntimeState.running);
      case RuntimeEventType.runtimeStopped:
        _setState(RuntimeState.stopped);
      case RuntimeEventType.runtimeInterrupted:
        _setState(RuntimeState.interrupted);
        _forEachSession((s) => s.pause());
      case RuntimeEventType.runtimeRecovered:
        _setState(RuntimeState.running);
        _forEachSession((s) {
          if (s.state == SessionState.idle || s.state == SessionState.paused) {
            return s.recover(RecoveryReason.runtimeRestored);
          }
          return Future.value();
        });
      case RuntimeEventType.runtimePaused:
        _forEachSession((s) => s.pause());
      case RuntimeEventType.runtimeResumed:
        _forEachSession((s) => s.resume());
      case RuntimeEventType.networkAvailable ||
          RuntimeEventType.networkLost ||
          RuntimeEventType.networkChanged:
        _setNetwork(NetworkState.fromMap(event.payload));
      default:
    }
  }

  void _forEachSession(Future<void> Function(RuntimeSession) action) {
    for (final s in _sessions.values.toList()) {
      action(s);
    }
  }

  Future<Object?> _onNativeCall(String method) async {
    if (method == NativeMethod.release) {
      // Another engine takes over; stop adapters here but leave the native
      // runtime running.
      await _serial(_stopSessions);
      return null;
    }
    throw MissingPluginException(method);
  }

  // ----------------------------------------------------------------- helpers

  Future<void> _stopSessions() async {
    for (final s in _sessions.values.toList().reversed) {
      await s.stop();
    }
  }

  Future<void> _pushRequirements() => platform.invoke<void>(
    NativeMethod.setRequirements,
    {'requirements': requirements.toMap()},
  );

  void _setState(RuntimeState next) {
    if (next == _state) return;
    _state = next;
    logger.debug('Runtime state', {'state': next.name});
    _stateController.add(next);
  }

  void _setNetwork(NetworkState next) {
    final wasConnected = _network.connected;
    if (next == _network) return;
    _network = next;
    _networkController.add(next);
    if (next.connected && !wasConnected) {
      for (final s in _sessions.values) {
        s.onNetworkAvailable();
      }
    }
  }

  void ensureInitialized() => _ensureInitialized();

  void _ensureInitialized() {
    if (!_initialized) {
      throw const NativeFlowException(
        NativeFlowErrorCode.notInitialized,
        'Call NativeFlow.initialize() first.',
      );
    }
  }

  /// Runs lifecycle operations one at a time, in call order.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _lock.then((_) => op());
    _lock = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    await _stateController.close();
    await _networkController.close();
  }
}

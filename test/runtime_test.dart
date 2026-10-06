import 'package:flutter_test/flutter_test.dart';
import 'package:nativeflow/nativeflow.dart';
import 'package:nativeflow/src/platform/native_flow_platform.dart';

import 'fake_platform.dart';

const _fast = RecoveryPolicy(
  initialDelay: Duration.zero,
  maxDelay: Duration.zero,
  jitter: 0,
  maxAttempts: 3,
);

const _online = {
  'network': {'connected': true, 'type': 'wifi'},
};

/// Records lifecycle calls; fails `start` the first [failures] times.
class RecordingAdapter extends RuntimeAdapter {
  RecordingAdapter(
    String id, {
    this.failures = 0,
    super.requirements,
    super.recoveryPolicy = _fast,
  }) : super(id: id);

  int failures;
  final log = <String>[];
  AdapterContext? lastContext;

  @override
  Future<void> start(AdapterContext context) async {
    lastContext = context;
    log.add('start');
    if (failures > 0) {
      failures--;
      throw StateError('boom');
    }
  }

  @override
  Future<void> stop(AdapterContext context) async => log.add('stop');
  @override
  Future<void> pause(AdapterContext context) async => log.add('pause');
  @override
  Future<void> resume(AdapterContext context) async => log.add('resume');
  @override
  Future<void> recover(AdapterContext context) async {
    log.add('recover:${context.recoveryReason!.name}');
    try {
      await start(context);
    } finally {
      log.removeLast(); // count recover, not the inner start
    }
  }
}

void main() {
  late FakePlatform platform;
  late NativeFlowRuntime runtime;

  Future<void> init([Map<String, Object?> snapshot = _online]) async {
    platform = FakePlatform(snapshot: snapshot);
    runtime = NativeFlowRuntime(platform);
    await runtime.initialize(
      config: const NativeFlowConfig(recoveryPolicy: _fast),
    );
  }

  tearDown(() => runtime.dispose());

  test('operations before initialize throw notInitialized', () async {
    runtime = NativeFlowRuntime(FakePlatform());
    expect(
      () => runtime.start(),
      throwsA(
        isA<NativeFlowException>().having(
          (e) => e.code,
          'code',
          NativeFlowErrorCode.notInitialized,
        ),
      ),
    );
  });

  test('initialize applies snapshot and is idempotent', () async {
    await init({
      'state': 'running',
      'network': {'connected': true, 'type': 'cellular', 'metered': true},
      'backgroundEngine': true,
    });
    await runtime.initialize();
    expect(
      platform.methods.where((m) => m == NativeMethod.initialize),
      hasLength(1),
    );
    expect(runtime.state, RuntimeState.running);
    expect(
      runtime.network,
      const NetworkState(
        connected: true,
        type: NetworkType.cellular,
        metered: true,
      ),
    );
    expect(runtime.isBackgroundEngine, isTrue);
  });

  test(
    'initialize drains events stored while Flutter was away, then acks',
    () async {
      platform = FakePlatform(snapshot: {'lastAck': 1});
      platform.pending.addAll([
        {'id': 1, 'type': 'old', 'ts': 0},
        {
          'id': 2,
          'type': 'nativeflow.notification.action',
          'ts': 0,
          'payload': {'actionId': 'accept'},
        },
        {'id': 3, 'type': 'ride.offer', 'ts': 0},
      ]);
      runtime = NativeFlowRuntime(platform);
      final seen = <String>[];
      runtime.bus.stream.listen((e) => seen.add(e.name));
      await runtime.initialize();
      expect(seen, ['nativeflow.notification.action', 'ride.offer']);
      expect(platform.lastArgs(NativeMethod.ackEvents), {'upTo': 3});
    },
  );

  test('redelivered events are de-duplicated by id', () async {
    await init();
    final seen = <int?>[];
    runtime.bus.stream.listen((e) => seen.add(e.id));
    platform.push([
      {'id': 5, 'type': 'x', 'ts': 0},
    ]);
    platform.push([
      {'id': 5, 'type': 'x', 'ts': 0},
      {'id': 6, 'type': 'x', 'ts': 0},
    ]);
    await settle();
    expect(seen, [5, 6]);
  });

  test(
    'start aggregates requirements into ONE native start, then starts adapters',
    () async {
      await init();
      final a = RecordingAdapter(
        'socket',
        requirements: const RuntimeRequirements(
          capabilities: {RuntimeCapability.network},
        ),
      );
      final b = RecordingAdapter(
        'gps',
        requirements: const RuntimeRequirements(
          capabilities: {RuntimeCapability.location},
        ),
      );
      await runtime.attach(a);
      await runtime.attach(b);
      expect(platform.methods, isNot(contains(NativeMethod.start)));

      await runtime.start(const RuntimeOptions(restoreOnBoot: true));
      expect(
        platform.methods.where((m) => m == NativeMethod.start),
        hasLength(1),
      );
      final args = platform.lastArgs(NativeMethod.start)!;
      expect((args['requirements'] as Map)['capabilities'], [
        'location',
        'network',
      ]);
      expect(args['restoreOnBoot'], isTrue);
      expect(a.log, ['start']);
      expect(b.log, ['start']);
      expect(
        runtime.sessions.map((s) => s.state),
        everyElement(SessionState.running),
      );
    },
  );

  test(
    'stop stops adapters in reverse order before the native runtime',
    () async {
      await init();
      final order = <String>[];
      for (final id in ['first', 'second']) {
        await runtime.attach(
          RuntimeAdapter(id: id, stop: (_) => order.add(id)),
        );
      }
      await runtime.start();
      await runtime.stop();
      expect(order, ['second', 'first']);
      expect(platform.methods.last, NativeMethod.stop);
      expect(runtime.state, RuntimeState.stopped);
      expect(
        runtime.sessions.map((s) => s.state),
        everyElement(SessionState.stopped),
      );
    },
  );

  test(
    'attach while running starts the adapter and updates native requirements',
    () async {
      await init();
      await runtime.start();
      final a = RecordingAdapter(
        'late',
        requirements: const RuntimeRequirements(
          capabilities: {RuntimeCapability.overlay},
        ),
      );
      await runtime.attach(a);
      expect(a.log, ['start']);
      expect(platform.lastArgs(NativeMethod.setRequirements), {
        'requirements': {
          'capabilities': ['overlay'],
        },
      });
    },
  );

  test('attach to a runtime that predates this engine calls recover(runtimeRestored)', () async {
    await init({..._online, 'state': 'running'});
    final a = RecordingAdapter('socket');
    await runtime.attach(a);
    expect(a.log, ['recover:runtimeRestored']);
  });

  test('attach rejects duplicate and invalid ids; failed requirement push rolls back', () async {
    await init();
    await runtime.attach(RuntimeAdapter(id: 'a'));
    expect(
      () => runtime.attach(RuntimeAdapter(id: 'a')),
      throwsA(isA<NativeFlowException>()),
    );
    expect(
      () => runtime.attach(RuntimeAdapter(id: 'bad id')),
      throwsA(isA<NativeFlowException>()),
    );

    await runtime.start();
    platform.handlers[NativeMethod.setRequirements] = (_) =>
        throw const NativeFlowException(
          NativeFlowErrorCode.permissionRequired,
          'location',
        );
    await expectLater(
      runtime.attach(RuntimeAdapter(id: 'gps')),
      throwsA(isA<NativeFlowException>()),
    );
    expect(runtime.sessions.map((s) => s.id), ['a']);
  });

  test('failed start is retried with recover until it succeeds', () async {
    await init();
    final a = RecordingAdapter('flaky', failures: 2);
    final session = await runtime.attach(a);
    await runtime.start();
    await settle();
    expect(a.log, [
      'start',
      'recover:adapterFailure',
      'recover:adapterFailure',
    ]);
    expect(session.state, SessionState.running);
    expect(session.attempts, 0);
  });

  test('recovery gives up after maxAttempts and emits adapterFailed', () async {
    await init();
    final failed = <RuntimeEvent>[];
    runtime.bus.on(RuntimeEventType.adapterFailed).listen(failed.add);
    final session = await runtime.attach(
      RecordingAdapter('dead', failures: 100),
    );
    await runtime.start();
    await settle(30);
    expect(session.state, SessionState.failed);
    expect(failed.single.adapterId, 'dead');
    expect(failed.single.payload['attempts'], 4);
  });

  test(
    'recovery waits for the network, then resumes on networkAvailable',
    () async {
      await init({
        'network': {'connected': false},
      });
      final a = RecordingAdapter('socket', failures: 1);
      final session = await runtime.attach(a);
      await runtime.start();
      await settle();
      expect(session.state, SessionState.waitingForNetwork);
      expect(a.log, ['start']);

      platform.pushSystem(RuntimeEventType.networkAvailable, {
        'connected': true,
        'type': 'wifi',
      });
      await settle();
      expect(a.log, ['start', 'recover:networkRestored']);
      expect(session.state, SessionState.running);
      expect(runtime.network.type, NetworkType.wifi);
    },
  );

  test('reportFailure from the adapter triggers recovery', () async {
    await init();
    final a = RecordingAdapter('socket');
    await runtime.attach(a);
    await runtime.start();
    a.lastContext!.reportFailure(StateError('socket closed'));
    await settle();
    expect(a.log, ['start', 'recover:adapterFailure']);
  });

  test('context subscriptions are cancelled on restart and stop', () async {
    await init();
    var hits = 0;
    final adapter = RuntimeAdapter(
      id: 'listener',
      start: (c) => c.onNamed('ping', (_) => hits++),
    );
    await runtime.attach(adapter);
    await runtime.start();
    await runtime.emit('ping');
    expect(hits, 1);
    runtime.sessions.single.context.reportFailure('x');
    await settle();
    await runtime.emit('ping');
    expect(hits, 2, reason: 'old subscription must not double-count');
    await runtime.stop();
    await runtime.emit('ping');
    expect(hits, 2);
  });

  test(
    'interrupted/recovered/paused/resumed drive adapter lifecycle',
    () async {
      await init();
      final a = RecordingAdapter('w');
      await runtime.attach(a);
      await runtime.start();

      platform.pushSystem(RuntimeEventType.runtimePaused);
      await settle();
      platform.pushSystem(RuntimeEventType.runtimeResumed);
      await settle();
      platform.pushSystem(RuntimeEventType.runtimeInterrupted);
      await settle();
      expect(runtime.state, RuntimeState.interrupted);
      platform.pushSystem(RuntimeEventType.runtimeRecovered);
      await settle();
      expect(a.log, [
        'start',
        'pause',
        'resume',
        'pause',
        'recover:runtimeRestored',
      ]);
      expect(runtime.state, RuntimeState.running);
    },
  );

  test('native release stops adapters but not the runtime', () async {
    await init();
    final a = RecordingAdapter('w');
    await runtime.attach(a);
    await runtime.start();
    await platform.callHandler!(NativeMethod.release);
    expect(a.log, ['start', 'stop']);
    expect(platform.methods, isNot(contains(NativeMethod.stop)));
  });

  test('persisted emit goes through the native store and is acked', () async {
    await init();
    final seen = <RuntimeEvent>[];
    runtime.bus.named('ride.offer').listen(seen.add);
    final id = await runtime.emit(
      'ride.offer',
      payload: {'ride': 42},
      persist: true,
    );
    await settle();
    expect(id, 1);
    expect(seen.single.id, 1);
    expect(seen.single.payload, {'ride': 42});
    expect(platform.lastArgs(NativeMethod.ackEvents), {'upTo': 1});
    expect(
      () => runtime.emit('nativeflow.fake'),
      throwsA(isA<NativeFlowException>()),
    );
  });

  test('requestRequired only asks for permissionRequired capabilities of attached adapters', () async {
    await init();
    await runtime.attach(
      RuntimeAdapter(
        id: 'driver',
        requirements: const RuntimeRequirements(
          capabilities: {RuntimeCapability.location, RuntimeCapability.network},
        ),
      ),
    );
    platform.handlers[NativeMethod.permissionStatus] = (args) =>
        args!['capability'] == 'location' ? 'permissionRequired' : 'supported';
    platform.handlers[NativeMethod.requestPermission] = (_) => 'supported';

    final report = await runtime.permissions.requestRequired();
    expect(report, {
      RuntimeCapability.location: CapabilityStatus.supported,
      RuntimeCapability.network: CapabilityStatus.supported,
    });
    final requested = platform.calls
        .where((c) => c.$1 == NativeMethod.requestPermission)
        .map((c) => c.$2!['capability']);
    expect(requested, ['location']);
  });

  test(
    'capabilities() reports every capability, unknown as unavailable',
    () async {
      await init();
      platform.handlers[NativeMethod.capabilities] = (_) => {
        'overlay': 'permissionRequired',
        'network': 'supported',
      };
      final caps = await runtime.capabilities();
      expect(caps, hasLength(RuntimeCapability.values.length));
      expect(
        caps[RuntimeCapability.overlay],
        CapabilityStatus.permissionRequired,
      );
      expect(
        caps[RuntimeCapability.liveActivity],
        CapabilityStatus.unavailable,
      );
    },
  );

  test('lifecycle calls are serialized', () async {
    await init();
    final order = <String>[];
    await runtime.attach(
      RuntimeAdapter(
        id: 'slow',
        start: (_) async {
          order.add('start-begin');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          order.add('start-end');
        },
        stop: (_) => order.add('stop'),
      ),
    );
    final s = runtime.start();
    final t = runtime.stop();
    await Future.wait([s, t]);
    expect(order, ['start-begin', 'start-end', 'stop']);
  });
}

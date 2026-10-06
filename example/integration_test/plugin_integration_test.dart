// Exercises every public NativeFlow API against the real native runtime.
//
//   flutter test integration_test -d <device>
//
// Platform-specific APIs are asserted to work on their platform and to fail
// honestly (`unavailable`) on the other. On Android, grant overlay /
// notification permissions while the test runs to exercise those paths
// (see doc/testing.md); without grants they are asserted to report
// `permissionRequired` instead.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nativeflow/nativeflow.dart';

final isAndroid = defaultTargetPlatform == TargetPlatform.android;

Matcher throwsCode(NativeFlowErrorCode code) =>
    throwsA(isA<NativeFlowException>().having((e) => e.code, 'code', code));

const fast = RecoveryPolicy(
  initialDelay: Duration(milliseconds: 50),
  maxDelay: Duration(milliseconds: 50),
  jitter: 0,
  maxAttempts: 3,
  waitForNetwork: false,
);

Future<void> settle([Duration d = const Duration(milliseconds: 600)]) =>
    Future<void>.delayed(d);

/// Waits until [session] reaches [state] (fails with the history on timeout).
Future<void> reach(RuntimeSession session, SessionState state) async {
  final seen = <SessionState>[session.state];
  if (session.state == state) return;
  await session.states
      .map((s) => (seen..add(s)).last)
      .firstWhere((s) => s == state)
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            throw TestFailure('${session.id} never reached $state: $seen'),
      );
}

/// Notifications need the user's authorization on iOS / Android 13+.
Future<bool> notificationsAllowed() async =>
    (await NativeFlow.permissions.status(RuntimeCapability.notifications))
        .isUsable;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final logs = <String>[];

  setUpAll(() async {
    await NativeFlow.initialize(
      config: const NativeFlowConfig(
        logVerbosity: LogVerbosity.verbose,
        recoveryPolicy: fast,
      ),
    );
    NativeFlow.logger.sink = (level, message, {fields, error}) =>
        logs.add('${level.name} $message');
  });

  tearDown(() async {
    for (final s in NativeFlow.sessions.toList()) {
      await NativeFlow.detach(s.id);
    }
    if (NativeFlow.state != RuntimeState.stopped) await NativeFlow.stop();
  });

  testWidgets('initialize is idempotent and reports a snapshot', (_) async {
    await NativeFlow.initialize();
    expect(NativeFlow.isBackgroundEngine, isFalse);
    expect(NativeFlow.state, isNot(RuntimeState.starting));
    expect(NativeFlow.network, isA<NetworkState>());
  });

  testWidgets('capabilities and permission status agree', (_) async {
    final caps = await NativeFlow.capabilities();
    expect(caps.keys, containsAll(RuntimeCapability.values));
    for (final c in [
      RuntimeCapability.network,
      RuntimeCapability.overlay,
      RuntimeCapability.liveActivity,
      RuntimeCapability.backgroundProcessing,
    ]) {
      expect(await NativeFlow.permissions.status(c), caps[c], reason: c.name);
    }
    // Honest platform split.
    if (isAndroid) {
      expect(
        caps[RuntimeCapability.liveActivity],
        CapabilityStatus.unavailable,
      );
      expect(caps[RuntimeCapability.widget], CapabilityStatus.unavailable);
      expect(
        caps[RuntimeCapability.backgroundProcessing],
        CapabilityStatus.partiallySupported,
      );
    } else {
      expect(caps[RuntimeCapability.overlay], CapabilityStatus.unavailable);
      expect(caps[RuntimeCapability.fullscreen], CapabilityStatus.unavailable);
      expect(
        caps[RuntimeCapability.bootRecovery],
        CapabilityStatus.unavailable,
      );
    }
    // No adapters attached -> nothing to request.
    expect(await NativeFlow.permissions.requestRequired(), isEmpty);
    // Requesting something that cannot be requested returns immediately.
    expect(
      await NativeFlow.permissions.request(RuntimeCapability.network),
      CapabilityStatus.supported,
    );
  });

  testWidgets(
    'one runtime for many adapters: attach/start/attach/detach/stop',
    (_) async {
      final calls = <String>[];
      RuntimeAdapter adapter(String id, Set<RuntimeCapability> caps) =>
          RuntimeAdapter(
            id: id,
            requirements: RuntimeRequirements(capabilities: caps),
            start: (_) => calls.add('$id.start'),
            stop: (_) => calls.add('$id.stop'),
          );

      final states = <RuntimeState>[];
      final sub = NativeFlow.states.listen(states.add);
      await NativeFlow.attach(adapter('socket', {RuntimeCapability.network}));
      await NativeFlow.attach(
        adapter('sync', {RuntimeCapability.backgroundExecution}),
      );
      await NativeFlow.start(
        const RuntimeOptions(
          notification: ForegroundNotification(
            title: 'Integration test',
            body: 'running',
            actions: [NotificationAction(id: 'stop', label: 'Stop')],
          ),
          persistent: false,
        ),
      );
      expect(NativeFlow.state, RuntimeState.running);
      expect(
        NativeFlow.sessions.map((s) => s.state),
        everyElement(SessionState.running),
      );

      // Attaching while running starts immediately and updates requirements.
      await NativeFlow.attach(
        adapter('late', {RuntimeCapability.notifications}),
      );
      expect(
        calls,
        containsAllInOrder(['socket.start', 'sync.start', 'late.start']),
      );
      await NativeFlow.detach('late');
      expect(calls.last, 'late.stop');
      expect(
        () => NativeFlow.detach('late'),
        throwsCode(NativeFlowErrorCode.unknownAdapter),
      );
      expect(
        () => NativeFlow.attach(adapter('socket', {})),
        throwsCode(NativeFlowErrorCode.duplicateAdapter),
      );

      await NativeFlow.stop();
      expect(NativeFlow.state, RuntimeState.stopped);
      expect(calls.sublist(calls.length - 2), ['sync.stop', 'socket.stop']);
      await settle(); // the states stream delivers asynchronously
      await sub.cancel();
      expect(
        states,
        containsAllInOrder([RuntimeState.running, RuntimeState.stopped]),
      );
    },
  );

  testWidgets('recovery: retries, reportFailure, give-up', (_) async {
    var failures = 1;
    AdapterContext? ctx;
    final reasons = <RecoveryReason?>[];
    final session = await NativeFlow.attach(
      RuntimeAdapter(
        id: 'flaky',
        start: (c) {
          ctx = c;
          reasons.add(c.recoveryReason);
          if (failures-- > 0) throw StateError('boom');
        },
      ),
    );
    await NativeFlow.start();
    await reach(session, SessionState.running);
    expect(reasons, [null, RecoveryReason.adapterFailure]);

    final recovered = reach(session, SessionState.recovering);
    ctx!.reportFailure(StateError('socket closed'));
    await recovered;
    await reach(session, SessionState.running);
    expect(reasons.last, RecoveryReason.adapterFailure);

    final failed = NativeFlow.events.on(RuntimeEventType.adapterFailed).first;
    failures = 100;
    ctx!.reportFailure(StateError('dead'));
    expect(
      (await failed.timeout(const Duration(seconds: 5))).adapterId,
      'flaky',
    );
    expect(session.state, SessionState.failed);
  });

  testWidgets('events: transient, persisted round-trip, validation', (_) async {
    final transient = NativeFlow.events.named('it.transient').first;
    expect(await NativeFlow.emit('it.transient', payload: {'a': 1}), isNull);
    expect((await transient).payload, {'a': 1});

    final persisted = NativeFlow.events.named('it.persisted').first;
    final id = await NativeFlow.emit(
      'it.persisted',
      payload: {
        'n': [1, 2],
      },
      persist: true,
    );
    final event = await persisted.timeout(const Duration(seconds: 5));
    expect(event.id, id);
    expect(event.isPersistent, isTrue);
    expect(event.payload, {
      'n': [1, 2],
    });

    expect(
      () => NativeFlow.emit('nativeflow.x'),
      throwsCode(NativeFlowErrorCode.invalidArgument),
    );
    expect(
      () => NativeFlow.emit('bad name'),
      throwsCode(NativeFlowErrorCode.invalidArgument),
    );
    expect(
      () =>
          NativeFlow.emit('it.big', payload: {'x': 'y' * 40000}, persist: true),
      throwsCode(NativeFlowErrorCode.invalidArgument),
    );
  });

  testWidgets('notifications: channel, every variant, cancel', (_) async {
    await NativeFlow.notifications.createChannel(
      const NotificationChannel(
        id: 'it',
        name: 'Integration',
        importance: NotificationImportance.high,
      ),
    );
    final variants = [
      const RuntimeNotification(id: 50, title: 'simple'),
      const RuntimeNotification(
        id: 51,
        title: 'actions',
        channelId: 'it',
        actions: [
          NotificationAction(id: 'accept', label: 'Accept', opensApp: true),
          NotificationAction(id: 'decline', label: 'Decline'),
        ],
        payload: {'ride': 1},
      ),
      RuntimeNotification(
        id: 52,
        title: 'link',
        deepLink: Uri.parse('nativeflow-example://ride/1'),
      ),
      const RuntimeNotification(id: 53, title: 'grouped', group: 'g'),
      const RuntimeNotification(id: 54, title: 'ongoing', ongoing: true),
      const RuntimeNotification(
        id: 55,
        title: 'call',
        fullScreen: FullScreenReason.incomingCall,
      ),
      const RuntimeNotification(
        id: 56,
        title: 'alarm',
        fullScreen: FullScreenReason.alarm,
      ),
    ];
    if (!await notificationsAllowed()) {
      expect(
        () => NativeFlow.notifications.show(variants.first),
        throwsCode(NativeFlowErrorCode.permissionRequired),
      );
      markTestSkipped('notifications not authorized; skipped the posting path');
      return;
    }
    for (final n in variants) {
      await NativeFlow.notifications.show(n);
    }
    for (final n in variants) {
      await NativeFlow.notifications.cancel(n.id);
    }
    expect(NativeFlow.notifications.taps, isA<Stream<RuntimeEvent>>());
    expect(NativeFlow.notifications.actions, isA<Stream<RuntimeEvent>>());
  });

  testWidgets('overlay: full lifecycle (Android) / unavailable (iOS)', (
    _,
  ) async {
    const window = OverlayWindow(
      x: 10,
      y: 100,
      content: OverlayCard(
        children: [
          OverlayText('test', bold: true),
          OverlayProgress(value: .5),
          OverlayButton(actionId: 'ok', label: 'OK'),
          OverlayButton.close(),
        ],
      ),
    );
    if (!isAndroid) {
      expect(
        () => NativeFlow.overlay.show(window),
        throwsCode(NativeFlowErrorCode.unavailable),
      );
      expect(
        NativeFlow.overlay.state,
        throwsCode(NativeFlowErrorCode.unavailable),
      );
      return;
    }
    // Give a permission-granting harness (adb appops) a moment.
    var status = await NativeFlow.overlay.status();
    for (
      var i = 0;
      i < 20 && status == CapabilityStatus.permissionRequired;
      i++
    ) {
      await settle(const Duration(seconds: 1));
      status = await NativeFlow.overlay.status();
    }
    if (status != CapabilityStatus.supported) {
      expect(status, CapabilityStatus.permissionRequired);
      expect(
        () => NativeFlow.overlay.show(window),
        throwsCode(NativeFlowErrorCode.permissionRequired),
      );
      markTestSkipped(
        'overlay permission not granted; skipped the working path',
      );
      return;
    }
    await NativeFlow.overlay.show(window);
    expect((await NativeFlow.overlay.state()).visible, isTrue);
    await NativeFlow.overlay.update(
      const OverlayCard(children: [OverlayText('updated')]),
    );
    await NativeFlow.overlay.move(120, 300);
    var state = await NativeFlow.overlay.state();
    expect(state.x, closeTo(120, 1));
    expect(state.y, closeTo(300, 1));
    await NativeFlow.overlay.resize(200, null);
    await settle();
    state = await NativeFlow.overlay.state();
    expect(state.width, closeTo(200, 1));
    await NativeFlow.overlay.resize(null, null);
    await NativeFlow.overlay.hide();
    expect((await NativeFlow.overlay.state()).visible, isFalse);
  });

  testWidgets('presentation, Live Activities and widgets', (_) async {
    const trip = RuntimePresentation(
      title: 'Trip',
      body: 'on the way',
      progress: .3,
      values: {'eta': '5'},
    );
    if (await notificationsAllowed() || isAndroid) {
      await NativeFlow.present(trip); // Android never refuses posting
    } else {
      // iOS falls back to a notification, which needs authorization.
      expect(
        () => NativeFlow.present(trip),
        throwsCode(NativeFlowErrorCode.permissionRequired),
      );
    }
    if (isAndroid) {
      // Foreground notification is updated while running.
      await NativeFlow.start();
      await NativeFlow.present(
        const RuntimePresentation(title: 'Trip', progress: .6),
      );
      await NativeFlow.stop();
      expect(
        await NativeFlow.activities.status(),
        CapabilityStatus.unavailable,
      );
      expect(
        () => NativeFlow.activities.start(state: {'s': '1'}),
        throwsCode(NativeFlowErrorCode.unavailable),
      );
      expect(
        () => NativeFlow.activities.updateWidget(
          appGroup: 'g',
          key: 'k',
          data: {},
        ),
        throwsCode(NativeFlowErrorCode.unavailable),
      );
      return;
    }
    await NativeFlow.activities.updateWidget(
      appGroup: 'group.com.example.nativeflowExample',
      key: 'driver',
      kind: 'DriverStatus',
      data: {'status': 'Testing'},
    );
    if (await NativeFlow.activities.status() == CapabilityStatus.supported) {
      final id = await NativeFlow.activities.start(
        attributes: {'rider': 'Asha'},
        state: {'status': 'Arriving', 'eta': '4 min'},
      );
      expect(id, isNotEmpty);
      await NativeFlow.activities.update(id, {
        'status': 'On trip',
        'eta': '9 min',
      });
      // present() now routes to the running activity.
      await NativeFlow.present(
        const RuntimePresentation(title: 'Trip', body: 'via activity'),
      ); // routed to the running activity: no notification permission needed
      await NativeFlow.activities.end(id, finalState: {'status': 'Done'});
      expect(
        () => NativeFlow.activities.update('missing', {}),
        throwsCode(NativeFlowErrorCode.invalidArgument),
      );
    }
  });

  testWidgets('background tasks', (_) async {
    // Unknown ids are a no-op (e.g. already expired).
    await NativeFlow.completeBackgroundTask('unknown');
    if (!isAndroid) {
      // iOS simulators have no BGTaskScheduler; devices accept the request.
      try {
        await NativeFlow.scheduleBackgroundTask(
          earliestIn: const Duration(minutes: 15),
        );
      } on NativeFlowException catch (e) {
        expect(e.code, NativeFlowErrorCode.unavailable);
      }
      return;
    }
    final granted = NativeFlow.events.on(RuntimeEventType.backgroundTask).first;
    await NativeFlow.scheduleBackgroundTask(earliestIn: Duration.zero);
    await NativeFlow.scheduleBackgroundTask(
      kind: BackgroundTaskKind.processing,
      earliestIn: const Duration(hours: 1),
    );
    // JobScheduler decides when; `cmd jobscheduler run -f` from the harness
    // forces it. Without it, accept the scheduling itself as the result.
    try {
      final event = await granted.timeout(const Duration(seconds: 45));
      expect(event.payload['kind'], 'refresh');
      await NativeFlow.completeBackgroundTask(
        event.payload['taskId']! as String,
      );
    } on TimeoutException {
      markTestSkipped(
        'JobScheduler did not run the task during the test window',
      );
    }
  });

  testWidgets('logger respects verbosity', (_) async {
    logs.clear();
    NativeFlow.logger.verbosity = LogVerbosity.disabled;
    NativeFlow.logger.error('hidden');
    expect(logs, isEmpty);
    NativeFlow.logger.verbosity = LogVerbosity.verbose;
    NativeFlow.logger.debug('shown');
    expect(logs, ['debug shown']);
  });
}

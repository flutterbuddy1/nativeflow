import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeflow/nativeflow.dart';
import 'package:nativeflow/src/core/validation.dart';

void main() {
  group('RuntimeRequirements', () {
    test('merge is the union and order-insensitive', () {
      const a = RuntimeRequirements(
        capabilities: {RuntimeCapability.location, RuntimeCapability.network},
      );
      const b = RuntimeRequirements(
        capabilities: {RuntimeCapability.network, RuntimeCapability.overlay},
      );
      final merged = RuntimeRequirements.merge([a, b]);
      expect(merged.capabilities, {
        RuntimeCapability.location,
        RuntimeCapability.network,
        RuntimeCapability.overlay,
      });
      expect(merged, RuntimeRequirements.merge([b, a]));
      expect(merged.toMap(), {
        'capabilities': ['location', 'network', 'overlay'],
      });
      expect(RuntimeRequirements.merge([]), RuntimeRequirements.none);
    });
  });

  group('RecoveryPolicy', () {
    test('exponential backoff, capped, without jitter', () {
      const p = RecoveryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
        jitter: 0,
      );
      expect(
        [for (var i = 1; i <= 6; i++) p.delayFor(i).inSeconds],
        [1, 2, 4, 8, 10, 10],
      );
    });

    test('jitter stays within bounds', () {
      const p = RecoveryPolicy(
        initialDelay: Duration(seconds: 10),
        jitter: 0.2,
      );
      final r = Random(1);
      for (var i = 0; i < 100; i++) {
        final ms = p.delayFor(1, r).inMilliseconds;
        expect(ms, inInclusiveRange(8000, 12000));
      }
    });

    test('attempt limits', () {
      expect(RecoveryPolicy.none.allowsAttempt(1), isFalse);
      expect(const RecoveryPolicy(maxAttempts: 2).allowsAttempt(2), isTrue);
      expect(const RecoveryPolicy(maxAttempts: 2).allowsAttempt(3), isFalse);
      expect(
        const RecoveryPolicy(maxAttempts: null).allowsAttempt(1 << 30),
        isTrue,
      );
    });
  });

  group('SessionState transitions', () {
    test('happy path and recovery are legal', () {
      const path = [
        SessionState.idle,
        SessionState.starting,
        SessionState.recovering,
        SessionState.waitingForNetwork,
        SessionState.recovering,
        SessionState.running,
        SessionState.paused,
        SessionState.running,
        SessionState.stopping,
        SessionState.stopped,
        SessionState.starting,
      ];
      for (var i = 0; i < path.length - 1; i++) {
        expect(
          path[i].canTransitionTo(path[i + 1]),
          isTrue,
          reason: '${path[i]} -> ${path[i + 1]}',
        );
      }
    });

    test('nonsense transitions are rejected', () {
      expect(
        SessionState.stopped.canTransitionTo(SessionState.running),
        isFalse,
      );
      expect(SessionState.idle.canTransitionTo(SessionState.running), isFalse);
      expect(
        SessionState.waitingForNetwork.canTransitionTo(SessionState.running),
        isFalse,
      );
    });

    test('every state has an exit', () {
      for (final s in SessionState.values) {
        expect(
          SessionState.values.any(s.canTransitionTo),
          isTrue,
          reason: '$s',
        );
      }
    });
  });

  group('validation', () {
    test('ids', () {
      expect(validateId('driver.socket:1', 'id'), 'driver.socket:1');
      for (final bad in ['', '-x', 'has space', 'a' * 65, 'ü']) {
        expect(
          () => validateId(bad, 'id'),
          throwsA(isA<NativeFlowException>()),
          reason: bad,
        );
      }
    });

    test('payloads must be JSON and bounded', () {
      expect(
        validatePayload({
          'a': 1,
          'b': [
            true,
            null,
            'x',
            {'c': 1.5},
          ],
        }),
        isNotEmpty,
      );
      expect(
        () => validatePayload({'a': DateTime(2020)}),
        throwsA(isA<NativeFlowException>()),
      );
      expect(
        () => validatePayload({'a': double.nan}),
        throwsA(isA<NativeFlowException>()),
      );
      expect(
        () => validatePayload({
          'a': {1: 2},
        }),
        throwsA(isA<NativeFlowException>()),
      );
      expect(
        () => validatePayload({'a': 'x' * (maxPayloadBytes + 1)}),
        throwsA(isA<NativeFlowException>()),
      );
    });
  });

  group('RuntimeEvent', () {
    test('round-trips and classifies system events', () {
      final e = RuntimeEvent.fromMap({
        'id': 7,
        'type': 'nativeflow.network.lost',
        'ts': 1000,
        'adapterId': 'a',
        'payload': {
          'nested': {
            'k': [1],
          },
        },
      });
      expect(e.type, RuntimeEventType.networkLost);
      expect(e.isPersistent, isTrue);
      expect(RuntimeEvent.fromMap(e.toMap()).toMap(), e.toMap());
      expect(RuntimeEvent(name: 'ride.offer').type, RuntimeEventType.custom);
    });

    test('toString never includes the payload', () {
      final e = RuntimeEvent(name: 'auth', payload: {'token': 'secret'});
      expect(e.toString(), isNot(contains('secret')));
    });
  });

  group('RuntimeEventBus', () {
    test('re-entrant dispatch is queued in order', () {
      final bus = RuntimeEventBus();
      final seen = <String>[];
      bus.stream.listen((e) {
        seen.add(e.name);
        if (e.name == 'a') bus.dispatch(RuntimeEvent(name: 'b'));
      });
      bus.dispatch(RuntimeEvent(name: 'a'));
      bus.dispatch(RuntimeEvent(name: 'c'));
      expect(seen, ['a', 'b', 'c']);
    });
  });

  group('serialization limits', () {
    test('overlay node count is bounded', () {
      final big = OverlayWindow(
        content: OverlayCard(children: List.filled(40, const OverlayText('x'))),
      );
      expect(big.toMap, throwsA(isA<NativeFlowException>()));
      final ok = OverlayWindow(
        content: OverlayCard(
          background: const Color(0xFF112233),
          children: [
            const OverlayText('Online'),
            const OverlayButton(actionId: 'go_offline', label: 'Go offline'),
            OverlayImage(Uint8List(4)),
            const OverlayProgress(value: .5),
          ],
        ),
      ).toMap();
      expect((ok['content'] as Map)['background'], 0xFF112233);
    });

    test('notifications reject reserved id and too many actions', () {
      expect(
        const RuntimeNotification(id: 1, title: 't').toMap,
        throwsA(isA<NativeFlowException>()),
      );
      expect(
        RuntimeNotification(
          id: 5,
          title: 't',
          actions: [
            for (var i = 0; i < 4; i++)
              NotificationAction(id: 'a$i', label: 'x'),
          ],
        ).toMap,
        throwsA(isA<NativeFlowException>()),
      );
      final m = RuntimeNotification(
        id: 5,
        title: 't',
        deepLink: Uri.parse('app://ride/1'),
        fullScreen: FullScreenReason.incomingCall,
      ).toMap();
      expect(m['deepLink'], 'app://ride/1');
      expect(m['fullScreen'], 'incomingCall');
    });
  });

  test('LogVerbosity gates levels', () {
    expect(LogVerbosity.disabled.allows(LogLevel.error), isFalse);
    expect(LogVerbosity.errors.allows(LogLevel.warning), isFalse);
    expect(LogVerbosity.normal.allows(LogLevel.info), isTrue);
    expect(LogVerbosity.normal.allows(LogLevel.debug), isFalse);
    expect(LogVerbosity.verbose.allows(LogLevel.debug), isTrue);
  });
}

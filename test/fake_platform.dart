import 'dart:async';

import 'package:nativeflow/nativeflow.dart';
import 'package:nativeflow/src/platform/native_flow_platform.dart';

typedef Handler = Object? Function(Map<String, Object?>? args);

/// In-memory stand-in for a native runtime.
class FakePlatform implements NativeFlowPlatform {
  FakePlatform({this.snapshot = const {}});

  Map<String, Object?> snapshot;
  final calls = <(String, Map<String, Object?>?)>[];
  final handlers = <String, Handler>{};
  final _events = StreamController<List<Object?>>.broadcast();
  final pending = <Map<String, Object?>>[];
  Future<Object?> Function(String method)? callHandler;
  var _nextId = 1;

  List<String> get methods => [for (final c in calls) c.$1];
  Map<String, Object?>? lastArgs(String method) =>
      calls.lastWhere((c) => c.$1 == method).$2;

  @override
  Future<T?> invoke<T>(String method, [Map<String, Object?>? args]) async {
    calls.add((method, args));
    final handler = handlers[method];
    if (handler != null) return handler(args) as T?;
    return switch (method) {
      NativeMethod.initialize => snapshot as T?,
      NativeMethod.start => 'running' as T?,
      NativeMethod.stop => 'stopped' as T?,
      NativeMethod.pendingEvents =>
        pending
                .where((e) => (e['id'] as int) > (args!['after'] as int))
                .toList()
            as T?,
      NativeMethod.appendEvent => _append(args!) as T?,
      _ => null,
    };
  }

  int _append(Map<String, Object?> args) {
    final event = {...args, 'id': _nextId++, 'ts': 0};
    pending.add(event);
    push([event]);
    return event['id']! as int;
  }

  void push(List<Map<String, Object?>> batch) => _events.add(batch);

  void pushSystem(
    RuntimeEventType type, [
    Map<String, Object?> payload = const {},
  ]) => push([
    {'type': type.wireName, 'ts': 0, 'payload': payload},
  ]);

  @override
  Stream<List<Object?>> get events => _events.stream;

  @override
  void setCallHandler(Future<Object?> Function(String method) handler) =>
      callHandler = handler;
}

/// Lets timers, microtasks and async adapter callbacks settle.
Future<void> settle([int rounds = 10]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

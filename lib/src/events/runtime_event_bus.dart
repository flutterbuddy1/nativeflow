import 'dart:async';
import 'dart:collection';

import 'runtime_event.dart';

/// Fan-out of runtime events to application and adapter listeners.
class RuntimeEventBus {
  final _controller = StreamController<RuntimeEvent>.broadcast(sync: true);

  /// Every event, system and custom.
  Stream<RuntimeEvent> get stream => _controller.stream;

  /// Events of one system [type].
  Stream<RuntimeEvent> on(RuntimeEventType type) =>
      stream.where((e) => e.type == type);

  /// Custom events with the given wire [name].
  Stream<RuntimeEvent> named(String name) =>
      stream.where((e) => e.name == name);

  final _queue = Queue<RuntimeEvent>();
  var _firing = false;

  /// Delivers [event] synchronously so that, when this returns, every
  /// listener has seen it and the event can be acknowledged. Events
  /// dispatched from inside a listener are queued, not nested.
  void dispatch(RuntimeEvent event) {
    _queue.add(event);
    if (_firing) return;
    _firing = true;
    try {
      while (_queue.isNotEmpty) {
        _controller.add(_queue.removeFirst());
      }
    } finally {
      _firing = false;
    }
  }
}

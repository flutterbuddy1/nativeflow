import 'package:flutter/foundation.dart';

/// Events produced by NativeFlow itself. Application events use
/// [RuntimeEventType.custom] with a free-form [RuntimeEvent.name].
enum RuntimeEventType {
  runtimeStarted('nativeflow.runtime.started'),
  runtimeStopped('nativeflow.runtime.stopped'),
  runtimeInterrupted('nativeflow.runtime.interrupted'),
  runtimeRecovered('nativeflow.runtime.recovered'),

  /// iOS: the app is about to be suspended; adapters are paused.
  runtimePaused('nativeflow.runtime.paused'),
  runtimeResumed('nativeflow.runtime.resumed'),
  networkAvailable('nativeflow.network.available'),
  networkLost('nativeflow.network.lost'),
  networkChanged('nativeflow.network.changed'),
  notificationTapped('nativeflow.notification.tap'),
  notificationAction('nativeflow.notification.action'),
  overlayAction('nativeflow.overlay.action'),
  overlayClosed('nativeflow.overlay.closed'),

  /// iOS: the system granted a BGTaskScheduler window. Call
  /// `NativeFlow.completeBackgroundTask` when done.
  backgroundTask('nativeflow.background.task'),

  /// An adapter exhausted its recovery policy.
  adapterFailed('nativeflow.adapter.failed'),
  custom('');

  const RuntimeEventType(this.wireName);

  final String wireName;

  static RuntimeEventType fromWire(String name) => values.firstWhere(
    (t) => t != custom && t.wireName == name,
    orElse: () => custom,
  );
}

/// A runtime event.
///
/// Events with a non-null [id] are persisted in the native event store and
/// survive Flutter engine and process death until acknowledged. NativeFlow
/// acknowledges them after delivering to listeners, so a crash mid-delivery
/// causes redelivery (at-least-once). Use [id] to de-duplicate.
@immutable
class RuntimeEvent {
  RuntimeEvent({
    required this.name,
    this.id,
    DateTime? timestamp,
    this.adapterId,
    this.payload = const {},
  }) : type = RuntimeEventType.fromWire(name),
       timestamp = timestamp ?? DateTime.now();

  /// Monotonic store id, or `null` for transient events.
  final int? id;
  final RuntimeEventType type;

  /// Wire name, e.g. `nativeflow.network.lost` or `ride.offer`.
  final String name;
  final DateTime timestamp;
  final String? adapterId;
  final Map<String, Object?> payload;

  bool get isPersistent => id != null;

  factory RuntimeEvent.fromMap(Map<Object?, Object?> map) => RuntimeEvent(
    id: (map['id'] as num?)?.toInt(),
    name: map['type']! as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (map['ts'] as num?)?.toInt() ?? 0,
    ),
    adapterId: map['adapterId'] as String?,
    payload: _stringKeyed(map['payload']),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'type': name,
    'ts': timestamp.millisecondsSinceEpoch,
    'adapterId': adapterId,
    'payload': payload,
  };

  // Payload contents are intentionally excluded: they may be private.
  @override
  String toString() =>
      'RuntimeEvent(${id ?? '-'}, $name${adapterId == null ? '' : ', $adapterId'})';
}

Map<String, Object?> _stringKeyed(Object? value) {
  if (value is! Map) return const {};
  return value.map((k, v) => MapEntry(k as String, _deep(v)));
}

Object? _deep(Object? v) => switch (v) {
  Map m => _stringKeyed(m),
  List l => l.map(_deep).toList(),
  _ => v,
};

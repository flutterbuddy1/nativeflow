import 'package:flutter/foundation.dart';

/// Events produced by NativeFlow itself. Application events use
/// [RuntimeEventType.custom] with a free-form [RuntimeEvent.name].
enum RuntimeEventType {
  /// The native runtime started.
  runtimeStarted('nativeflow.runtime.started'),

  /// The native runtime stopped.
  runtimeStopped('nativeflow.runtime.stopped'),

  /// The OS stopped the runtime without the app asking. Persisted.
  runtimeInterrupted('nativeflow.runtime.interrupted'),

  /// The runtime was restored after process recreation or relaunch.
  /// Persisted; attached adapters receive `recover`.
  runtimeRecovered('nativeflow.runtime.recovered'),

  /// iOS: the app is about to be suspended; adapters are paused.
  runtimePaused('nativeflow.runtime.paused'),

  /// The app returned from background on iOS; paused adapters resume.
  runtimeResumed('nativeflow.runtime.resumed'),

  /// The OS reports a usable default network.
  networkAvailable('nativeflow.network.available'),

  /// The OS reports no usable network.
  networkLost('nativeflow.network.lost'),

  /// The network type or metered flag changed while connected.
  networkChanged('nativeflow.network.changed'),

  /// A notification body was tapped. Persisted.
  notificationTapped('nativeflow.notification.tap'),

  /// A notification action button was tapped. Persisted.
  notificationAction('nativeflow.notification.action'),

  /// An overlay button or card was tapped. Persisted.
  overlayAction('nativeflow.overlay.action'),

  /// The overlay was closed by the user. Persisted.
  overlayClosed('nativeflow.overlay.closed'),

  /// The OS granted a background window requested with
  /// `NativeFlow.scheduleBackgroundTask`. The payload has `taskId` and
  /// `kind`; call `NativeFlow.completeBackgroundTask(taskId)` when done.
  /// Persisted.
  backgroundTask('nativeflow.background.task'),

  /// An adapter exhausted its recovery policy.
  adapterFailed('nativeflow.adapter.failed'),

  /// An application event; see [RuntimeEvent.name].
  custom('');

  const RuntimeEventType(this.wireName);

  /// Name used on the platform channel and in the event store.
  final String wireName;

  /// Maps a wire name to its type; any other name is [custom].
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
  /// Creates an event. [type] is derived from [name]; [timestamp] defaults
  /// to now.
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

  /// System type, or [RuntimeEventType.custom] for application events.
  final RuntimeEventType type;

  /// Wire name, e.g. `nativeflow.network.lost` or `ride.offer`.
  final String name;

  /// When the event was produced.
  final DateTime timestamp;

  /// Id of the adapter that emitted it, if any.
  final String? adapterId;

  /// JSON-compatible event data.
  final Map<String, Object?> payload;

  /// Whether the event came from the native store and is redelivered
  /// until acknowledged.
  bool get isPersistent => id != null;

  /// Decodes an event from its platform-channel map.
  factory RuntimeEvent.fromMap(Map<Object?, Object?> map) => RuntimeEvent(
    id: (map['id'] as num?)?.toInt(),
    name: map['type']! as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (map['ts'] as num?)?.toInt() ?? 0,
    ),
    adapterId: map['adapterId'] as String?,
    payload: _stringKeyed(map['payload']),
  );

  /// Encodes this event as a platform-channel map.
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
  final Map<Object?, Object?> m => _stringKeyed(m),
  final List<Object?> l => l.map(_deep).toList(),
  _ => v,
};

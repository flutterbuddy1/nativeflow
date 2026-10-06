# Events

## Listening

```dart
NativeFlow.events.stream.listen(...);                                  // everything
NativeFlow.events.on(RuntimeEventType.networkLost).listen(...);        // system type
NativeFlow.events.named('ride.offer').listen((e) => show(e.payload));  // app event
```

Inside adapters, prefer `ctx.on(...)` / `ctx.onNamed(...)`: they are cancelled
automatically on restart and stop.

`RuntimeEvent`: `id` (null for transient events), `type`, `name`,
`timestamp`, `adapterId`, `payload` (JSON map).

## System events

| Type | Persisted | Payload |
|---|---|---|
| `runtimeStarted` / `runtimeStopped` | | |
| `runtimeInterrupted` | ✓ | `reason` |
| `runtimeRecovered` | ✓ | `reason` |
| `runtimePaused` / `runtimeResumed` (iOS) | | |
| `networkAvailable` / `networkLost` / `networkChanged` | | `connected`, `type`, `metered` |
| `notificationTapped` / `notificationAction` | ✓ | `notificationId`, `actionId`, `deepLink`, `data` |
| `overlayAction` / `overlayClosed` | ✓ | `actionId` |
| `backgroundTask` | ✓ | `taskId`, `kind` (or `expired: true`) |
| `adapterFailed` | | `attempts`, `error` |

## Emitting

```dart
await NativeFlow.emit('ui.refresh');                                // in-memory only
final id = await NativeFlow.emit('ride.offer', payload: {'ride': 42}, persist: true);
```

Rules: names match `[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}` and must not start with
`nativeflow.`. Payloads must be JSON (null, bool, num, String, List, Map
with String keys), nested at most 16 levels, at most 32 KB. Anything else
throws `invalidArgument`.

## Persistence and delivery

Persisted events are written to a native append-only store first, so they
survive Flutter engine death, process death and reboot:

1. On `initialize`, Dart receives `lastAck` and drains all newer events in
   order.
2. Events arriving during the drain are buffered, then delivered.
3. After each batch has been dispatched to your listeners, Dart sends one
   cumulative acknowledgement.

Delivery is **at-least-once**: a crash between dispatch and acknowledgement
redelivers. De-duplicate by `event.id`. Listeners run synchronously; if you
start async work, persist your own progress.

Store bounds: 1000 events, 7 days, 10 delivery attempts (then dropped as
poison). Location: app-private, not backed up, unencrypted. Don't store
secrets in events.

Native → Dart events are batched once per main-loop turn, so a burst of
network changes or notification actions is one platform-channel message.

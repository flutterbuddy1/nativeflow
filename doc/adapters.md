# Adapters

An adapter plugs **your** workload into the runtime. It owns the protocol;
NativeFlow owns when it runs and how it recovers.

```
NativeFlow ──start/stop/pause/resume/recover──▶ RuntimeAdapter ──▶ your library
           ◀──emit / reportFailure / on(...)──
```

## Two styles

Callbacks:

```dart
RuntimeAdapter(
  id: 'telemetry',
  requirements: const RuntimeRequirements(capabilities: {RuntimeCapability.network}),
  start: (ctx) async => client.connect(),
  stop: (ctx) async => client.disconnect(),
)
```

Subclass (for state such as the connection object):

```dart
class SocketAdapter extends RuntimeAdapter {
  SocketAdapter() : super(id: 'socket', requirements: const RuntimeRequirements(
    capabilities: {RuntimeCapability.backgroundExecution, RuntimeCapability.network},
  ));

  WebSocketChannel? _channel;

  @override
  Future<void> start(AdapterContext ctx) async { /* connect */ }

  @override
  Future<void> stop(AdapterContext ctx) async { /* close; must be idempotent */ }
}
```

## Lifecycle

| Method | Called when | Default |
|---|---|---|
| `start` | The runtime starts, or you attach while it is running (this engine started it) | no-op |
| `stop` | `NativeFlow.stop()`, `detach`, or the engine hands off its adapters | no-op |
| `pause` | iOS is about to suspend the app; Android runtime interrupted | no-op |
| `resume` | iOS app returns to foreground; runtime started again | no-op |
| `recover` | After a failure, when the network returns, or when the runtime predates this engine | `stop` then `start` |

`ctx.recoveryReason` tells `recover` why: `adapterFailure`,
`networkRestored`, `runtimeRestored`. Override `recover` to resume from a
checkpoint (for example the last acknowledged server offset) instead of a
cold start.

Lifecycle calls on the runtime are serialized. Session states and their
legal transitions are listed in [Runtime lifecycle](runtime-lifecycle.md#session-states).

## AdapterContext

| Member | Use |
|---|---|
| `emit(name, payload:, persist:)` | Publish an app event, tagged with this adapter's id. `persist: true` → stored natively until acknowledged |
| `reportFailure(error)` | Your connection broke: schedules `recover` with backoff |
| `on(type, handler)` / `onNamed(name, handler)` | Listen to runtime / app events. Auto-cancelled before every restart and on stop |
| `network` | Current `NetworkState` |
| `runtimeState` | Current `RuntimeState` |
| `attempt` | Failed attempts since the last success |
| `logger` | The shared `NativeFlowLogger` |

## Requirements

Requirements are merged across all attached adapters into **one** native
configuration. A driver app with socket + location + notifications + overlay
adapters gets one Android foreground service of type `location`, not four
services.

```dart
RuntimeRequirements.merge([a.requirements, b.requirements])
```

Attaching or detaching while running updates the running service's types.
If a newly required capability lacks permission, `attach` throws
`permissionRequired` and the adapter is not attached.

## Ids

`[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}`. Ids must be stable across launches: the
background engine and process restarts re-attach adapters by id.

## Rules of thumb

- **Cancel before close.** Cancel your stream subscription before closing the
  connection in `stop`, so `onDone` doesn't report a failure for your own
  shutdown.
- **Let the library reconnect if it does so well** (Socket.IO). Only report
  failures it cannot handle.
- **Use `persist: true` sparingly**: only for events you must not lose while
  Flutter is down (ride offers, commands). The store is bounded (1000 events,
  7 days, 32 KB each).
- **Don't block in `start`** for minutes. Throw and let recovery retry.

## Complete examples

In [`example/lib/adapters`](../example/lib/adapters):
[WebSocket](../example/lib/adapters/websocket_adapter.dart),
[Socket.IO](../example/lib/adapters/socket_io_adapter.dart),
[MQTT](../example/lib/adapters/mqtt_adapter.dart),
[location](../example/lib/adapters/location_adapter.dart),
[failure simulation](../example/lib/adapters/demo_adapter.dart).

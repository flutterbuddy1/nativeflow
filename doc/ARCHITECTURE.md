# Architecture

```
USER APPLICATION ── owns behavior
      │
USER'S LIBRARIES ── own protocols (web_socket_channel, socket_io_client, mqtt_client, geolocator…)
      │   wrapped by RuntimeAdapter
NATIVEFLOW (Dart) ── public API, adapters, sessions, recovery policy, event bus
      │   MethodChannel  dev.nativeflow/runtime   (commands, closed whitelist)
      │   EventChannel   dev.nativeflow/events    (batched native → Dart events)
NATIVEFLOW (native) ── RuntimeSupervisor: state, service/background coordination,
      │                 event store, network, notifications, overlay, recovery
NATIVE OS ── owns process & background policy
```

## Dart layer (`lib/src`)

| Path | Responsibility |
|---|---|
| `core/native_flow.dart` | `NativeFlow` static facade (the only entry point). |
| `core/runtime.dart` | `NativeFlowRuntime`: one per Flutter engine. Sessions, serialized lifecycle, bridge sync, event delivery + ack. |
| `core/runtime_session.dart` | `RuntimeSession`: one per adapter. State machine, failure counting, backoff timers. |
| `core/runtime_state.dart` | `RuntimeState` (native runtime) and `SessionState` (adapter) with a legal-transition table. |
| `core/runtime_capability.dart` | `RuntimeCapability`, `CapabilityStatus`. |
| `core/runtime_requirement.dart` | Immutable `RuntimeRequirements` + `merge`. |
| `adapter/` | `RuntimeAdapter` (callbacks or subclass) and `AdapterContext`. |
| `events/` | `RuntimeEvent`, `RuntimeEventBus` (synchronous, re-entrancy-safe). |
| `recovery/recovery_policy.dart` | Exponential backoff with jitter, attempt limit, network-awareness. |
| `notification/`, `overlay/`, `presentation/`, `permissions/` | Feature controllers + immutable specs. |
| `platform/native_flow_platform.dart` | Transport (`invoke` + event stream). The only place that knows about channels. |

No Android or iOS concept appears in the public Dart API: adapters declare
*capabilities*, and each platform maps them to its own mechanism.

## Android (`android/src/main/kotlin/com/nativeflow`)

| File | Responsibility |
|---|---|
| `NativeFlowPlugin` | One per engine. Channel ↔ supervisor; activity hooks for permissions and notification-tap intents. |
| `RuntimeSupervisor` | Process singleton. State machine, start/stop, recovery, event outbox, engine ownership. Main thread only. |
| `RuntimeService` | The **single** foreground service. Thin; delegates to the supervisor. |
| `RequirementManager` | Capabilities → one FGS type mask (∩ manifest-declared types). Pure, tested. |
| `RecoveryManager` | Restore decisions (intent, boot opt-in, restart-loop guard). Pure, tested. |
| `EventStore` | JSON-lines persistent event log. Pure, tested. |
| `RuntimeStore` | SharedPreferences: intent + config needed to restore without Flutter. |
| `NetworkManager` | `ConnectivityManager` default-network callback, change-only. |
| `NotificationPresenter`, `NotificationActionReceiver` | Native notifications; taps/actions → store. |
| `OverlayManager` | Native declarative overlay (WindowManager), drag, persistence. |
| `PermissionManager`, `capability/CapabilityManager` | Honest status + explicit request flows. |
| `NativeFlowEngine` | Background `FlutterEngine` for adapters when no UI exists. |
| `BootReceiver` (in `NotificationActionReceiver.kt`) | Reboot / app-update restore. |
| `BackgroundTaskService` | JobScheduler tasks → persisted `background.task` events; spawns the background engine if needed. |

### Aggregation

Driver app: `socket + location + notifications + overlay` → one
`RuntimeService` started with `FOREGROUND_SERVICE_TYPE_LOCATION`, one
notification, one overlay window. Adding or removing an adapter while running
re-issues `startForeground` with the new type mask; it never starts another
service.

### Engine ownership (Android)

Adapters run in exactly one Flutter engine at a time.

1. UI engine calls `initialize` → it participates.
2. UI engine is destroyed (app swiped away) while the runtime is active →
   after 1 s, if no engine participates and a `backgroundEntrypoint` was
   registered, the supervisor starts a background engine that runs it. The
   entrypoint re-attaches adapters; they get `recover(runtimeRestored)`.
3. A UI engine initializes again → the supervisor asks the background engine
   to `release` (stop adapters, ≤ 3 s), destroys it, then answers the UI's
   `initialize`. The UI's adapters get `recover(runtimeRestored)`.
4. `stop()` destroys the background engine.

No engine is created unless the runtime is active and nobody else runs the
adapters.

## iOS (`ios/nativeflow/Sources/nativeflow`)

| File | Responsibility |
|---|---|
| `NativeFlowPlugin` | Channel ↔ supervisor; forwarded `UNUserNotificationCenterDelegate`. |
| `RuntimeSupervisor` | State, app-lifecycle pause/resume, network (`NWPathMonitor`), outbox. |
| `CapabilityManager` | Info.plist + authorization based capability report. |
| `BackgroundTaskManager` | BGTaskScheduler refresh/processing tasks. |
| `PrivacyInfo.xcprivacy` | Declares UserDefaults access (CA92.1, 1C8F.1). |
| `NotificationPresenter` | `UNUserNotificationCenter`, action categories. |
| `ActivityManager` | ActivityKit Live Activities, WidgetKit reloads. |
| `EventStore` | Same JSON-lines format as Android. |

iOS has no persistent service. "Running" means the app recorded the intent;
NativeFlow then coordinates what iOS offers: ~30 s of background time (used to
pause adapters cleanly before suspension), the app's own continuous background
modes (location/audio/VoIP — if declared and required, adapters are not
paused), BGTaskScheduler windows, notifications and Live Activities.

## Bridge protocol

Commands (`dev.nativeflow/runtime`): `initialize, capabilities, start, stop,
setRequirements, appendEvent, pendingEvents, ackEvents, permissionStatus,
requestPermission, createChannel, showNotification, cancelNotification,
overlay{Show,Update,Hide,Move,Resize,State}, present, activity{Start,Update,End},
widgetUpdate, scheduleBackgroundTask, completeBackgroundTask`. Native → Dart:
`release`. Anything else is `notImplemented`.

Events (`dev.nativeflow/events`) are lists (batches, one per main-loop turn):
`{id?, type, ts, adapterId?, payload}`. `id` is present for persisted events.

### Synchronisation after engine (re)creation

1. Dart subscribes to the event channel (buffering), then calls `initialize`.
2. Native replies with a snapshot: `state`, `network`, `backgroundEngine`,
   `lastAck`, `capabilities`. Dart never assumes state.
3. Dart drains `pendingEvents(after: lastAck)` in pages, dispatches, then
   flushes the buffer. Events with `id ≤ lastDelivered` are dropped (dedupe).
4. After each batch is dispatched synchronously to listeners, Dart sends one
   cumulative `ackEvents(upTo)`.

Delivery is at-least-once: a crash between dispatch and ack redelivers.

## Event store

JSON-lines append log (`add`, `ack`, `try`, `meta`), replayed on load,
compacted atomically (write temp + rename) when dead lines dominate. Bounded:
1000 events, 7 days, 10 delivery attempts (poison events dropped), 32 KB
payloads. Torn trailing lines are skipped and terminated. It stores runtime
signals only — never a general database.

Persisted: notification taps/actions, overlay actions/close, runtime
interrupted/recovered, background-task grants, application events emitted with
`persist: true`. Transient: network changes, started/stopped, paused/resumed.

## Recovery

| Situation | Android | iOS |
|---|---|---|
| Adapter throws / `reportFailure` | Dart: backoff per `RecoveryPolicy`; waits for network if offline | same |
| Network lost / restored | `networkLost/Available` events; waiting sessions recover immediately | same |
| Flutter UI destroyed | background engine re-attaches adapters | n/a (engine lives with the process) |
| Process killed | `START_STICKY` restart → `runtime.recovered`; restart-loop guard (5 in 10 min) | app relaunch with recorded intent → `runtime.recovered` |
| App relaunch after interruption | `initialize` from UI restores the service | same as above |
| FGS time limit (Android 15 dataSync) | `runtime.interrupted{timeLimit}`; restored on next app launch | n/a |
| Reboot | only with `restoreOnBoot: true`; if the OS refuses the FGS start, a "Tap to resume" notification is posted | not possible |
| `stop()` | clears the intent; nothing is restored | same |

## Tests

| Suite | Location | Run |
|---|---|---|
| Dart unit (runtime, sessions, recovery, bridge sync, serialization) | `test/` | `flutter test` |
| Android JVM (event store, FGS type aggregation, recovery decisions) | `android/src/test/kotlin` | `cd example/android && ./gradlew :nativeflow:testDebugUnitTest` |
| iOS XCTest (event store, capabilities, plugin commands) | `example/ios/RunnerTests` (Flutter's plugin test host) | `cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'` |
| Integration (real native runtime) | `example/integration_test` | `cd example && flutter test integration_test -d <device>` |

OS integration that cannot run in CI (sticky restarts, reboot, OEM kills,
BGTaskScheduler timing) is isolated behind pure decision code
(`RecoveryManager`, `RequirementManager`, `EventStore`) which is unit tested.

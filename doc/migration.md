# Migration

## From `flutter_background_service`

| flutter_background_service | NativeFlow |
|---|---|
| `onStart(ServiceInstance)` entrypoint with all logic | `RuntimeAdapter`s (testable units) + optional `backgroundEntrypoint` that re-attaches them |
| `service.invoke` / `on` messaging between isolates | `NativeFlow.emit` / `events` (persisted if needed) |
| Manual reconnect loops | `ctx.reportFailure` + `RecoveryPolicy` |
| `setForegroundNotificationInfo` | `NativeFlow.present` |
| `autoStartOnBoot` | `RuntimeOptions(restoreOnBoot: true)`, only restoring recorded intent |
| Always-on background isolate | Background engine only when no UI engine runs the adapters |

Steps:

1. Move each long-running piece (socket, tracking loop) into a
   `RuntimeAdapter`. Keep using the same libraries inside it.
2. Replace isolate messaging for critical data with
   `ctx.emit(..., persist: true)`. UI listens with `NativeFlow.events.named(...)`.
3. Remove the old plugin's service from your manifest and widen
   `com.nativeflow.RuntimeService`'s `foregroundServiceType` instead.
4. Call `NativeFlow.start()` where you started the old service (from the UI).

## From a hand-rolled Android service

Delete your `Service`, `BroadcastReceiver`s and notification-building code
for the runtime. Map each responsibility:

- keeping the process alive → `NativeFlow.start()`
- reconnect on network change → adapter + `RecoveryPolicy(waitForNetwork: true)`
- boot restart → `restoreOnBoot`
- notification buttons → `NotificationAction` + `notifications.actions`

## From `workmanager`

Periodic, deferrable work maps to `scheduleBackgroundTask`. Keep
`workmanager` if you need periodic constraints NativeFlow doesn't expose
(see [Roadmap](ROADMAP.md)).

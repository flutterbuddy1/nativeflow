# Background tasks

OS-scheduled, deferrable work (sync, upload, cleanup) that should happen even
if the runtime is not running.

| | Android | iOS |
|---|---|---|
| Mechanism | JobScheduler | BGTaskScheduler |
| `refresh` | Runs when network is available | `BGAppRefreshTask` (~30 s) |
| `processing` | Network + charging | `BGProcessingTask` (minutes; usually while charging/idle) |
| Who decides when | The OS | The OS (may be never: Low Power Mode, Background App Refresh off, app force-quit) |

## Schedule

```dart
await NativeFlow.scheduleBackgroundTask(
  kind: BackgroundTaskKind.refresh,
  earliestIn: const Duration(minutes: 15),
);
```

Scheduling the same kind again replaces the pending request.

## Handle

A granted window arrives as a **persisted** event, in whichever engine is
running (Android starts the background engine if needed):

```dart
NativeFlow.events.on(RuntimeEventType.backgroundTask).listen((e) async {
  final taskId = e.payload['taskId'] as String;
  if (e.payload['expired'] == true) return;   // the OS revoked the window
  try {
    await syncNow();
    await NativeFlow.completeBackgroundTask(taskId);
  } catch (_) {
    await NativeFlow.completeBackgroundTask(taskId, success: false); // retry later
  }
});
```

Always complete before the deadline. Register the listener in your
`backgroundEntrypoint` too (Android), since there may be no UI.

## Setup

- **Android:** nothing. Register a `backgroundEntrypoint` so tasks can run
  without UI; otherwise the event waits for the next launch.
- **iOS:** `fetch`/`processing` in `UIBackgroundModes`, the identifiers in
  `BGTaskSchedulerPermittedIdentifiers`, and
  `NativeFlowPlugin.registerBackgroundTasks()` in `AppDelegate` (see
  [iOS setup](ios-setup.md)).

## Testing

- Android: `adb shell cmd jobscheduler run -f <package> 20038` (refresh) or
  `20039` (processing).
- iOS: simulators don't run BGTaskScheduler, so `schedule` throws
  `unavailable`. On a device, pause in the debugger and run:
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"<bundle id>.nativeflow.refresh"]`

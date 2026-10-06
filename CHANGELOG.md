## 0.1.0

* Initial NativeFlow runtime: Dart API (`NativeFlow`, adapters, sessions,
  recovery policy, event bus, capabilities, logging).
* Android: single foreground service runtime, requirement aggregation,
  network callbacks, persistent event store, recovery (sticky restart,
  app relaunch, opt-in boot), background Flutter engine hand-off,
  notifications (channels, actions, deep links, full-screen), native overlays,
  permission flows.
* Android background tasks via JobScheduler (`scheduleBackgroundTask`).
* iOS: capability-driven runtime, background pause/resume, BGTaskScheduler,
  notifications, Live Activities, widget reloads, persistent event store,
  privacy manifest.
* Complete example app covering every public API, with a Live Activity
  widget extension, and an integration test suite.

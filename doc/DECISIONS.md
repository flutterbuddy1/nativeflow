# Architectural decisions

Short records: context → decision → consequence.

### D1. Replace the scaffold; drop `plugin_platform_interface`
The repository was an untouched `flutter create --template=plugin` scaffold
(`com.example.nativeflow`, `getPlatformVersion`). Nothing was reusable except
build configuration. The package is not federated, so
`plugin_platform_interface` added nothing an abstract class doesn't:
`NativeFlowPlatform` is a plain abstract class with a method-channel
implementation and a test fake. Zero runtime dependencies besides Flutter.

### D2. One native runtime, many adapters
Requirements are aggregated (`RuntimeRequirements.merge`) and sent as one
capability set. Android runs exactly one foreground service whose type mask
is derived from the set. Never one service per adapter.

### D3. Capabilities, not mechanisms, in the Dart API
Adapters declare `RuntimeCapability`s. Android maps them to FGS types and
permissions; iOS to background modes and authorizations. Status is reported as
`supported / partiallySupported / permissionRequired / restricted /
unavailable`. Nothing is faked: an undeclared manifest/Info.plist entry is
`unavailable`.

### D4. FGS types = requested ∩ declared
Passing an undeclared type to `startForeground` throws. The plugin manifest
declares `dataSync`; apps widen it with `tools:replace`. NativeFlow intersects
and prefers specific types (location/microphone/mediaPlayback) over generic
ones, and among generic types prefers `specialUse`/`remoteMessaging` (no time
limit) over `dataSync` (6 h/24 h on Android 15).

### D5. Android background Flutter engine with single ownership
Flutter's default activity destroys its engine when the activity goes, which
kills Dart sockets even though the FGS keeps the process alive. The only
legitimate way to keep running Dart is a second engine. It is created only
when needed (runtime active, no participating engine, entrypoint registered)
and handed back to the UI engine via `release` → destroy. Adapters therefore
run in exactly one engine; switching costs one reconnect (`recover`).
Alternative rejected: requiring apps to cache their UI engine (invasive, still
breaks on process death).

### D6. Persistent event store is native, JSON-lines, bounded
Native events (notification/overlay actions, boot, interruptions) happen when
Flutter is dead, so the store lives natively. A JSON-lines append log is
O(1) per write, crash-tolerant, testable on the JVM without Robolectric, and
has an identical format on iOS. SQLite would be faster for large volumes but
the store is deliberately not a database.

### D7. At-least-once delivery, cumulative auto-ack
Dart dispatches each batch synchronously and then acks the highest id.
Listeners must tolerate redelivery (`event.id` is stable). Manual ack mode
can be added if apps need to ack after async work (marked `ponytail:`).

### D8. Recovery restores only recorded intent
`start()` writes `active = true`; `stop()` clears it. Service restarts, app
relaunches and (opt-in) reboots restore only that intent. A restart-loop guard
gives up after 5 sticky restarts in 10 minutes.

### D9. Default `recover` = `stop` then `start`
Recovery must not leak the broken connection, so the default implementation
releases before re-establishing. Adapters can override `recover` (e.g. to
resume from the last acknowledged server offset).

### D10. Overlays are native and declarative
Rendering Flutter widgets in an overlay requires a live engine; a driver
bubble must work without one. A bounded node set (card/text/button/image/
progress, ≤ 32 nodes, images ≤ 256 KB) is rendered with Android views. The
reserved `close` action hides natively. Flutter-rendered overlays are a
roadmap item.

### D11. Full-screen only through notifications, only for calls/alarms
`RuntimeNotification.fullScreen` takes a `FullScreenReason` (incomingCall,
alarm). It uses `setFullScreenIntent` only when `USE_FULL_SCREEN_INTENT` is
granted, otherwise degrades to heads-up. There is no API to launch an
activity from the background.

### D12. iOS: no service emulation
iOS gets the same Dart API, but `start()` only records intent. On
backgrounding without a declared and required continuous mode, NativeFlow
uses the finite background time to `pause` adapters before suspension and
`resume`s them on foreground. BGTaskScheduler registration is an explicit
`NativeFlowPlugin.registerBackgroundTasks()` call in `AppDelegate`, because
plugins may register after launch finishes (UIScene), which would crash.

### D13. iOS location/microphone looked up dynamically
Statically referencing CoreLocation/AVFoundation would make App Store Connect
demand purpose strings from every app using NativeFlow (ITMS-90683).
NativeFlow only *reports* those statuses on iOS; the app's own library
requests them.

### D14. Live Activities via a shared generic attributes type
ActivityKit matches attributes by type. NativeFlow ships
`NativeFlowActivityAttributes { values: [String:String], ContentState {
values } }`; the app's Widget Extension declares an identical struct and
renders the values. Keeps the plugin generic without code generation.

### D15. No wake locks, no WorkManager, no polling
FGS keeps the process; network callbacks and app lifecycle notifications
drive everything. WorkManager/AlarmManager would add a dependency and
behaviour nobody asked for yet (see ROADMAP).

### D16. Android background tasks on JobScheduler, not WorkManager
`scheduleBackgroundTask` needed an Android side for parity with iOS
BGTaskScheduler. JobScheduler is a framework API (no dependency) and gives
the OS-scheduled, constraint-based semantics needed. Each run becomes a
persisted event; if no engine participates, the background engine is started
(when an entrypoint is registered) and destroyed once tasks complete and the
runtime is inactive.

### D17. Publishing metadata
MIT license (© flutterbuddy1). `doc/` follows pub's layout convention. The iOS
plugin ships a privacy manifest declaring its only required-reason API,
`UserDefaults`.

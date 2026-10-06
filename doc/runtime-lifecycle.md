# Runtime lifecycle

## API

```dart
await NativeFlow.initialize();             // sync with native state; safe to repeat
await NativeFlow.attach(adapter);          // RuntimeSession
await NativeFlow.start(const RuntimeOptions(
  notification: ForegroundNotification(title: 'Online', body: 'Receiving rides',
      actions: [NotificationAction(id: 'go_offline', label: 'Go offline')]),
  persistent: true,     // Android START_STICKY
  restoreOnBoot: false, // opt-in reboot restore
));
NativeFlow.state;        // RuntimeState
NativeFlow.states;       // Stream<RuntimeState>
NativeFlow.sessions;     // List<RuntimeSession>
await NativeFlow.detach('socket');
await NativeFlow.stop(); // stops adapters (reverse order) then the runtime; clears intent
```

`start()` and `stop()` complete only after the native side has really started
or stopped. On Android that means the service has entered the foreground, or
has been destroyed.

## Runtime states

| State | Meaning |
|---|---|
| `stopped` | Not running, no recorded intent |
| `starting` / `stopping` | Transitional |
| `running` | Active |
| `interrupted` | The OS stopped it without the app asking (time limit, kill, refused restore). Intent is kept |
| `recovering` | Being restored after process recreation, relaunch or reboot |

`state.isActive` is true for `running` and `recovering`.

## Session states

Each attached adapter has a `RuntimeSession` (`state`, `states`, `attempts`,
`lastError`).

```
idle ─▶ starting ─▶ running ◀─▶ paused
          │            │
          ▼            ▼
      recovering ◀─▶ waitingForNetwork
          │
          ▼
        failed          (any) ─▶ stopping ─▶ stopped
```

Transitions are validated against a table. An illegal transition is a bug:
it asserts in debug builds and is logged in release builds.

## Engine ownership (Android)

Flutter's default activity destroys its engine when the activity goes. The
foreground service keeps the *process* alive, but your Dart sockets die with
the engine. NativeFlow fixes this without fighting the OS:

1. Register a `backgroundEntrypoint` in `initialize`.
2. When the runtime is active and no engine participates (UI swiped away,
   process restarted by the OS, boot restore, a background task), NativeFlow
   starts a background engine that runs it. Your entrypoint re-attaches the
   same adapters; they receive `recover(runtimeRestored)`.
3. When the UI engine calls `initialize` again, NativeFlow asks the background
   engine to `release` its adapters (≤ 3 s), destroys it, and only then
   answers the UI. The UI's adapters receive `recover(runtimeRestored)`.
4. `stop()` destroys the background engine.

Adapters therefore run in exactly one engine at a time. `NativeFlow.isBackgroundEngine`
tells you which one you are in.

## iOS

`start()` records intent and enables lifecycle coordination; there is no
service. See [iOS setup → what iOS does](ios-setup.md#what-ios-does-with-your-runtime).

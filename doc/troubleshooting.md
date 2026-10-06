# Troubleshooting

### `NativeFlowException(notInitialized)`
Call `await NativeFlow.initialize()` before any other API. In the Android
background engine, your entrypoint must call it too.

### `start()` throws `notAllowed`
Android 12+ forbids starting a foreground service from the background. Call
`start()` from a visible screen. Restores after process death and reboot are
handled by NativeFlow.

### `start()` throws `permissionRequired`
An attached adapter requires `location` or `microphone` and the permission is
not granted. Call `NativeFlow.permissions.requestRequired()` first.

### The service runs as `dataSync` although I need `location`
Your manifest doesn't declare the type. Override
`com.nativeflow.RuntimeService`'s `foregroundServiceType` with
`tools:replace` ([Android setup](android-setup.md#choose-the-service-type)).

### `interrupted` with reason `timeLimit`
Android 15 limits `dataSync` services to 6 h per 24 h. Declare a type that
matches your workload (`location`, `remoteMessaging`, `specialUse`). The
runtime restores on the next app launch.

### Adapters stop when the app is swiped away (Android)
Register a `backgroundEntrypoint` in `initialize` and re-attach your adapters
inside it ([Runtime lifecycle](runtime-lifecycle.md#engine-ownership-android)).

### Adapters pause after ~20 s in background (iOS)
This is iOS suspension. Only declared continuous modes (location, audio,
VoIP) keep the app running, and only if your app legitimately uses them and
an adapter requires `persistentRuntime`, `location` or `audio`.

### Notification taps don't arrive on iOS
Set `UNUserNotificationCenter.current().delegate = self` in your
`AppDelegate` before calling `super.application(...)`.

### `scheduleBackgroundTask` throws `unavailable` on iOS
Expected on simulators. On devices: call
`NativeFlowPlugin.registerBackgroundTasks()` in `AppDelegate` and add the
identifiers to `BGTaskSchedulerPermittedIdentifiers`.

### `activities.start` throws
The status must be `supported`: iOS 16.1+, `NSSupportsLiveActivities`, a
widget extension declaring `NativeFlowActivityAttributes` verbatim, and Live
Activities enabled by the user.

### Events are delivered twice
Delivery is at-least-once. De-duplicate by `event.id`.

### The runtime stops on Xiaomi / Huawei / Oppo / Vivo / Samsung
OEM battery managers kill foreground services beyond Android's rules.
NativeFlow reports `interrupted` and restores at the next legitimate
opportunity; it does not work around the vendor. Guide users to the vendor's
battery settings from your UI (see dontkillmyapp.com).

### Seeing what happens
`NativeFlowConfig(logVerbosity: LogVerbosity.verbose)`, then
`adb logcat -s NativeFlow` or the Xcode console (`[NativeFlow]`).

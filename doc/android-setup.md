# Android setup

## What the plugin adds

The plugin's manifest is merged into your app and contains only:

| Entry | Why |
|---|---|
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | The runtime service |
| `POST_NOTIFICATIONS` | The foreground notification (requested only via `NativeFlow.permissions.request`) |
| `ACCESS_NETWORK_STATE` | Network events |
| `RECEIVE_BOOT_COMPLETED` | Opt-in reboot restore |
| `com.nativeflow.RuntimeService` (type `dataSync`) | The **one** runtime service |
| `com.nativeflow.BackgroundTaskService` | JobScheduler background tasks |
| `NotificationActionReceiver`, `BootReceiver` (not exported) | Notification actions, reboot |

No location, microphone, overlay or full-screen permission is ever added for
you.

## Choose the service type

Android 14+ requires every foreground service to declare a type, and Google
Play asks you to justify it. NativeFlow starts the service with
**(types your adapters need) ∩ (types you declared)** and never passes an
undeclared type (that would crash).

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
  <application>
    <service android:name="com.nativeflow.RuntimeService"
             android:foregroundServiceType="location|dataSync"
             tools:replace="android:foregroundServiceType"/>
  </application>
</manifest>
```

| Workload | Type | Also declare |
|---|---|---|
| Driver / fleet / delivery tracking | `location` | `FOREGROUND_SERVICE_LOCATION`, `ACCESS_FINE_LOCATION` |
| Voice agent, call | `microphone` (`phoneCall` if you are a calling app) | `FOREGROUND_SERVICE_MICROPHONE`, `RECORD_AUDIO` |
| Audio playback | `mediaPlayback` | `FOREGROUND_SERVICE_MEDIA_PLAYBACK` |
| Persistent chat/messaging socket | `remoteMessaging` or `specialUse` | `FOREGROUND_SERVICE_REMOTE_MESSAGING` / `_SPECIAL_USE` + Play justification |
| Sync | `dataSync` (default) | — (limited to 6 h per 24 h on Android 15+) |

When adapters require `location`/`microphone`/`audio`, only those specific
types are used. Otherwise the first declared of `specialUse`,
`remoteMessaging`, `dataSync` is used.

## Optional features

```xml
<!-- Floating overlay -->
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<!-- Full-screen call/alarm notifications -->
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
```

For full-screen notifications, the activity they open (your launcher
activity) should show over the lock screen:

```xml
<activity android:name=".MainActivity"
          android:showWhenLocked="true"
          android:turnScreenOn="true" ... />
```

Notification deep links (`RuntimeNotification.deepLink`) are delivered as the
launch intent's data. Add an intent filter for your scheme so routing
packages such as `app_links` / `go_router` can handle them:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <category android:name="android.intent.category.BROWSABLE"/>
  <data android:scheme="myapp"/>
</intent-filter>
```

## Small icon

The foreground notification uses your app icon by default. Pass a
monochrome drawable for a correct status-bar icon:

```dart
const RuntimeOptions(notification: ForegroundNotification(smallIcon: 'ic_stat_runtime'))
```

## Release builds

No ProGuard/R8 rules are needed. The background entrypoint must be annotated
`@pragma('vm:entry-point')` so tree shaking keeps it.

## Platform rules NativeFlow respects

- Android 12+: foreground services cannot be started from the background. Call
  `NativeFlow.start()` while your UI is visible; otherwise it throws
  `notAllowed`.
- Android 14+: typed services need their runtime permission at start, so
  `start()` throws `permissionRequired` instead of crashing.
- Android 15+: `dataSync` services are stopped after 6 h per day
  (`runtime.interrupted{reason: timeLimit}`), and several types cannot be
  started from `BOOT_COMPLETED`. Restore then posts a "Tap to resume"
  notification.
- OEM battery managers can kill services regardless. See
  [Troubleshooting](troubleshooting.md#the-runtime-stops-on-xiaomi--huawei--oppo--vivo--samsung).

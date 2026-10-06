# Notifications

Rendered natively, so taps and actions work, and are persisted, while
Flutter is not running.

## Channels (Android 8+)

```dart
await NativeFlow.notifications.createChannel(const NotificationChannel(
  id: 'rides',
  name: 'Ride requests',
  description: 'New ride offers',
  importance: NotificationImportance.high, // heads-up
));
```

Built-in channels: `nativeflow_runtime` (low, foreground service),
`nativeflow_default`, `nativeflow_urgent` (high, full-screen). iOS ignores
channels.

## Showing

```dart
await NativeFlow.notifications.show(RuntimeNotification(
  id: 100,                              // > 1; reuse to update
  title: 'New ride request',
  body: '2.4 km · ₹182',
  channelId: 'rides',
  actions: const [                      // max 3
    NotificationAction(id: 'accept', label: 'Accept', opensApp: true),
    NotificationAction(id: 'decline', label: 'Decline'),
  ],
  deepLink: Uri.parse('myapp://ride/42'),
  group: 'rides',                       // Android group / iOS thread
  ongoing: false,
  payload: {'ride': 42},                // returned with tap/action events
));
await NativeFlow.notifications.cancel(100);
```

## Handling taps and actions

```dart
NativeFlow.notifications.taps.listen((e) => open(e.payload['deepLink']));
NativeFlow.notifications.actions.listen((e) {
  switch (e.payload['actionId']) {
    case 'accept': accept(e.payload['data']);
    case 'decline': decline(e.payload['data']);
  }
});
```

- `opensApp: false` actions are handled in the background by a broadcast
  receiver (Android) or the notification delegate (iOS); the notification is
  dismissed.
- `opensApp: true` launches the app directly. This is not a trampoline, so it
  works on Android 12+.
- Events tapped while the app was dead are delivered on the next
  `initialize`.

iOS requires `UNUserNotificationCenter.current().delegate = self` in
`AppDelegate` (see [iOS setup](ios-setup.md)). NativeFlow only handles
notifications it posted, so other notification plugins keep working.

## Full-screen (Android)

Only for incoming calls and alarms:

```dart
const RuntimeNotification(id: 200, title: 'Rider calling',
    fullScreen: FullScreenReason.incomingCall);
```

Uses a full-screen intent only when `USE_FULL_SCREEN_INTENT` is declared and
granted (a user-grantable permission on Android 14+), otherwise a heads-up
notification. There is no API to start an activity from the background. On
iOS, use CallKit for calls.

## Foreground notification

Configured by `RuntimeOptions.notification` and updated with
[`NativeFlow.present`](presentation.md). Its actions arrive as
`notificationAction` events like any other notification's.

## Permission

Android 13+ and iOS need the user's grant:

```dart
await NativeFlow.permissions.request(RuntimeCapability.notifications);
```

Without it, Android still runs the foreground service, but the notification
appears only in the task manager.

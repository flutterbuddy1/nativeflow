# Presentation, Live Activities and widgets

## `NativeFlow.present`: say what, not how

```dart
await NativeFlow.present(const RuntimePresentation(
  title: 'Trip in progress',
  body: '2.1 km to drop-off',
  progress: .6,
  values: {'eta': '6 min'},      // extra Live Activity values (iOS)
  actions: [NotificationAction(id: 'sos', label: 'SOS', opensApp: true)],
));
```

| Platform | Runtime running | Otherwise |
|---|---|---|
| Android | Updates the foreground notification (title, body, progress bar, actions) | Posts a notification |
| iOS | Updates the running NativeFlow Live Activity (`title`, `body`, `progress` and `values` merged into its state) if enabled | Posts a notification |

## Live Activities (iOS 16.1+)

Requires `NSSupportsLiveActivities` and a widget extension declaring
`NativeFlowActivityAttributes` (see [iOS setup](ios-setup.md#live-activities-and-widgets)).

```dart
if (await NativeFlow.activities.status() == CapabilityStatus.supported) {
  final id = await NativeFlow.activities.start(
    attributes: {'rider': 'Asha'},                 // fixed for the activity
    state: {'status': 'Arriving', 'eta': '4 min'}, // dynamic
  );
  await NativeFlow.activities.update(id, {'status': 'On trip', 'eta': '12 min'});
  await NativeFlow.activities.end(id, finalState: {'status': 'Completed'});
}
```

`restricted` means the user disabled Live Activities for the app. On Android
these calls throw `unavailable`.

## Home-screen widgets (iOS)

```dart
await NativeFlow.activities.updateWidget(
  appGroup: 'group.com.example.app',
  key: 'driver',
  data: {'status': 'Online'},
  kind: 'DriverStatus', // omit to reload all widgets
);
```

This writes `data` to the App Group's `UserDefaults` under `key` and reloads
the widget timelines. Your widget reads it in its timeline provider.

# NativeFlow example

A driver app that exercises **every** public NativeFlow API, one screen per
area. Each call shows its result, including honest platform refusals such as
`unavailable`, in a snackbar and in the Events log.

| Screen | APIs |
|---|---|
| Runtime & adapters | `start` (notification, persistent, restoreOnBoot), `stop`, `attach`, `detach`, `sessions`, `state`, `network`, `isBackgroundEngine`, failure simulation |
| Capabilities & permissions | `capabilities`, `permissions.status / request / requestRequired` |
| Events | `events.stream / on / named`, `emit` (transient, persisted, rejected) |
| Notifications | `createChannel`, `show` (actions, deep link, group, ongoing, full-screen), `cancel`, `taps`, `actions` |
| Overlay (Android) | `status`, `requestPermission`, `show`, `update`, `move`, `resize`, `state`, `hide`, `actions`, `closed` |
| Presentation & Live Activities | `present`, `activities.status / start / update / end / updateWidget` |
| Background & logging | `scheduleBackgroundTask`, `completeBackgroundTask`, `logger.verbosity` |

Adapters ([lib/adapters](lib/adapters)) each keep their own library:
WebSocket (`web_socket_channel`, public echo server), Socket.IO
(`socket_io_client`), MQTT (`mqtt_client`, test.mosquitto.org), location
(simulated stream) and a failure-simulation adapter.

## Run

```bash
flutter run
```

For the Socket.IO adapter, start the bundled dependency-free server first:

```bash
dart run tool/socket_io_server.dart
```

## Platform setup shown here

- Android: [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml) widens the runtime service to `location|dataSync` and adds overlay and full-screen permissions plus a deep-link scheme.
- iOS: [`Info.plist`](ios/Runner/Info.plist) (background modes, task identifiers, Live Activities), [`AppDelegate.swift`](ios/Runner/AppDelegate.swift) and the [`NativeFlowWidgets`](ios/NativeFlowWidgets/NativeFlowWidgets.swift) extension (Live Activity + App Group home-screen widget).

## Tests

```bash
flutter test integration_test -d <device>   # every API on a real runtime
```

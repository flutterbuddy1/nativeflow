<center>
<img src="https://github.com/flutterbuddy1/nativeflow/blob/main/assets/logo.png?raw=true" height="100" width="100">

# NativeFlow

[![pub package](https://img.shields.io/pub/v/nativeflow.svg)](https://pub.dev/packages/nativeflow)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</center>


An OS-compliant native runtime for long-running, event-driven Flutter apps:
driver, delivery, fleet, field-service, IoT, chat and voice-agent apps.

**NativeFlow provides the runtime. Your libraries own the protocol. The OS
owns background policy.**

<center>
<img src="https://github.com/flutterbuddy1/nativeflow/blob/main/assets/workflow.png?raw=true">
</center>

## Features

| | Android | iOS |
|---|:---:|:---:|
| One runtime for all workloads (single foreground service) | ✅ | coordinated background modes |
| Adapters for your own libraries, with backoff + network-aware recovery | ✅ | ✅ |
| Restore after process death / app relaunch | ✅ | ✅ (relaunch) |
| Opt-in reboot restore | ✅ | — |
| Adapters survive the UI being swiped away (background engine) | ✅ | — |
| Persistent, acknowledged event store | ✅ | ✅ |
| Network state events | ✅ | ✅ |
| Notifications: channels, actions, deep links, groups | ✅ | ✅ |
| Full-screen call/alarm notifications | ✅ | — |
| Native floating overlays | ✅ | — |
| Live Activities / widget refresh | — | ✅ |
| OS-scheduled background tasks | JobScheduler | BGTaskScheduler |
| Honest capability report (`supported` … `unavailable`) | ✅ | ✅ |

## What NativeFlow is NOT

- Not a socket, MQTT, HTTP, BLE or location library. It never opens a connection or reads GPS for you.
- Not a way to keep an app "alive forever" or to bypass Doze, OEM battery managers or iOS suspension. No library can guarantee a connection.
- Not a database. The event store is a bounded queue of runtime signals.

## Install

```yaml
dependencies:
  nativeflow: ^0.1.0
```

Then follow [Android setup](doc/android-setup.md) and [iOS setup](doc/ios-setup.md).
Declare only what your app legitimately uses.

## Quick start

```dart
import 'package:nativeflow/nativeflow.dart';

await NativeFlow.initialize();

await NativeFlow.attach(RuntimeAdapter(
  id: 'driver',
  requirements: const RuntimeRequirements(capabilities: {
    RuntimeCapability.backgroundExecution,
    RuntimeCapability.network,
    RuntimeCapability.notifications,
  }),
  start: (ctx) async {
    channel = WebSocketChannel.connect(url);   // your library
    await channel.ready;                        // throw → retried with backoff
    channel.stream.listen(
      (m) => ctx.emit('ride.offer', payload: {'raw': '$m'}, persist: true),
      onError: ctx.reportFailure,               // → recover()
      onDone: () => ctx.reportFailure('closed'),
    );
  },
  stop: (ctx) async => channel.sink.close(),
));

await NativeFlow.start(const RuntimeOptions(
  notification: ForegroundNotification(title: 'You are online'),
));

NativeFlow.events.named('ride.offer').listen((e) => showOffer(e.payload));
```

## Documentation

| | |
|---|---|
| [Getting started](doc/getting-started.md) | Install, setup, first adapter |
| [Adapters](doc/adapters.md) | Wrapping WebSocket / Socket.IO / MQTT / BLE / location |
| [Runtime lifecycle](doc/runtime-lifecycle.md) | States, sessions, engine ownership |
| [Recovery](doc/recovery.md) | Backoff, process death, reboot |
| [Events](doc/events.md) | Event bus, persistence, acknowledgement |
| [Notifications](doc/notifications.md) · [Overlays](doc/overlays.md) · [Presentation & Live Activities](doc/presentation.md) | UI outside your app |
| [Background tasks](doc/background-tasks.md) · [Permissions](doc/permissions.md) · [Capabilities](doc/capabilities.md) | Platform features |
| [Logging](doc/logging.md) · [Testing](doc/testing.md) · [Troubleshooting](doc/troubleshooting.md) · [Migration](doc/migration.md) | Operating it |
| [Architecture](doc/ARCHITECTURE.md) · [Decisions](doc/DECISIONS.md) · [Roadmap](doc/ROADMAP.md) | Design |

## Example

[`example/`](example) is a complete driver app with one screen per API area.
It covers every public method, plus WebSocket, Socket.IO, MQTT and location
adapters that keep their own libraries, and a Live Activity widget extension.

## Platform limits, stated plainly

- **Android:** foreground services must be started while the app is visible
  (Android 12+); typed services need their permission (Android 14+);
  `dataSync` is limited to 6 h per day and some types cannot start at boot
  (Android 15+). OEM battery managers may still kill the service. NativeFlow
  reports `interrupted` and restores at the next legitimate opportunity.
- **iOS:** there are no persistent services. Without a declared continuous
  background mode (location, audio, VoIP), adapters are paused before
  suspension. BGTaskScheduler timing is decided by the OS.
- **Events** are delivered at least once. De-duplicate by `event.id`.

## Security

A closed native command set with no reflective dispatch. Ids and payloads are
validated (JSON only, 32 KB maximum). Payloads, notification content and
credentials are never logged. No background activity launches. No dangerous
permission is declared or requested on your behalf. The privacy manifest is
included.

## License

[MIT](LICENSE)

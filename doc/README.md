# NativeFlow documentation

**Start here**

1. [Getting started](getting-started.md): install, set up the platforms, run your first adapter.
2. [Android setup](android-setup.md) and [iOS setup](ios-setup.md): manifest, Info.plist and AppDelegate.
3. [Capabilities](capabilities.md): what each platform can deliver and how it is reported.

**Guides**

| Guide | Covers |
|---|---|
| [Adapters](adapters.md) | Wrapping your own WebSocket / Socket.IO / MQTT / BLE / location code |
| [Runtime lifecycle](runtime-lifecycle.md) | `start`, `stop`, states, sessions, engine ownership |
| [Recovery](recovery.md) | Backoff, network-aware retries, process death, reboot |
| [Events](events.md) | Event bus, persisted events, acknowledgement |
| [Notifications](notifications.md) | Channels, actions, deep links, full-screen |
| [Overlays](overlays.md) | Native floating windows on Android |
| [Presentation & Live Activities](presentation.md) | `present`, Live Activities, widgets |
| [Background tasks](background-tasks.md) | JobScheduler / BGTaskScheduler |
| [Permissions](permissions.md) | Status, explicit requests, `requestRequired` |
| [Logging](logging.md) | Verbosity, custom sinks, what is never logged |
| [Testing](testing.md) | Fakes, native tests, integration tests |
| [Troubleshooting](troubleshooting.md) | Common errors and OEM issues |
| [Migration](migration.md) | Moving from `flutter_background_service` and hand-rolled services |

**Design**

- [Architecture](ARCHITECTURE.md)
- [Decisions](DECISIONS.md)
- [Roadmap](ROADMAP.md)

**API reference:** [pub.dev/documentation/nativeflow](https://pub.dev/documentation/nativeflow/latest/)

# Roadmap

Status legend: ✅ done and verified · 🟡 done, verified only by build/static
analysis (needs a device run) · ⏭ deferred (why)

| Phase | Scope | Status |
|---|---|---|
| 0 | Repository audit, docs skeleton | ✅ |
| 1 | Core Dart API (`NativeFlow`, state, capabilities, requirements, events) | ✅ 38 Dart unit tests |
| 2 | Adapter system (callbacks + subclassing, context, auto-cancelled listeners) | ✅ |
| 3 | Android runtime: supervisor, single FGS, type aggregation, graceful stop | ✅ logic tests + integration test on emulator (API 37) |
| 4 | Android network/lifecycle events | 🟡 |
| 5 | Recovery engine (Dart backoff + network-aware; native restore decisions, restart-loop guard) | ✅ Dart + Kotlin tests |
| 6 | Event store (JSONL, ack, retry, retention, compaction, torn writes) | ✅ Kotlin + Swift tests |
| 7 | Bridge: batching, snapshot sync, drain + dedupe + cumulative ack, engine hand-off | ✅ Dart tests · 🟡 hand-off on device |
| 8 | Android notifications (channels, actions, deep links, heads-up, grouping) | 🟡 |
| 9 | Android overlays (declarative native, drag, persistence, close) | 🟡 |
| 10 | Full-screen via notifications for calls/alarms only | 🟡 |
| 11 | Boot / package-replaced / sticky restore | ✅ decision tests · 🟡 device |
| 12 | iOS runtime (capabilities, pause/resume, BGTaskScheduler, network) | ✅ XCTests · 🟡 background behaviour on device |
| 13 | iOS Live Activities / widgets, `RuntimePresentation` | 🟡 (needs a widget extension target to run) |
| 14 | Permission system (`status`, `request`, `requestRequired`) | ✅ Dart tests |
| 15 | Tests (Dart 38+1, Android JVM 15, iOS XCTest 14, integration 3 on Android emulator + iOS simulator) | ✅ |
| 16 | Example app: driver runtime, WebSocket/Socket.IO/MQTT/location adapters, notifications, overlay, Live Activity, recovery log | ✅ builds Android + iOS |
| 17 | Documentation | ✅ |

## Next

1. **Device verification matrix** — run `example/integration_test` and a
   manual checklist (swipe-away hand-off, `adb shell am kill`, reboot restore,
   Android 15 `dataSync` timeout via `adb shell cmd activity
   set-fgs-timeout`) on API 26/31/34/35 + one OEM device; iOS 15/16.1/17+.
2. **Instrumented Android tests** for `RuntimeService` and `OverlayManager`
   (needs Robolectric or an emulator in CI).
4. **Manual acknowledgement mode** for events processed asynchronously
   (`ponytail:` marker in `runtime.dart`).
6. **Optional Flutter-rendered overlays** (engine-backed, with native
   fallback when no engine is available).
7. **Optional partial wake lock** requirement for workloads that need CPU
   timers with the screen off — opt-in, documented battery cost.
8. **CI**: `flutter analyze`, `flutter test`, Gradle unit tests, `xcodebuild
   test` on every PR.

## Known limitations

See README → Platform limits and [Capabilities → OEM restrictions](capabilities.md#oem-and-battery-restrictions-android).

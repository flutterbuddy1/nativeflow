# Testing

## Testing your adapters (unit tests)

`NativeFlowRuntime` takes a `NativeFlowPlatform`. Supply a fake to test your
adapters' lifecycle and recovery without a device:

```dart
class FakePlatform implements NativeFlowPlatform {
  final _events = StreamController<List<Object?>>.broadcast();
  @override
  Future<T?> invoke<T>(String method, [Map<String, Object?>? args]) async =>
      switch (method) {
        'initialize' => {'state': 'stopped', 'network': {'connected': true}} as T,
        'start' => 'running' as T,
        'stop' => 'stopped' as T,
        _ => null,
      };
  @override
  Stream<List<Object?>> get events => _events.stream;
  @override
  void setCallHandler(Future<Object?> Function(String) handler) {}
}

test('my adapter recovers', () async {
  final runtime = NativeFlowRuntime(FakePlatform());
  await runtime.initialize();
  await runtime.attach(myAdapter);
  await runtime.start();
  // ...
});
```

To test code that uses the static `NativeFlow` facade, set
`NativeFlow.debugRuntime = NativeFlowRuntime(FakePlatform())`.

The package's own fake, with event pushing and call recording, is in
[`test/fake_platform.dart`](../test/fake_platform.dart).

## The package's test suites

| Suite | Run |
|---|---|
| Dart unit (runtime, sessions, recovery, bridge sync, validation) | `flutter test` |
| Android JVM (event store, service-type aggregation, recovery decisions) | `cd example/android && ./gradlew :nativeflow:testDebugUnitTest` |
| iOS XCTest (event store, capabilities, plugin commands) | `cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'` |
| Integration: every public API on a real runtime | `cd example && flutter test integration_test -d <device>` |

## Exercising permission paths on Android

While the integration test runs, grant from another terminal so the overlay,
notification and background-task paths execute instead of being skipped:

```bash
PKG=com.example.nativeflow_example
while true; do
  adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS
  adb shell appops set $PKG SYSTEM_ALERT_WINDOW allow
  adb shell appops set $PKG USE_FULL_SCREEN_INTENT allow
  adb shell cmd jobscheduler run -f $PKG 20038
  sleep 3
done
```

## Manual OS scenarios

| Scenario | How |
|---|---|
| Process death + sticky restart | `adb shell am kill com.example.nativeflow_example` (with the app in background) |
| UI swiped away → background engine | Swipe the app from recents while running; watch logcat `NativeFlow` |
| Reboot restore | Start with `restoreOnBoot: true`, then `adb reboot` |
| Android 15 `dataSync` time limit | `adb shell device_config put activity_manager data_sync_fgs_timeout_duration 60000` |
| iOS suspension | Background the app without a continuous mode; `runtime.paused` arrives after ~20 s |

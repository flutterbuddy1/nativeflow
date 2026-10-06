# Getting started

## 1. Install

```yaml
dependencies:
  nativeflow: ^0.1.0
```

Requirements: Flutter ≥ 3.35, Android minSdk 24 (targetSdk 34+ recommended),
iOS 15+ (Live Activities need 16.1+).

## 2. Platform setup

Declare only what your app legitimately uses:

- [Android setup](android-setup.md): foreground service types and permissions.
- [iOS setup](ios-setup.md): background modes, `AppDelegate`, Live Activity extension.

With no setup at all you still get an Android `dataSync` foreground service,
network events, notifications and the event store.

## 3. Initialize and start

```dart
import 'package:nativeflow/nativeflow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NativeFlow.initialize();
  runApp(const MyApp());
}

// Later, from a visible screen (Android 12+ forbids starting a
// foreground service from the background):
await NativeFlow.start();
```

## 4. Plug in your workload

```dart
final chat = RuntimeAdapter(
  id: 'chat',
  requirements: const RuntimeRequirements(capabilities: {
    RuntimeCapability.backgroundExecution,
    RuntimeCapability.network,
  }),
  start: (ctx) async {
    final channel = WebSocketChannel.connect(Uri.parse('wss://chat.example.com'));
    await channel.ready;
    ctx.onNamed('chat.send', (e) => channel.sink.add(e.payload['text']));
    channel.stream.listen(
      (m) => ctx.emit('chat.message', payload: {'raw': '$m'}, persist: true),
      onError: ctx.reportFailure,
      onDone: () => ctx.reportFailure('closed'),
    );
    _channel = channel;
  },
  stop: (ctx) async => _channel?.sink.close(),
);

await NativeFlow.attach(chat);
await NativeFlow.start();
```

`start` throwing or `ctx.reportFailure(...)` triggers recovery with
exponential backoff ([Recovery](recovery.md)). Messages emitted with
`persist: true` survive process death ([Events](events.md)).

## 5. Keep running when the UI is closed (Android)

```dart
@pragma('vm:entry-point')
void nativeFlowBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await NativeFlow.initialize(backgroundEntrypoint: nativeFlowBackground);
  await NativeFlow.attach(chat); // same adapters; they get recover()
}

await NativeFlow.initialize(backgroundEntrypoint: nativeFlowBackground);
```

See [Runtime lifecycle → engine ownership](runtime-lifecycle.md#engine-ownership-android).

## 6. Run the example

```bash
cd example && flutter run
```

It is a driver app with a screen per API area. Every call shows its result,
including honest refusals such as `unavailable`. The Socket.IO adapter talks
to a bundled test server:

```bash
cd example && dart run tool/socket_io_server.dart
```

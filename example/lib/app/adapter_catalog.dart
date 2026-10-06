import 'dart:io';

import 'package:nativeflow/nativeflow.dart';

import '../adapters/demo_adapter.dart';
import '../adapters/location_adapter.dart';
import '../adapters/mqtt_adapter.dart';
import '../adapters/socket_io_adapter.dart';
import '../adapters/websocket_adapter.dart';

/// Every adapter the example can attach. Each wraps the app's OWN library;
/// NativeFlow only runs, observes and recovers it.
class AdapterCatalog {
  AdapterCatalog._();

  static final demo = DemoAdapter();

  /// Public echo server.
  static final websocket = WebSocketAdapter(
    url: Uri.parse('wss://ws.postman-echo.com/raw'),
  );

  /// Local test server: `dart run tool/socket_io_server.dart`.
  static final socketIo = SocketIoAdapter(
    url: Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000',
    events: const ['ride.offer'],
  );

  /// Public test broker.
  static final mqtt = MqttAdapter(
    host: 'test.mosquitto.org',
    clientId: 'nativeflow-${DateTime.now().millisecondsSinceEpoch}',
    topic: 'nativeflow/example/${DateTime.now().millisecondsSinceEpoch}',
  );

  static final location = LocationAdapter(
    positions: simulatedPositions,
    upload: (_) async {},
  );

  static final List<RuntimeAdapter> all = [
    demo,
    websocket,
    location,
    socketIo,
    mqtt,
  ];

  /// Attached on every launch, including inside the Android background
  /// engine. The others can be attached at runtime from the Runtime screen.
  static final List<RuntimeAdapter> defaults = [demo, websocket, location];
}

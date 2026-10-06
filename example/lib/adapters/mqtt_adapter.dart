import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:nativeflow/nativeflow.dart';

/// IoT telemetry over `mqtt_client`. NativeFlow does not know MQTT exists.
class MqttAdapter extends RuntimeAdapter {
  MqttAdapter({
    required this.host,
    required this.clientId,
    required this.topic,
    super.id = 'mqtt',
  }) : super(
         requirements: const RuntimeRequirements(
           capabilities: {
             RuntimeCapability.backgroundExecution,
             RuntimeCapability.network,
           },
         ),
         recoveryPolicy: const RecoveryPolicy(
           maxAttempts: null, // devices should retry forever, with backoff
           maxDelay: Duration(minutes: 2),
         ),
       );

  final String host;
  final String clientId;
  final String topic;
  MqttServerClient? _client;
  StreamSubscription<Object?>? _updates;

  @override
  Future<void> start(AdapterContext context) async {
    final client = MqttServerClient(host, clientId)
      ..keepAlivePeriod = 60
      ..autoReconnect = false; // NativeFlow's RecoveryPolicy handles it
    final status = await client.connect();
    if (status?.state != MqttConnectionState.connected) {
      throw StateError('MQTT connect failed: ${status?.state}');
    }
    client.onDisconnected = () =>
        context.reportFailure(StateError('mqtt disconnected'));
    client.subscribe(topic, MqttQos.atLeastOnce);
    _updates = client.updates!.listen((messages) {
      for (final m in messages) {
        final publish = m.payload as MqttPublishMessage;
        context.emit(
          'mqtt.message',
          payload: {
            'topic': m.topic,
            'data': MqttPublishPayload.bytesToStringAsString(
              publish.payload.message,
            ),
          },
          persist: true,
        );
      }
    });
    _client = client;
  }

  /// Publishes [message] to [topic]; it comes back through the subscription.
  void publish(String message) {
    final builder = MqttClientPayloadBuilder()..addString(message);
    _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  @override
  Future<void> stop(AdapterContext context) async {
    await _updates?.cancel();
    _client?.onDisconnected = null; // our own disconnect is not a failure
    _client?.disconnect();
    _client = null;
  }
}

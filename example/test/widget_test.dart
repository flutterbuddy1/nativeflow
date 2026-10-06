import 'package:flutter_test/flutter_test.dart';
import 'package:nativeflow/nativeflow.dart';
import 'package:nativeflow_example/adapters/location_adapter.dart';
import 'package:nativeflow_example/adapters/websocket_adapter.dart';

void main() {
  test('driver adapters aggregate into one runtime requirement set', () {
    final merged = RuntimeRequirements.merge([
      WebSocketAdapter(url: Uri.parse('wss://example.invalid')).requirements,
      LocationAdapter(
        positions: simulatedPositions,
        upload: (_) async {},
      ).requirements,
    ]);
    expect(merged.capabilities, {
      RuntimeCapability.backgroundExecution,
      RuntimeCapability.network,
      RuntimeCapability.location,
      RuntimeCapability.persistentRuntime,
    });
  });
}

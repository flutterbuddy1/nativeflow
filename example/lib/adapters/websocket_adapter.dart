import 'dart:async';

import 'package:nativeflow/nativeflow.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A plain `web_socket_channel` connection run inside the NativeFlow runtime.
///
/// NativeFlow does not open, read or reconnect this socket. It keeps the
/// process eligible to run (Android foreground service), tells the adapter
/// when the network or runtime changes, and calls [recover] with backoff
/// after [AdapterContext.reportFailure].
class WebSocketAdapter extends RuntimeAdapter {
  WebSocketAdapter({required this.url, super.id = 'websocket'})
    : super(
        requirements: const RuntimeRequirements(
          capabilities: {
            RuntimeCapability.backgroundExecution,
            RuntimeCapability.network,
          },
        ),
      );

  final Uri url;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;

  @override
  Future<void> start(AdapterContext context) async {
    final channel = WebSocketChannel.connect(url);
    await channel.ready; // throws -> NativeFlow schedules recover()
    _channel = channel;
    _subscription = channel.stream.listen(
      // Persist messages that must survive process death until handled.
      (message) => context.emit(
        'ws.message',
        payload: {'data': '$message'},
        persist: true,
      ),
      onError: context.reportFailure,
      onDone: () => context.reportFailure(StateError('socket closed')),
    );
    // Close promptly when the OS reports the network gone; recovery
    // reconnects when it returns (RecoveryPolicy.waitForNetwork).
    context.on(RuntimeEventType.networkLost, (_) {
      context.reportFailure(StateError('network lost'));
    });
  }

  @override
  Future<void> stop(AdapterContext context) async {
    await _subscription?.cancel(); // cancel first: no onDone -> no failure
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }

  // iOS suspension: close cleanly instead of being frozen mid-frame.
  @override
  Future<void> pause(AdapterContext context) => stop(context);

  @override
  Future<void> resume(AdapterContext context) => start(context);

  void send(String message) => _channel?.sink.add(message);
}

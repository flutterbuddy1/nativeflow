import 'package:nativeflow/nativeflow.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Socket.IO via `socket_io_client`, owned entirely by the app.
///
/// Socket.IO already reconnects on its own, so this adapter leaves that to
/// the library and only uses NativeFlow for what Socket.IO cannot do: keep
/// running in the background, survive engine/process recreation, and
/// persist events (e.g. ride offers) until the app handles them.
class SocketIoAdapter extends RuntimeAdapter {
  SocketIoAdapter({
    required this.url,
    required this.events,
    super.id = 'socket.io',
  }) : super(
         requirements: const RuntimeRequirements(
           capabilities: {
             RuntimeCapability.backgroundExecution,
             RuntimeCapability.network,
             RuntimeCapability.notifications,
           },
         ),
       );

  final String url;

  /// Server events to forward into the NativeFlow event store.
  final List<String> events;
  io.Socket? _socket;

  @override
  Future<void> start(AdapterContext context) async {
    final socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    for (final name in events) {
      socket.on(name, (data) {
        context.emit(
          'socketio.$name',
          payload: {'data': data is Map || data is List ? data : '$data'},
          persist: true,
        );
      });
    }
    socket.onConnectError(
      (e) => context.logger.warning('socket.io connect error'),
    );
    socket.connect();
    _socket = socket;
  }

  @override
  Future<void> stop(AdapterContext context) async {
    _socket?.dispose();
    _socket = null;
  }

  @override
  Future<void> pause(AdapterContext context) async => _socket?.disconnect();

  @override
  Future<void> resume(AdapterContext context) async => _socket?.connect();
}

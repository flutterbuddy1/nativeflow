// Minimal Socket.IO (Engine.IO v4, WebSocket transport) server for the
// example's SocketIoAdapter. No dependencies:
//
//   dart run tool/socket_io_server.dart          # listens on :3000
//
// Android emulator: http://10.0.2.2:3000 · iOS simulator: http://localhost:3000
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 3000 : int.parse(args.first);
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('socket.io test server on :$port');
  var rides = 0;
  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket transport only')
        ..close();
      continue;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final sid = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    socket.add(
      '0${jsonEncode({'sid': sid, 'upgrades': [], 'pingInterval': 25000, 'pingTimeout': 20000, 'maxPayload': 1000000})}',
    );
    Timer? offers;
    final ping = Timer.periodic(
      const Duration(seconds: 25),
      (_) => socket.add('2'),
    );
    socket.listen(
      (packet) {
        if (packet == '40' || (packet is String && packet.startsWith('40'))) {
          socket.add('40${jsonEncode({'sid': '$sid-io'})}');
          stdout.writeln('client $sid connected');
          offers = Timer.periodic(const Duration(seconds: 10), (_) {
            rides++;
            socket.add(
              '42${jsonEncode([
                'ride.offer',
                {'ride': rides, 'fare': 120 + rides},
              ])}',
            );
          });
        } else if (packet is String && packet.startsWith('42')) {
          stdout.writeln('client $sid event ${packet.substring(2)}');
        }
      },
      onDone: () {
        ping.cancel();
        offers?.cancel();
        stdout.writeln('client $sid disconnected');
      },
    );
  }
}

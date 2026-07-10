import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xalarm_sync_server/hub.dart';

/// xalarm sync relay. In-memory only — restart wipes everything, which is a
/// feature: sessions are ephemeral by design.
void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final hub = SyncHub();

  final wsHandler = webSocketHandler((WebSocketChannel channel, _) {
    final socketClient = hub.attach((msg) => channel.sink.add(msg.encode()));
    channel.stream.listen(
      (raw) {
        if (raw is String) {
          hub.onMessage(hub.effective(socketClient), raw);
        }
      },
      onDone: () => hub.onDisconnect(hub.effective(socketClient)),
      onError: (_) => hub.onDisconnect(hub.effective(socketClient)),
      cancelOnError: true,
    );
  });

  Response handler(Request req) {
    switch (req.url.path) {
      case 'health':
        return Response.ok('ok');
      case '':
        return Response.ok(
          'xalarm sync relay — connect via /ws '
          '(${hub.registeredCount} registered)',
        );
      default:
        return Response.notFound('not found');
    }
  }

  // Accept both /ws (direct) and /sync (the path reverse proxies forward
  // when the app's default wss://…/sync route is proxied as-is).
  final pipeline = Cascade()
      .add((req) => req.url.path == 'ws' || req.url.path == 'sync'
          ? wsHandler(req)
          : Response.notFound('not found'))
      .add(handler)
      .handler;

  final server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  stdout.writeln('xalarm sync relay listening on :${server.port}');
}

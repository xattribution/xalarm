import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xalarm_sync_server/hub.dart';

/// Full-stack test: real HTTP server, real WebSockets, two clients.
class TestClient {
  TestClient(this.channel) {
    channel.stream.listen((raw) {
      final msg = SyncMessage.decode(raw as String);
      inbox.add(msg);
      _waiters.removeWhere((w) {
        if (w.$1(msg)) {
          w.$2.complete(msg);
          return true;
        }
        return false;
      });
    }, onDone: () => closed = true);
  }

  final WebSocketChannel channel;
  final List<SyncMessage> inbox = [];
  final List<(bool Function(SyncMessage), Completer<SyncMessage>)> _waiters =
      [];
  bool closed = false;

  void send(SyncMessage msg) => channel.sink.add(msg.encode());

  Future<T> expectMsg<T extends SyncMessage>({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    for (final m in inbox) {
      if (m is T) {
        inbox.remove(m);
        return m;
      }
    }
    final completer = Completer<SyncMessage>();
    _waiters.add(((m) => m is T, completer));
    final result = await completer.future.timeout(timeout);
    inbox.remove(result);
    return result as T;
  }

  Future<void> close() => channel.sink.close();
}

void main() {
  late HttpServer server;
  late SyncHub hub;
  late Uri wsUri;

  setUp(() async {
    hub = SyncHub(graceMs: 400); // short limbo for tests
    final wsHandler = webSocketHandler((WebSocketChannel channel, _) {
      final socketClient =
          hub.attach((msg) => channel.sink.add(msg.encode()));
      channel.stream.listen(
        (raw) => hub.onMessage(hub.effective(socketClient), raw as String),
        onDone: () => hub.onDisconnect(hub.effective(socketClient)),
        onError: (_) => hub.onDisconnect(hub.effective(socketClient)),
        cancelOnError: true,
      );
    });
    final pipeline = Cascade()
        .add((req) => req.url.path == 'ws' || req.url.path == 'sync'
            ? wsHandler(req)
            : Response.notFound(''))
        .handler;
    server = await shelf_io.serve(pipeline, InternetAddress.loopbackIPv4, 0);
    wsUri = Uri.parse('ws://127.0.0.1:${server.port}/ws');
  });

  tearDown(() => server.close(force: true));

  Future<TestClient> connect() async =>
      TestClient(IOWebSocketChannel.connect(wsUri));

  Future<(TestClient, TestClient, Welcome, Welcome)> pairTwo() async {
    final alice = await connect();
    final bob = await connect();
    alice.send(const Hello(name: 'Alice'));
    bob.send(const Hello(name: 'Bob'));
    final wa = await alice.expectMsg<Welcome>();
    final wb = await bob.expectMsg<Welcome>();
    alice.send(PairRequest(targetCode: wb.code));
    final incoming = await bob.expectMsg<PairIncoming>();
    expect(incoming.name, 'Alice');
    expect(incoming.code, wa.code);
    bob.send(const PairAccept());
    final pa = await alice.expectMsg<Paired>();
    final pb = await bob.expectMsg<Paired>();
    expect(pa.peerName, 'Bob');
    expect(pb.peerName, 'Alice');
    return (alice, bob, wa, wb);
  }

  test('register → pair → action relays with server timestamp', () async {
    final (alice, bob, _, _) = await pairTwo();

    alice.send(const ActionMsg(
      action: TimerStart(endsAtServerMs: 123456, durationMs: 60000),
    ));
    final relayed = await bob.expectMsg<PeerAction>();
    expect(relayed.action, isA<TimerStart>());
    expect(relayed.seq, 1);
    expect(relayed.serverTime, greaterThan(0));
    // Sender must NOT receive its own action echoed back.
    expect(alice.inbox.whereType<PeerAction>(), isEmpty);

    await alice.close();
    await bob.close();
  });

  test('decline notifies the requester', () async {
    final alice = await connect();
    final bob = await connect();
    alice.send(const Hello(name: 'Alice'));
    bob.send(const Hello(name: 'Bob'));
    await alice.expectMsg<Welcome>();
    final wb = await bob.expectMsg<Welcome>();
    alice.send(PairRequest(targetCode: wb.code));
    await bob.expectMsg<PairIncoming>();
    bob.send(const PairDecline());
    await alice.expectMsg<PairDeclined>();
    await alice.close();
    await bob.close();
  });

  test('unknown code errors', () async {
    final alice = await connect();
    alice.send(const Hello(name: 'Alice'));
    await alice.expectMsg<Welcome>();
    alice.send(const PairRequest(targetCode: 'ZZZZZZ'));
    final err = await alice.expectMsg<ErrorMsg>();
    expect(err.message, contains('code'));
    await alice.close();
  });

  test('drop → limbo → both resume within grace → restored + state replay',
      () async {
    final (alice, bob, _, wb) = await pairTwo();

    // Establish some state first.
    alice.send(const ActionMsg(
      action: StopwatchStart(accumulatedMs: 1000, sinceServerMs: 5),
    ));
    await bob.expectMsg<PeerAction>();

    // Bob drops.
    await bob.close();
    final lost = await alice.expectMsg<PeerLost>();
    expect(lost.graceMs, 400);

    // Both reconnect within the grace window.
    alice.send(const Resume());
    final bob2 = await connect();
    bob2.send(Resume(resumeKey: wb.resumeKey));

    await alice.expectMsg<Restored>();
    await bob2.expectMsg<Restored>();

    // State replay reaches both sides.
    final replayA = await alice.expectMsg<PeerAction>();
    final replayB = await bob2.expectMsg<PeerAction>();
    expect(replayA.action, isA<StopwatchStart>());
    expect(replayB.action, isA<StopwatchStart>());

    // Session is functional again.
    bob2.send(const ActionMsg(action: StopwatchReset()));
    final after = await alice.expectMsg<PeerAction>();
    expect(after.action, isA<StopwatchReset>());

    await alice.close();
    await bob2.close();
  });

  test('drop → grace expires → purged, codes freed', () async {
    final (alice, bob, wa, wb) = await pairTwo();

    await bob.close();
    await alice.expectMsg<PeerLost>();

    // Only Alice resumes; Bob never comes back.
    alice.send(const Resume());
    final purged = await alice.expectMsg<Purged>(
      timeout: const Duration(seconds: 2),
    );
    expect(purged, isA<Purged>());

    // The old resume key is now useless.
    final bob2 = await connect();
    bob2.send(Resume(resumeKey: wb.resumeKey));
    final err = await bob2.expectMsg<ErrorMsg>();
    expect(err.message, contains('nothing'));

    // Old codes are freed — pairing against them fails.
    bob2.send(const Hello(name: 'Bob2'));
    await bob2.expectMsg<Welcome>();
    bob2.send(PairRequest(targetCode: wa.code));
    final err2 = await bob2.expectMsg<ErrorMsg>();
    expect(err2.message, contains('code'));

    await alice.close();
    await bob2.close();
  });

  test('the /sync path works end to end (reverse-proxy passthrough)', () async {
    final syncUri = Uri.parse('ws://127.0.0.1:${server.port}/sync');
    final alice = TestClient(IOWebSocketChannel.connect(syncUri));
    final bob = TestClient(IOWebSocketChannel.connect(syncUri));
    alice.send(const Hello(name: 'Alice'));
    bob.send(const Hello(name: 'Bob'));
    await alice.expectMsg<Welcome>();
    final wb = await bob.expectMsg<Welcome>();
    alice.send(PairRequest(targetCode: wb.code));
    await bob.expectMsg<PairIncoming>();
    bob.send(const PairAccept());
    await alice.expectMsg<Paired>();
    await bob.expectMsg<Paired>();
    await alice.close();
    await bob.close();
  });

  test('explicit bye also triggers limbo for both', () async {
    final (alice, bob, _, _) = await pairTwo();
    alice.send(const Bye());
    final lostBob = await bob.expectMsg<PeerLost>();
    expect(lostBob.graceMs, 400);
    await alice.close();
    await bob.close();
  });
}

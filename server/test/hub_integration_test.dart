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

/// Full-stack test: real HTTP server, real WebSockets, several clients.
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
    }, onDone: () => closed.complete());
  }

  final WebSocketChannel channel;
  final List<SyncMessage> inbox = [];
  final List<(bool Function(SyncMessage), Completer<SyncMessage>)> _waiters =
      [];
  final closed = Completer<void>();

  void send(SyncMessage msg) => channel.sink.add(msg.encode());
  void sendRaw(String raw) => channel.sink.add(raw);

  Future<T> expectMsg<T extends SyncMessage>({
    bool Function(T)? where,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    bool matches(SyncMessage m) => m is T && (where == null || where(m));
    for (final m in inbox) {
      if (matches(m)) {
        inbox.remove(m);
        return m as T;
      }
    }
    final completer = Completer<SyncMessage>();
    _waiters.add((matches, completer));
    final result = await completer.future.timeout(timeout);
    inbox.remove(result);
    return result as T;
  }

  /// Drains everything of type T currently queued (order preserved).
  List<T> drain<T extends SyncMessage>() {
    final out = inbox.whereType<T>().toList();
    inbox.removeWhere((m) => m is T);
    return out;
  }

  Future<void> close() => channel.sink.close();
}

void main() {
  late HttpServer server;
  late SyncHub hub;
  late Uri wsUri;

  Future<void> startServer(SyncHub h) async {
    hub = h;
    final wsHandler = webSocketHandler((WebSocketChannel channel, _) {
      final socketClient = hub.attach(
        (msg) => channel.sink.add(msg.encode()),
        () => channel.sink.close(),
      );
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
  }

  setUp(() => startServer(SyncHub(graceMs: 400, helloTimeoutMs: 300)));
  tearDown(() => server.close(force: true));

  Future<TestClient> connect([Uri? uri]) async =>
      TestClient(IOWebSocketChannel.connect(uri ?? wsUri));

  Future<(TestClient, Welcome)> register(String name) async {
    final c = await connect();
    c.send(Hello(name: name));
    return (c, await c.expectMsg<Welcome>());
  }

  /// Alice hosts, Bob joins.
  Future<(TestClient, TestClient, Welcome, Welcome)> pairTwo() async {
    final (alice, wa) = await register('Alice');
    final (bob, wb) = await register('Bob');
    bob.send(PairRequest(targetCode: wa.code));
    final incoming = await alice.expectMsg<PairIncoming>();
    expect(incoming.name, 'Bob');
    expect(incoming.code, wb.code);
    alice.send(PairAccept(code: wb.code));
    final sa = await alice.expectMsg<SessionState>();
    final sb = await bob.expectMsg<SessionState>();
    expect(sa.hostCode, wa.code);
    expect(sb.hostCode, wa.code);
    expect(sa.members.map((m) => m.name), ['Alice', 'Bob']);
    expect(sb.membersCanControl, isTrue);
    return (alice, bob, wa, wb);
  }

  test('register → join → action fans out with server timestamp', () async {
    final (alice, bob, _, wb) = await pairTwo();

    bob.send(const ActionMsg(
      action: TimerStart(endsAtServerMs: 123456, durationMs: 60000),
    ));
    final relayed = await alice.expectMsg<PeerAction>();
    expect(relayed.action, isA<TimerStart>());
    expect(relayed.seq, 1);
    expect(relayed.fromCode, wb.code);
    expect(relayed.serverTime, greaterThan(0));
    // Sender must NOT receive its own action echoed back.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bob.drain<PeerAction>(), isEmpty);

    await alice.close();
    await bob.close();
  });

  test('a third member joins via ANY member code and gets state replay',
      () async {
    final (alice, bob, wa, wb) = await pairTwo();
    alice.send(const ActionMsg(
      action: StopwatchStart(accumulatedMs: 1000, sinceServerMs: 5),
    ));
    await bob.expectMsg<PeerAction>();

    final (carol, wc) = await register('Carol');
    carol.send(PairRequest(targetCode: wb.code)); // Bob's code → Alice hosts
    final incoming = await alice.expectMsg<PairIncoming>();
    expect(incoming.code, wc.code);
    alice.send(const PairAccept()); // no code = oldest pending
    final state = await carol.expectMsg<SessionState>();
    expect(state.hostCode, wa.code);
    expect(state.members.length, 3);
    final replay = await carol.expectMsg<PeerAction>();
    expect(replay.action, isA<StopwatchStart>());
    await bob.expectMsg<SessionState>(where: (s) => s.members.length == 3);

    // Fan-out reaches everyone but the sender.
    carol.send(const ActionMsg(action: StopwatchReset()));
    await alice.expectMsg<PeerAction>();
    await bob.expectMsg<PeerAction>();

    for (final c in [alice, bob, carol]) {
      await c.close();
    }
  });

  test('host can lock controls: members see, cannot act', () async {
    final (alice, bob, _, _) = await pairTwo();
    alice.send(const SetPolicy(membersCanControl: false));
    final sb = await bob.expectMsg<SessionState>(
      where: (s) => s.membersCanControl == false,
    );
    expect(sb.membersCanControl, isFalse);

    bob.send(const ActionMsg(action: StopwatchReset()));
    final err = await bob.expectMsg<ErrorMsg>();
    expect(err.code, ErrorCode.viewOnly);

    // Host still controls and members still receive.
    alice.send(const ActionMsg(action: StopwatchReset()));
    final relayed = await bob.expectMsg<PeerAction>();
    expect(relayed.action, isA<StopwatchReset>());

    // A member cannot flip the policy.
    bob.send(const SetPolicy(membersCanControl: true));
    final err2 = await bob.expectMsg<ErrorMsg>();
    expect(err2.code, ErrorCode.notHost);

    await alice.close();
    await bob.close();
  });

  test('host can kick; kicked member stays registered', () async {
    final (alice, bob, wa, wb) = await pairTwo();
    alice.send(Kick(code: wb.code));
    final purged = await bob.expectMsg<Purged>();
    expect(purged.reason, PurgeReason.kicked);
    final sa = await alice.expectMsg<SessionState>(
      where: (s) => s.members.length == 1,
    );
    expect(sa.members.single.code, wa.code);

    // Bob can immediately ask to join again with the same code.
    bob.send(PairRequest(targetCode: wa.code));
    await alice.expectMsg<PairIncoming>();
    // Members can't kick.
    alice.send(const PairAccept());
    await bob.expectMsg<SessionState>();
    bob.send(Kick(code: wa.code));
    expect((await bob.expectMsg<ErrorMsg>()).code, ErrorCode.notHost);

    await alice.close();
    await bob.close();
  });

  test('joining a session declines anyone waiting on you', () async {
    final (alice, wa) = await register('Alice');
    final (bob, wb) = await register('Bob');
    final (carol, _) = await register('Carol');
    // Carol asks Bob; before Bob answers, Bob joins Alice.
    carol.send(PairRequest(targetCode: wb.code));
    await bob.expectMsg<PairIncoming>();
    bob.send(PairRequest(targetCode: wa.code));
    await alice.expectMsg<PairIncoming>();
    alice.send(const PairAccept());
    await bob.expectMsg<SessionState>();
    await carol.expectMsg<PairDeclined>();
    // Carol can now join the session through Bob's code instead.
    carol.send(PairRequest(targetCode: wb.code));
    await alice.expectMsg<PairIncoming>();
    for (final c in [alice, bob, carol]) {
      await c.close();
    }
  });

  test('decline notifies the requester', () async {
    final (alice, wa) = await register('Alice');
    final (bob, wb) = await register('Bob');
    bob.send(PairRequest(targetCode: wa.code));
    await alice.expectMsg<PairIncoming>();
    alice.send(PairDecline(code: wb.code));
    await bob.expectMsg<PairDeclined>();
    await alice.close();
    await bob.close();
  });

  test('unknown code errors', () async {
    final (alice, _) = await register('Alice');
    alice.send(const PairRequest(targetCode: 'ZZZZZZ'));
    final err = await alice.expectMsg<ErrorMsg>();
    expect(err.message, contains('code'));
    await alice.close();
  });

  test('member drop → resume within grace → restored + replay', () async {
    final (alice, bob, _, wb) = await pairTwo();
    alice.send(const ActionMsg(
      action: StopwatchStart(accumulatedMs: 1000, sinceServerMs: 5),
    ));
    await bob.expectMsg<PeerAction>();

    await bob.close();
    final lost = await alice.expectMsg<PeerLost>();
    expect(lost.isHost, isFalse);
    expect(lost.code, wb.code);
    final frozenState = await alice.expectMsg<SessionState>();
    expect(frozenState.member(wb.code)?.connected, isFalse);

    // Session keeps working for the host meanwhile (member is not the host).
    alice.send(const ActionMsg(action: StopwatchLap(atMs: 10)));

    final bob2 = await connect();
    bob2.send(Resume(resumeKey: wb.resumeKey));
    final restored = await alice.expectMsg<Restored>();
    expect(restored.code, wb.code);
    final state = await bob2.expectMsg<SessionState>();
    expect(state.member(wb.code)?.connected, isTrue);
    // Only the latest action per category is replayed (the lap superseded
    // the start in the 'stopwatch' slot).
    final replay = await bob2.expectMsg<PeerAction>();
    expect(replay.action, isA<StopwatchLap>());

    bob2.send(const ActionMsg(action: StopwatchReset()));
    final after = await alice.expectMsg<PeerAction>();
    expect(after.action, isA<StopwatchReset>());

    await alice.close();
    await bob2.close();
  });

  test('member drop → grace expires → removed, session continues', () async {
    final (alice, bob, wa, wb) = await pairTwo();
    await bob.close();
    await alice.expectMsg<PeerLost>();
    final gone = await alice.expectMsg<SessionState>(
      where: (s) => s.members.length == 1,
      timeout: const Duration(seconds: 2),
    );
    expect(gone.members.single.code, wa.code);

    // The old resume key is now useless…
    final bob2 = await connect();
    bob2.send(Resume(resumeKey: wb.resumeKey));
    expect((await bob2.expectMsg<ErrorMsg>()).code, ErrorCode.noSession);
    // …but Alice is still hosting and joinable.
    bob2.send(const Hello(name: 'Bob2'));
    await bob2.expectMsg<Welcome>();
    bob2.send(PairRequest(targetCode: wa.code));
    await alice.expectMsg<PairIncoming>();

    await alice.close();
    await bob2.close();
  });

  test('host drop freezes the session; host resume thaws it', () async {
    final (alice, bob, wa, _) = await pairTwo();
    await alice.close();
    final lost = await bob.expectMsg<PeerLost>();
    expect(lost.isHost, isTrue);
    final frozen = await bob.expectMsg<SessionState>();
    expect(frozen.hostConnected, isFalse);

    bob.send(const ActionMsg(action: StopwatchReset()));
    expect((await bob.expectMsg<ErrorMsg>()).code, ErrorCode.frozen);

    final alice2 = await connect();
    alice2.send(Resume(resumeKey: wa.resumeKey));
    await bob.expectMsg<Restored>();
    final thawed = await bob.expectMsg<SessionState>(
      where: (s) => s.hostConnected,
    );
    expect(thawed.hostCode, wa.code);
    bob.send(const ActionMsg(action: StopwatchReset()));
    await alice2.expectMsg<PeerAction>();

    await alice2.close();
    await bob.close();
  });

  test('host drop → grace expires → session purged, members stay registered',
      () async {
    final (alice, bob, wa, _) = await pairTwo();
    await alice.close();
    await bob.expectMsg<PeerLost>();
    final purged = await bob.expectMsg<Purged>(
      timeout: const Duration(seconds: 2),
    );
    expect(purged.reason, PurgeReason.hostLost);
    // Bob still has his code and can host a new session; Alice was freed.
    final (carol, _) = await register('Carol');
    expect(hub.registeredCount, 2);
    carol.send(PairRequest(targetCode: wa.code));
    expect((await carol.expectMsg<ErrorMsg>()).message, contains('code'));
    await carol.close();
    await bob.close();
  });

  test('host bye ends the session; member bye just leaves', () async {
    final (alice, bob, wa, _) = await pairTwo();
    final (carol, wc) = await register('Carol');
    carol.send(PairRequest(targetCode: wa.code));
    await alice.expectMsg<PairIncoming>();
    alice.send(PairAccept(code: wc.code));
    await carol.expectMsg<SessionState>();
    await bob.expectMsg<SessionState>(where: (s) => s.members.length == 3);

    carol.send(const Bye());
    await bob.expectMsg<SessionState>(where: (s) => s.members.length == 2);
    await alice.expectMsg<SessionState>(where: (s) => s.members.length == 2);

    alice.send(const Bye());
    final purged = await bob.expectMsg<Purged>();
    expect(purged.reason, PurgeReason.hostLeft);
    // Bob is still registered and can be joined.
    expect(hub.registeredCount, 1);

    await alice.close();
    await bob.close();
    await carol.close();
  });

  test('hello then resume drops the throwaway registration', () async {
    final (alice, bob, _, wb) = await pairTwo();
    await bob.close();
    await alice.expectMsg<PeerLost>();
    final bob2 = await connect();
    bob2.send(const Hello(name: 'Ghost'));
    await bob2.expectMsg<Welcome>();
    expect(hub.registeredCount, 3);
    bob2.send(Resume(resumeKey: wb.resumeKey));
    await alice.expectMsg<Restored>();
    expect(hub.registeredCount, 2);
    await alice.close();
    await bob2.close();
  });

  test('oversized frames and unregistered idlers get disconnected', () async {
    final big = await connect();
    big.sendRaw('{"type":"hello","name":"${'x' * 5000}"}');
    await big.closed.future.timeout(const Duration(seconds: 2));

    final idle = await connect();
    await idle.closed.future.timeout(const Duration(seconds: 2));
  });

  test('message and pair-request floods are throttled', () async {
    final (alice, wa) = await register('Alice');
    final (bob, _) = await register('Bob');
    // Pair budget: 5 burst.
    for (var i = 0; i < 7; i++) {
      bob.send(const PairRequest(targetCode: 'ZZZZZZ'));
    }
    final errors = <ErrorMsg>[];
    for (var i = 0; i < 7; i++) {
      errors.add(await bob.expectMsg<ErrorMsg>());
    }
    expect(errors.where((e) => e.code == ErrorCode.rateLimited), isNotEmpty);
    expect(errors.where((e) => e.code == null).length, 5);

    // Message budget: 40 burst.
    for (var i = 0; i < 60; i++) {
      alice.send(Ping(t0: i));
    }
    var limited = 0;
    for (var i = 0; i < 60; i++) {
      final m = await alice.expectMsg<SyncMessage>(
        where: (m) => m is Pong || m is ErrorMsg,
      );
      if (m is ErrorMsg && m.code == ErrorCode.rateLimited) limited++;
    }
    expect(limited, greaterThan(0));
    expect(wa.code, isNotEmpty);
    await alice.close();
    await bob.close();
  });

  test('the /sync path works end to end (reverse-proxy passthrough)', () async {
    final syncUri = Uri.parse('ws://127.0.0.1:${server.port}/sync');
    final alice = await connect(syncUri);
    final bob = await connect(syncUri);
    alice.send(const Hello(name: 'Alice'));
    bob.send(const Hello(name: 'Bob'));
    final wa = await alice.expectMsg<Welcome>();
    await bob.expectMsg<Welcome>();
    bob.send(PairRequest(targetCode: wa.code));
    await alice.expectMsg<PairIncoming>();
    alice.send(const PairAccept());
    await alice.expectMsg<SessionState>();
    await bob.expectMsg<SessionState>();
    await alice.close();
    await bob.close();
  });

  test('names are sanitised', () {
    expect(SyncHub.sanitizeName('  Jar\u200bed \u202E evil  '), 'Jared evil');
    expect(SyncHub.sanitizeName('\x00\x1f'), '');
  });
}

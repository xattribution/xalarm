import 'dart:math';

import 'package:sync_protocol/sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PairCodes', () {
    test('generates 6 chars from the safe alphabet', () {
      final rng = Random(42);
      for (var i = 0; i < 50; i++) {
        final code = PairCodes.generate(rng);
        expect(code.length, 6);
        for (final c in code.split('')) {
          expect(PairCodes.alphabet.contains(c), isTrue);
        }
      }
    });

    test('normalize accepts dashes/spaces/lowercase, rejects junk', () {
      expect(PairCodes.normalize('abc-234'), 'ABC234');
      expect(PairCodes.normalize(' ab C2 34 '), 'ABC234');
      expect(PairCodes.normalize('ABC23'), isNull); // too short
      expect(PairCodes.normalize('ABC2340'), isNull); // too long + zero
      expect(PairCodes.normalize('ABC10I'), isNull); // ambiguous chars
    });

    test('pretty formats as XXX-XXX', () {
      expect(PairCodes.pretty('ABC234'), 'ABC-234');
    });
  });

  group('ClockSync', () {
    test('computes offset from a clean sample', () {
      final cs = ClockSync();
      // Local sends at 1000, server (running 500ms ahead) stamps at 1550,
      // reply lands at 1100 → midpoint 1050 → offset +500.
      cs.addSample(t0: 1000, serverTime: 1550, t1: 1100);
      expect(cs.offsetMs, 500);
      expect(cs.toServer(2000), 2500);
      expect(cs.toLocal(2500), 2000);
    });

    test('median rejects one jittery outlier', () {
      final cs = ClockSync();
      cs.addSample(t0: 1000, serverTime: 1550, t1: 1100); // +500
      cs.addSample(t0: 2000, serverTime: 2552, t1: 2100); // +502
      cs.addSample(t0: 3000, serverTime: 4400, t1: 3900); // junk RTT → +950
      expect(cs.offsetMs, inInclusiveRange(500, 510));
    });

    test('no samples → zero offset', () {
      expect(ClockSync().offsetMs, 0);
      expect(ClockSync().hasFix, isFalse);
    });
  });

  group('message codec round-trips', () {
    final samples = <SyncMessage>[
      const Hello(name: 'Jared'),
      const Resume(resumeKey: 'abc123'),
      const Resume(),
      const PairRequest(targetCode: 'ABC234'),
      const PairAccept(),
      const PairAccept(code: 'XYZ789'),
      const PairDecline(code: 'XYZ789'),
      const SetPolicy(membersCanControl: false),
      const Kick(code: 'XYZ789'),
      const ActionMsg(action: TimerStart(endsAtServerMs: 999, durationMs: 60000)),
      const Ping(t0: 123),
      const Bye(),
      const Welcome(code: 'ABC234', resumeKey: 'k'),
      const PairIncoming(name: 'Sam', code: 'XYZ789'),
      const PairDeclined(),
      const SessionState(
        hostCode: 'ABC234',
        membersCanControl: false,
        members: [
          SessionMember(name: 'Jared', code: 'ABC234', connected: true),
          SessionMember(name: 'Sam', code: 'XYZ789', connected: false),
        ],
      ),
      const PeerAction(
        action: StopwatchStart(accumulatedMs: 100, sinceServerMs: 5000),
        serverTime: 5001,
        seq: 7,
        fromCode: 'XYZ789',
      ),
      const Pong(t0: 123, serverTime: 456),
      const PeerLost(code: 'XYZ789', isHost: false, graceMs: 5000),
      const Restored(code: 'XYZ789'),
      const Purged(reason: PurgeReason.kicked),
      const ErrorMsg(message: 'nope'),
      const ErrorMsg(message: 'nope', code: ErrorCode.viewOnly),
    ];

    test('every message survives encode → decode', () {
      for (final msg in samples) {
        final decoded = SyncMessage.decode(msg.encode());
        expect(decoded.toJson(), msg.toJson(), reason: msg.runtimeType.toString());
      }
    });
  });

  group('decode rejects junk with one exception type', () {
    test('wrong field types surface as FormatException', () {
      expect(() => SyncMessage.decode('{"type":"ping","t0":"x"}'),
          throwsFormatException);
      expect(() => SyncMessage.decode('{"type":"hello"}'),
          throwsFormatException);
      expect(() => SyncMessage.decode('[]'), throwsFormatException);
      expect(() => SyncMessage.decode('not json'), throwsFormatException);
      expect(() => SyncMessage.decode('{"type":"nope"}'),
          throwsFormatException);
    });
  });

  group('SyncLink', () {
    test('round-trips code + server', () {
      const link = SyncLink(code: 'ABC234', server: 'wss://x.example/sync');
      final parsed = SyncLink.parse(link.encode());
      expect(parsed?.code, 'ABC234');
      expect(parsed?.server, 'wss://x.example/sync');
      expect(link.encode(), startsWith('xalarm://sync?'));
    });

    test('accepts a bare code in any spelling', () {
      expect(SyncLink.parse(' abc-234 ')?.code, 'ABC234');
      expect(SyncLink.parse('abc-234')?.server, isNull);
    });

    test('rejects other schemes, bad codes, and non-websocket servers', () {
      expect(SyncLink.parse('https://evil.example/?code=ABC234'), isNull);
      expect(SyncLink.parse('xalarm://sync?code=ABC10I'), isNull);
      expect(SyncLink.parse(''), isNull);
      final noServer =
          SyncLink.parse('xalarm://sync?code=ABC234&server=javascript:1');
      expect(noServer?.code, 'ABC234');
      expect(noServer?.server, isNull);
    });
  });

  group('action codec round-trips', () {
    final actions = <SyncAction>[
      const TimerSet(durationMs: 300000),
      const TimerStart(endsAtServerMs: 1234567, durationMs: 300000),
      const TimerPause(remainingMs: 120000, durationMs: 300000),
      const TimerReset(durationMs: 300000),
      const StopwatchStart(accumulatedMs: 42, sinceServerMs: 999),
      const StopwatchPause(accumulatedMs: 4242),
      const StopwatchReset(),
      const StopwatchLap(atMs: 61000),
    ];

    test('every action survives toJson → fromJson', () {
      for (final a in actions) {
        expect(SyncAction.fromJson(a.toJson()).toJson(), a.toJson());
      }
    });
  });
}

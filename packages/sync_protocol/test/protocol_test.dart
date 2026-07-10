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
      const PairDecline(),
      const ActionMsg(action: TimerStart(endsAtServerMs: 999, durationMs: 60000)),
      const Ping(t0: 123),
      const Bye(),
      const Welcome(code: 'ABC234', resumeKey: 'k'),
      const PairIncoming(name: 'Sam', code: 'XYZ789'),
      const PairDeclined(),
      const Paired(peerName: 'Sam', peerCode: 'XYZ789'),
      const PeerAction(
        action: StopwatchStart(accumulatedMs: 100, sinceServerMs: 5000),
        serverTime: 5001,
        seq: 7,
      ),
      const Pong(t0: 123, serverTime: 456),
      const PeerLost(graceMs: 5000),
      const Restored(),
      const Purged(),
      const ErrorMsg(message: 'nope'),
    ];

    test('every message survives encode → decode', () {
      for (final msg in samples) {
        final decoded = SyncMessage.decode(msg.encode());
        expect(decoded.toJson(), msg.toJson(), reason: msg.runtimeType.toString());
      }
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

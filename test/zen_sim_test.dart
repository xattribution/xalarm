import 'package:flutter_test/flutter_test.dart';
import 'package:xalarm/features/timer/domain/zen_sim.dart';

void main() {
  group('ZenSandSim time flow', () {
    test('upright: counts down in real time', () {
      final sim = ZenSandSim(totalSeconds: 100);
      for (var i = 0; i < 10; i++) {
        sim.step(1.0, gx: 0, gy: 1, gz: 0);
      }
      expect(sim.remaining, closeTo(90, 0.001));
      expect(sim.flow, ZenFlow.running);
    });

    test('flat on the desk keeps running (deliberate cheat)', () {
      final sim = ZenSandSim(totalSeconds: 100);
      sim.step(5.0, gx: 0, gy: 0.1, gz: 0.95);
      expect(sim.orientation, ZenOrientation.flat);
      expect(sim.flow, ZenFlow.running);
      expect(sim.remaining, closeTo(95, 0.001));
    });

    test('inverted: rewinds at 4x, capped at total', () {
      final sim = ZenSandSim(totalSeconds: 100, remainingSeconds: 50);
      sim.step(5.0, gx: 0, gy: -1, gz: 0);
      expect(sim.flow, ZenFlow.rewinding);
      expect(sim.remaining, closeTo(70, 0.001)); // +5*4
      sim.step(30.0, gx: 0, gy: -1, gz: 0);
      expect(sim.remaining, 100); // capped
    });

    test('on its side: pauses', () {
      final sim = ZenSandSim(totalSeconds: 100);
      sim.step(5.0, gx: 0.9, gy: 0.1, gz: 0.1);
      expect(sim.orientation, ZenOrientation.side);
      expect(sim.flow, ZenFlow.paused);
      expect(sim.remaining, 100);
    });

    test('manual pause overrides orientation', () {
      final sim = ZenSandSim(totalSeconds: 100)..manuallyPaused = true;
      sim.step(5.0, gx: 0, gy: 1, gz: 0);
      expect(sim.flow, ZenFlow.paused);
      expect(sim.remaining, 100);
    });

    test('completion fires exactly once and latches done', () {
      final sim = ZenSandSim(totalSeconds: 3);
      sim.step(2.0, gx: 0, gy: 1, gz: 0);
      expect(sim.consumeCompletion(), isFalse);
      sim.step(2.0, gx: 0, gy: 1, gz: 0);
      expect(sim.flow, ZenFlow.done);
      expect(sim.consumeCompletion(), isTrue);
      expect(sim.consumeCompletion(), isFalse); // only once
      sim.step(1.0, gx: 0, gy: 1, gz: 0);
      expect(sim.remaining, 0);
      expect(sim.flow, ZenFlow.done);
    });

    test('flipping after done rewinds back into a live session', () {
      final sim = ZenSandSim(totalSeconds: 10);
      sim.step(11.0, gx: 0, gy: 1, gz: 0);
      expect(sim.flow, ZenFlow.done);
      sim.consumeCompletion();
      sim.step(1.0, gx: 0, gy: -1, gz: 0); // flip the phone
      expect(sim.flow, ZenFlow.rewinding);
      expect(sim.remaining, greaterThan(0));
      sim.step(1.0, gx: 0, gy: 1, gz: 0); // back upright
      expect(sim.flow, ZenFlow.running);
    });

    test('addSeconds revives a done session and caps at total', () {
      final sim = ZenSandSim(totalSeconds: 60);
      sim.step(61, gx: 0, gy: 1, gz: 0);
      expect(sim.flow, ZenFlow.done);
      sim.addSeconds(300);
      expect(sim.remaining, 60); // capped
      expect(sim.flow, ZenFlow.running);
    });
  });

  group('orientation classification', () {
    test('ambiguous angles keep the previous stable reading', () {
      expect(
        ZenSandSim.classify(0.3, 0.4, 0.3, ZenOrientation.upright),
        ZenOrientation.upright,
      );
      expect(
        ZenSandSim.classify(0.3, 0.4, 0.3, ZenOrientation.side),
        ZenOrientation.side,
      );
    });

    test('clear dominance switches state', () {
      expect(
        ZenSandSim.classify(0, 0.9, 0, ZenOrientation.side),
        ZenOrientation.upright,
      );
      expect(
        ZenSandSim.classify(0, -0.9, 0, ZenOrientation.upright),
        ZenOrientation.inverted,
      );
      expect(
        ZenSandSim.classify(0.9, 0, 0, ZenOrientation.upright),
        ZenOrientation.side,
      );
      expect(
        ZenSandSim.classify(0, 0.1, 0.95, ZenOrientation.upright),
        ZenOrientation.flat,
      );
    });
  });

  group('sand geometry', () {
    test('fill heights track the remaining fraction', () {
      final sim = ZenSandSim(totalSeconds: 100);
      expect(sim.topFillHeight, closeTo(0.5, 0.001)); // full
      expect(sim.bottomFillHeight, 0);
      sim.remaining = 0;
      expect(sim.topFillHeight, 0);
      expect(sim.bottomFillHeight, closeTo(0.5, 0.001));
    });

    test('grains spawn while running and land in the bottom bulb', () {
      final sim = ZenSandSim(totalSeconds: 600);
      for (var i = 0; i < 60; i++) {
        sim.step(1 / 60, gx: 0, gy: 1, gz: 0);
      }
      expect(sim.grains, isNotEmpty);
      expect(sim.grains.length, lessThanOrEqualTo(80));
      // All grains stay inside the glass.
      for (final g in sim.grains) {
        expect(g.x.abs(), lessThanOrEqualTo(ZenSandSim.halfWidthAt(g.y)));
        expect(g.y.abs(), lessThanOrEqualTo(0.5));
      }
    });
  });
}

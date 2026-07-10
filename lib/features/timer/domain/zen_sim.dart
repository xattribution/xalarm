import 'dart:math';

/// How the phone is being held, derived from the accelerometer.
enum ZenOrientation { upright, inverted, side, flat }

/// What the sand (and the clock) is doing right now.
enum ZenFlow { running, paused, rewinding, done }

/// One grain of sand in normalized hourglass coordinates
/// (y ∈ [-0.5, 0.5], neck at y = 0, bottom bulb is positive y).
class Grain {
  double x, y, vx, vy;
  final double size; // 1..2.5 (painter scales)
  final double alpha; // 0.5..1
  final bool rising; // true while rewinding (flows bottom → top)
  Grain({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.alpha,
    required this.rising,
  });
}

/// A slow-drifting dust speck inside the glass (pure ambience).
class Dust {
  double x, y, phase;
  Dust(this.x, this.y, this.phase);
}

/// The zen hourglass: time state + a lightweight sand simulation.
///
/// Pure Dart (no Flutter imports) so the flow logic is unit-testable.
/// The painter samples [halfWidthAt], [topSurfaceY], [bottomSurfaceY] and
/// draws [grains] each frame.
class ZenSandSim {
  ZenSandSim({
    required this.totalSeconds,
    double? remainingSeconds,
    int seed = 7,
  }) : remaining = remainingSeconds ?? totalSeconds,
       _rng = Random(seed) {
    for (var i = 0; i < 5; i++) {
      dust.add(
        Dust(
          (_rng.nextDouble() - 0.5) * 0.3,
          (_rng.nextDouble() - 0.5) * 0.8,
          _rng.nextDouble() * pi * 2,
        ),
      );
    }
  }

  final double totalSeconds;
  double remaining;
  bool manuallyPaused = false;

  ZenOrientation orientation = ZenOrientation.upright;
  ZenFlow flow = ZenFlow.running;

  final List<Grain> grains = [];
  final List<Dust> dust = [];
  final Random _rng;

  bool _justCompleted = false;

  /// Rewind speed multiplier while the phone is held upside down.
  static const double rewindRate = 4.0;

  /// Geometry: glass half-width at height y (normalized units). Narrow at
  /// the neck (y=0), flaring toward the end caps (|y|=0.5).
  static const double neckHalfWidth = 0.014;
  static const double maxHalfWidth = 0.30;

  static double halfWidthAt(double y) {
    final t = (y.abs() / 0.5).clamp(0.0, 1.0);
    return neckHalfWidth + (maxHalfWidth - neckHalfWidth) * pow(t, 1.6);
  }

  double get fraction =>
      totalSeconds <= 0 ? 0 : (remaining / totalSeconds).clamp(0.0, 1.0);

  /// Height of the sand column resting above the neck (top bulb).
  double get topFillHeight => 0.5 * pow(fraction, 0.55).toDouble();

  /// Height of the pile accumulated in the bottom bulb.
  double get bottomFillHeight => 0.5 * pow(1 - fraction, 0.55).toDouble();

  /// Surface line of the top sand (y coordinate; more negative = higher).
  double get topSurfaceY => -topFillHeight;

  /// Surface of the bottom mound at horizontal position [x] (cone shape,
  /// peaked in the center).
  double bottomSurfaceY(double x) {
    final h = bottomFillHeight;
    if (h <= 0.001) return 0.5;
    final w = halfWidthAt(0.5 - h * 0.5) + 0.02;
    final t = (x.abs() / w).clamp(0.0, 1.0);
    return 0.5 - h * (1.0 - 0.45 * t);
  }

  /// Classify device orientation from a normalized gravity vector in screen
  /// space: gy +1 = screen-bottom down (upright), gy -1 = inverted,
  /// |gx| dominant = resting on its side, |gz| dominant = flat on a table.
  /// Mild hysteresis: an axis must clearly dominate to switch.
  static ZenOrientation classify(
    double gx,
    double gy,
    double gz,
    ZenOrientation current,
  ) {
    if (gy > 0.55) return ZenOrientation.upright;
    if (gy < -0.55) return ZenOrientation.inverted;
    if (gx.abs() > 0.62) return ZenOrientation.side;
    if (gz.abs() > 0.72) return ZenOrientation.flat;
    return current; // in-between angles: keep the last stable reading
  }

  /// Advance the simulation. [gx], [gy], [gz] are the filtered gravity
  /// direction in screen space (roughly unit length).
  void step(double dt, {double gx = 0, double gy = 1, double gz = 0}) {
    orientation = classify(gx, gy, gz, orientation);

    // Time flow.
    if (remaining <= 0 && orientation != ZenOrientation.inverted) {
      flow = ZenFlow.done;
    } else if (manuallyPaused) {
      flow = ZenFlow.paused;
    } else {
      switch (orientation) {
        case ZenOrientation.upright:
        case ZenOrientation.flat: // deliberate cheat: desk = keep focusing
          flow = ZenFlow.running;
        case ZenOrientation.inverted:
          flow = ZenFlow.rewinding;
        case ZenOrientation.side:
          flow = ZenFlow.paused;
      }
    }

    if (flow == ZenFlow.running) {
      remaining -= dt;
      if (remaining <= 0) {
        remaining = 0;
        flow = ZenFlow.done;
        _justCompleted = true;
      }
    } else if (flow == ZenFlow.rewinding) {
      remaining = min(totalSeconds, remaining + dt * rewindRate);
    }

    _stepGrains(dt, gx);
    _stepDust(dt);
  }

  /// True exactly once per completion (latched).
  bool consumeCompletion() {
    if (_justCompleted) {
      _justCompleted = false;
      return true;
    }
    return false;
  }

  /// "+5 minutes" style extension; revives a done session.
  void addSeconds(double seconds) {
    remaining = min(totalSeconds, remaining + seconds);
    if (remaining > 0 && flow == ZenFlow.done) {
      flow = manuallyPaused ? ZenFlow.paused : ZenFlow.running;
    }
  }

  // --- particles ---

  void _stepGrains(double dt, double lean) {
    final flowing = flow == ZenFlow.running;
    final rewinding = flow == ZenFlow.rewinding;

    // Spawn stream grains at the neck.
    if ((flowing || rewinding) && grains.length < 80) {
      final n = 2 + _rng.nextInt(2);
      for (var i = 0; i < n; i++) {
        final dir = rewinding ? -1.0 : 1.0;
        grains.add(
          Grain(
            x: (_rng.nextDouble() - 0.5) * 0.016,
            y: 0.012 * dir,
            vx: lean * 0.06 + (_rng.nextDouble() - 0.5) * 0.03,
            vy: 0.18 * dir,
            size: 1.2 + _rng.nextDouble() * 1.3,
            alpha: 0.55 + _rng.nextDouble() * 0.45,
            rising: rewinding,
          ),
        );
      }
    }

    // Integrate + cull.
    grains.removeWhere((g) {
      // Freeze mid-air grains when paused: sand hangs still for a beat —
      // reads as "held" — then settles quickly.
      final speed = (flowing || rewinding) ? 1.0 : 2.5;
      g.vy += (g.rising ? -2.4 : 2.4) * dt * speed;
      g.vx += lean * 1.1 * dt;
      g.x += g.vx * dt;
      g.y += g.vy * dt;

      // Keep grains inside the glass.
      final w = halfWidthAt(g.y) * 0.94;
      if (g.x.abs() > w) {
        g.x = g.x.clamp(-w, w);
        g.vx *= -0.25;
      }

      if (g.rising) {
        return g.y <= topSurfaceY + 0.01 || g.y < -0.5;
      }
      return g.y >= bottomSurfaceY(g.x) - 0.004 || g.y > 0.5;
    });
  }

  void _stepDust(double dt) {
    for (final d in dust) {
      d.phase += dt * 0.4;
      d.x += sin(d.phase) * 0.006 * dt * 60;
      d.y += cos(d.phase * 0.7) * 0.004 * dt * 60;
      final w = halfWidthAt(d.y) * 0.8;
      d.x = d.x.clamp(-w, w);
      d.y = d.y.clamp(-0.46, 0.46);
    }
  }
}

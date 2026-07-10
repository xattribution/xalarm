import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../services/system_sounds.dart';
import 'domain/zen_sim.dart';
import 'widgets/hourglass_painter.dart';

/// Zen focus mode: an hourglass of flowing sand controlled by how you hold
/// the phone. Upright it counts down; flip it upside down to flow the sand
/// back (add time); rest it on its side to pause; tap the glass to pause
/// manually. Ends with a gentle buzz + chime and a reminder to move —
/// deliberately foreground-only, not an alarm.
class ZenScreen extends ConsumerStatefulWidget {
  const ZenScreen({super.key});

  @override
  ConsumerState<ZenScreen> createState() => _ZenScreenState();
}

class _ZenScreenState extends ConsumerState<ZenScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _presets = [15, 25, 45, 60];

  int _minutes = 25;
  ZenSandSim? _sim;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  // Filtered gravity in screen space (gy +1 = screen-bottom down).
  double _gx = 0, _gy = 1, _gz = 0;

  bool _showBreak = false;

  bool get _inSession => _sim != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _begin() {
    final sim = ZenSandSim(
      totalSeconds: _minutes * 60.0,
      seed: DateTime.now().millisecondsSinceEpoch & 0xffff,
    );
    setState(() {
      _sim = sim;
      _showBreak = false;
    });

    ref.read(systemSoundsProvider).setKeepScreenOn(true);

    _accelSub = accelerometerEventStream().listen((e) {
      // Low-pass filter; normalize by standard gravity. Screen-space
      // mapping: device +y points up-screen, so upright ⇒ e.y ≈ +9.8 ⇒
      // sand falls toward screen-bottom (+gy). Lean follows -e.x.
      const alpha = 0.14;
      _gx = _gx * (1 - alpha) + (-e.x / 9.81) * alpha;
      _gy = _gy * (1 - alpha) + (e.y / 9.81) * alpha;
      _gz = _gz * (1 - alpha) + (e.z / 9.81) * alpha;
    });

    _lastTick = Duration.zero;
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final sim = _sim;
    if (sim == null) return;
    final dt =
        ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;

    sim.step(dt, gx: _gx, gy: _gy, gz: _gz);

    if (sim.consumeCompletion()) {
      _onComplete();
    }
    if (mounted) setState(() {});
  }

  Future<void> _onComplete() async {
    setState(() => _showBreak = true);
    // Gentle triple buzz + a single quiet chime — no alarm machinery.
    unawaited(
      ref.read(systemSoundsProvider).preview('assets/sounds/chime.wav'),
    );
    for (var i = 0; i < 3; i++) {
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  void _extend(double seconds) {
    _sim?.addSeconds(seconds);
    setState(() => _showBreak = false);
  }

  void _end() {
    _teardown();
    setState(() {
      _sim = null;
      _showBreak = false;
    });
  }

  void _teardown() {
    _ticker?.dispose();
    _ticker = null;
    _accelSub?.cancel();
    _accelSub = null;
    ref.read(systemSoundsProvider).setKeepScreenOn(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mindfulness tool, not an alarm: leaving the app pauses the session.
    if (state != AppLifecycleState.resumed && _sim != null) {
      _sim!.manuallyPaused = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_inSession) _teardown();
    super.dispose();
  }

  static String _fmt(double seconds) {
    final s = seconds.ceil();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: _inSession ? _session(context) : _setup(context),
      ),
    );
  }

  // --- pre-session: pick a duration ---

  Widget _setup(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.close, color: AppColors.darkTextMuted),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const Spacer(),
        const Icon(Icons.self_improvement, size: 56, color: AppColors.tan),
        const SizedBox(height: 16),
        const Text(
          'Zen focus',
          style: TextStyle(
            color: AppColors.darkText,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            'Sand falls while you focus. Flip the phone to give yourself '
            'more time; rest it on its side to pause.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 10,
          children: [
            for (final m in _presets)
              ChoiceChip(
                label: Text('$m min'),
                selected: _minutes == m,
                onSelected: (_) => setState(() => _minutes = m),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _minutes > 5
                  ? () => setState(() => _minutes -= 5)
                  : null,
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppColors.darkTextMuted),
            ),
            SizedBox(
              width: 90,
              child: Text(
                '$_minutes min',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: _minutes < 180
                  ? () => setState(() => _minutes += 5)
                  : null,
              icon: const Icon(Icons.add_circle_outline,
                  color: AppColors.darkTextMuted),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _begin,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            minimumSize: const Size(180, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text('Begin'),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  // --- active session ---

  Widget _session(BuildContext context) {
    final sim = _sim!;
    final status = switch (sim.flow) {
      ZenFlow.running => 'focus',
      ZenFlow.paused => sim.manuallyPaused ? 'paused' : 'resting on its side',
      ZenFlow.rewinding => 'adding time…',
      ZenFlow.done => 'time to move',
    };

    return Stack(
      children: [
        Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon:
                    const Icon(Icons.close, color: AppColors.darkTextMuted),
                onPressed: _end,
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(
                  () => sim.manuallyPaused = !sim.manuallyPaused,
                ),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 0.62,
                    child: CustomPaint(painter: HourglassPainter(sim)),
                  ),
                ),
              ),
            ),
            Text(
              _fmt(sim.remaining),
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 40,
                fontWeight: FontWeight.w200,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
        // Break overlay.
        IgnorePointer(
          ignoring: !_showBreak,
          child: AnimatedOpacity(
            opacity: _showBreak ? 1 : 0,
            duration: const Duration(milliseconds: 600),
            child: Container(
              color: AppColors.darkBg.withValues(alpha: 0.88),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_walk,
                      size: 52, color: AppColors.tan),
                  const SizedBox(height: 18),
                  const Text(
                    'Time to move',
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Stand up, stretch, walk around.',
                    style: TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => _extend(300),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.darkText,
                          side: const BorderSide(
                              color: AppColors.darkDivider),
                          minimumSize: const Size(130, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('+5 minutes'),
                      ),
                      const SizedBox(width: 14),
                      FilledButton(
                        onPressed: _end,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          minimumSize: const Size(130, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

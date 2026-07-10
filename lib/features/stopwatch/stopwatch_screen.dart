import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Stopwatch with laps. State lives in this widget and survives tab switches
/// because the shell keeps tabs alive in an IndexedStack.
class StopwatchScreen extends StatefulWidget {
  const StopwatchScreen({super.key});

  @override
  State<StopwatchScreen> createState() => _StopwatchScreenState();
}

class _StopwatchScreenState extends State<StopwatchScreen> {
  final _watch = Stopwatch();
  Timer? _tick;
  final List<Duration> _laps = [];

  bool get _running => _watch.isRunning;

  void _startTick() {
    _tick ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  void _startPause() {
    setState(() {
      if (_running) {
        _watch.stop();
        _stopTick();
      } else {
        _watch.start();
        _startTick();
      }
    });
  }

  void _lapOrReset() {
    setState(() {
      if (_running) {
        _laps.add(_watch.elapsed);
      } else {
        _watch.reset();
        _laps.clear();
      }
    });
  }

  @override
  void dispose() {
    _stopTick();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s.$cs' : '$m:$s.$cs';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elapsed = _watch.elapsed;
    final hasTime = elapsed > Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(),
          Text(
            _fmt(elapsed),
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w200,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: hasTime || _running ? _lapOrReset : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(_running ? 'Lap' : 'Reset'),
              ),
              const SizedBox(width: 20),
              FilledButton(
                onPressed: _startPause,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 52),
                  backgroundColor:
                      _running ? scheme.secondary : scheme.primary,
                  foregroundColor:
                      _running ? scheme.onSecondary : scheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(_running ? 'Pause' : (hasTime ? 'Resume' : 'Start')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            flex: 2,
            child: _laps.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    itemCount: _laps.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      // newest lap first
                      final idx = _laps.length - 1 - i;
                      final total = _laps[idx];
                      final prev =
                          idx == 0 ? Duration.zero : _laps[idx - 1];
                      final lap = total - prev;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                'Lap ${idx + 1}',
                                style: TextStyle(color: context.mutedColor),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _fmt(lap),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              _fmt(total),
                              style: TextStyle(
                                color: context.mutedColor,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

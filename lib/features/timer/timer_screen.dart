import 'dart:async';

import 'package:alarm/alarm.dart' as pkg;
import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Countdown timer. The end-of-timer ring is scheduled as a one-shot native
/// alarm, so it fires even if the app is backgrounded or the screen is off.
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Duration _selected = const Duration(minutes: 10);
  DateTime? _endsAt; // non-null while running
  Duration _pausedRemaining = Duration.zero;
  bool _paused = false;
  Timer? _tick;

  bool get _running => _endsAt != null;
  bool get _idle => !_running && !_paused;

  Duration get _remaining {
    if (_running) {
      final r = _endsAt!.difference(DateTime.now());
      return r.isNegative ? Duration.zero : r;
    }
    if (_paused) return _pausedRemaining;
    return _selected;
  }

  Future<void> _start() async {
    final duration = _paused ? _pausedRemaining : _selected;
    if (duration.inSeconds < 1) return;
    final endsAt = DateTime.now().add(duration);
    try {
      await pkg.Alarm.set(
        alarmSettings: pkg.AlarmSettings(
          id: kTimerNativeAlarmId,
          dateTime: endsAt,
          assetAudioPath: kDefaultSoundAsset,
          loopAudio: true,
          vibrate: true,
          androidFullScreenIntent: true,
          volumeSettings: const pkg.VolumeSettings.fixed(volume: 0.8),
          notificationSettings: const pkg.NotificationSettings(
            title: 'Timer',
            body: 'Time is up',
            stopButton: 'Stop',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Timer alarm scheduling failed (non-mobile platform?): $e');
    }
    setState(() {
      _endsAt = endsAt;
      _paused = false;
    });
    _tick ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_running && _endsAt!.isBefore(DateTime.now())) {
        // The native alarm is ringing; reset the UI to idle.
        setState(() {
          _endsAt = null;
          _paused = false;
        });
        _stopTick();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _pause() async {
    final remaining = _remaining;
    try {
      await pkg.Alarm.stop(kTimerNativeAlarmId);
    } catch (_) {}
    setState(() {
      _pausedRemaining = remaining;
      _endsAt = null;
      _paused = true;
    });
    _stopTick();
  }

  Future<void> _reset() async {
    try {
      await pkg.Alarm.stop(kTimerNativeAlarmId);
    } catch (_) {}
    setState(() {
      _endsAt = null;
      _paused = false;
    });
    _stopTick();
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stopTick();
    super.dispose();
  }

  void _adjust({int hours = 0, int minutes = 0, int seconds = 0}) {
    setState(() {
      final next = _selected +
          Duration(hours: hours, minutes: minutes, seconds: seconds);
      _selected = next.isNegative || next.inSeconds < 1
          ? const Duration(seconds: 1)
          : (next > const Duration(hours: 99) ? const Duration(hours: 99) : next);
    });
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _idle
        ? 1.0
        : (_selected.inMilliseconds == 0
              ? 0.0
              : _remaining.inMilliseconds / _selected.inMilliseconds);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(),
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 240,
                  height: 240,
                  child: CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: _running ? scheme.primary : scheme.secondary,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  _fmt(_remaining),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w200,
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_idle) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AdjustButton(label: '-1m', onTap: () => _adjust(minutes: -1)),
                _AdjustButton(label: '-10s', onTap: () => _adjust(seconds: -10)),
                _AdjustButton(label: '+10s', onTap: () => _adjust(seconds: 10)),
                _AdjustButton(label: '+1m', onTap: () => _adjust(minutes: 1)),
                _AdjustButton(label: '+1h', onTap: () => _adjust(hours: 1)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final preset in const [
                  Duration(minutes: 1),
                  Duration(minutes: 5),
                  Duration(minutes: 10),
                  Duration(minutes: 20),
                  Duration(minutes: 30),
                  Duration(hours: 1),
                ])
                  ChoiceChip(
                    label: Text(
                      preset.inMinutes < 60
                          ? '${preset.inMinutes}m'
                          : '${preset.inHours}h',
                    ),
                    selected: _selected == preset,
                    onSelected: (_) => setState(() => _selected = preset),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _idle ? null : _reset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Reset'),
              ),
              const SizedBox(width: 20),
              FilledButton(
                onPressed: _running ? _pause : _start,
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
                child: Text(_running ? 'Pause' : (_paused ? 'Resume' : 'Start')),
              ),
            ],
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

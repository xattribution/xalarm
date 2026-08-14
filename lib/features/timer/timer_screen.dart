import 'dart:async';

import 'package:alarm/alarm.dart' as pkg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_protocol/sync_protocol.dart';

import '../../core/constants.dart';
import '../sync/application/sync_controller.dart';
import '../sync/sync_banner.dart';
import 'zen_screen.dart';

/// Countdown timer. The end-of-timer ring is scheduled as a one-shot native
/// alarm, so it fires even if the app is backgrounded or the screen is off.
/// When a Time Sync session is active, start/pause/reset mirror to the
/// partner's device — each phone still schedules its own native alarm, so
/// the ring fires locally even if the connection hiccups at zero.
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  Duration _selected = const Duration(minutes: 10);
  DateTime? _endsAt; // non-null while running
  Duration _pausedRemaining = Duration.zero;
  bool _paused = false;
  Timer? _tick;
  StreamSubscription<PeerAction>? _syncSub;

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

  @override
  void initState() {
    super.initState();
    _syncSub =
        ref.read(syncProvider.notifier).actions.listen(_onRemoteAction);
  }

  void _onRemoteAction(PeerAction pa) {
    final sync = ref.read(syncProvider.notifier);
    switch (pa.action) {
      case TimerSet(:final durationMs):
        if (_idle) {
          setState(() => _selected = Duration(milliseconds: durationMs));
        }
      case TimerStart(:final endsAtServerMs, :final durationMs):
        final endsAt = DateTime.fromMillisecondsSinceEpoch(
          sync.toLocalMs(endsAtServerMs),
        );
        setState(() => _selected = Duration(milliseconds: durationMs));
        _startAt(endsAt);
      case TimerPause(:final remainingMs, :final durationMs):
        _applyPause(
          Duration(milliseconds: remainingMs),
          Duration(milliseconds: durationMs),
        );
      case TimerReset(:final durationMs):
        _applyReset(Duration(milliseconds: durationMs));
      default:
        return; // stopwatch actions belong to the Stopwatch tab
    }
  }

  Future<void> _start() async {
    final duration = _paused ? _pausedRemaining : _selected;
    if (duration.inSeconds < 1) return;
    final endsAt = DateTime.now().add(duration);
    await _startAt(endsAt);

    final sync = ref.read(syncProvider.notifier);
    if (ref.read(syncProvider).isPaired) {
      sync.sendAction(TimerStart(
        endsAtServerMs: sync.clock.toServer(endsAt.millisecondsSinceEpoch),
        durationMs: _selected.inMilliseconds,
      ));
    }
  }

  /// Schedule the native ring + run the countdown toward [endsAt].
  /// Shared by local starts and remote (synced) starts.
  Future<void> _startAt(DateTime endsAt) async {
    if (endsAt.isBefore(DateTime.now())) return;
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
    await _applyPause(remaining, _selected);
    final sync = ref.read(syncProvider.notifier);
    if (ref.read(syncProvider).isPaired) {
      sync.sendAction(TimerPause(
        remainingMs: remaining.inMilliseconds,
        durationMs: _selected.inMilliseconds,
      ));
    }
  }

  Future<void> _applyPause(Duration remaining, Duration total) async {
    try {
      await pkg.Alarm.stop(kTimerNativeAlarmId);
    } catch (_) {}
    setState(() {
      _selected = total;
      _pausedRemaining = remaining;
      _endsAt = null;
      _paused = true;
    });
    _stopTick();
  }

  Future<void> _reset() async {
    await _applyReset(_selected);
    if (ref.read(syncProvider).isPaired) {
      ref.read(syncProvider.notifier).sendAction(
            TimerReset(durationMs: _selected.inMilliseconds),
          );
    }
  }

  Future<void> _applyReset(Duration total) async {
    try {
      await pkg.Alarm.stop(kTimerNativeAlarmId);
    } catch (_) {}
    setState(() {
      _selected = total;
      _endsAt = null;
      _paused = false;
    });
    _stopTick();
  }

  /// Mirror duration tweaks made while idle so both parties see the same
  /// setting before anyone presses start.
  void _publishSet() {
    if (_idle && ref.read(syncProvider).isPaired) {
      ref.read(syncProvider.notifier).sendAction(
            TimerSet(durationMs: _selected.inMilliseconds),
          );
    }
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _syncSub?.cancel();
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
    _publishSet();
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
          const SyncBanner(),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const ZenScreen(),
                  ),
                ),
                icon: const Icon(Icons.self_improvement, size: 20),
                label: const Text('Zen'),
              ),
            ),
          ),
          const Spacer(),
          // Tap the ring to start/pause.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _running ? _pause() : _start(),
            child: SizedBox(
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
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(_remaining),
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w200,
                          color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Icon(
                        _running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                        // 0.5 keeps the hint subordinate to the digits while
                        // clearing the 3:1 non-text contrast floor.
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ],
              ),
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
                    onSelected: (_) {
                      setState(() => _selected = preset);
                      _publishSet();
                    },
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

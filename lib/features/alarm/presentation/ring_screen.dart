import 'dart:async';

import 'package:alarm/alarm.dart' as pkg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/time_format.dart';
import '../application/alarm_providers.dart';
import '../domain/alarm.dart';

/// Full-screen alarm ring UI with Snooze / Stop, shown when an alarm fires.
class RingScreen extends ConsumerStatefulWidget {
  const RingScreen({super.key, required this.nativeId, required this.onClosed});

  final int nativeId;
  final VoidCallback onClosed;

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends ConsumerState<RingScreen> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Alarm? get _alarm {
    final scheduler = ref.read(alarmSchedulerProvider);
    final baseId = scheduler.baseIdForNative(widget.nativeId);
    final alarms = ref.read(alarmListProvider).value ?? const [];
    for (final a in alarms) {
      if (a.id == baseId) return a;
    }
    return null;
  }

  Future<void> _stop() async {
    await pkg.Alarm.stop(widget.nativeId);
    // Top the horizon back up for this alarm.
    final alarm = _alarm;
    if (alarm != null) {
      await ref.read(alarmSchedulerProvider).sync(alarm);
    }
    _close();
  }

  Future<void> _snooze() async {
    final alarm = _alarm;
    await pkg.Alarm.stop(widget.nativeId);
    final minutes = alarm?.snoozeMinutes ?? 9;
    final when = DateTime.now().add(Duration(minutes: minutes));
    try {
      await pkg.Alarm.set(
        alarmSettings: pkg.AlarmSettings(
          id: widget.nativeId,
          dateTime: when,
          assetAudioPath: alarm?.soundAsset ?? 'assets/sounds/alarm.wav',
          loopAudio: true,
          vibrate: alarm?.vibrate ?? true,
          androidFullScreenIntent: true,
          volumeSettings: pkg.VolumeSettings.fixed(volume: alarm?.volume ?? 0.8),
          notificationSettings: pkg.NotificationSettings(
            title: (alarm?.label.isNotEmpty ?? false) ? alarm!.label : 'Alarm',
            body: 'Snoozed',
            stopButton: 'Stop',
          ),
        ),
      );
    } catch (_) {
      // If snooze scheduling fails, still top up the regular horizon.
      if (alarm != null) await ref.read(alarmSchedulerProvider).sync(alarm);
    }
    _close();
  }

  void _close() {
    widget.onClosed();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = _alarm;
    final label = (alarm?.label.isNotEmpty ?? false) ? alarm!.label : 'Alarm';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Icon(Icons.alarm, size: 56, color: AppColors.tan),
                const SizedBox(height: 24),
                Text(
                  TimeFormat.clock(_now),
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 72,
                    fontWeight: FontWeight.w200,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 18,
                  ),
                ),
                const Spacer(flex: 3),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _snooze,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.darkText,
                          side: const BorderSide(color: AppColors.darkDivider),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text('Snooze ${alarm?.snoozeMinutes ?? 9}m'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: _stop,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Stop'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

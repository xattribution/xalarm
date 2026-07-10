import 'dart:async';

import 'package:alarm/alarm.dart' as pkg;
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/time/time_format.dart';
import '../../../services/ringtone_library.dart';
import '../application/alarm_providers.dart';
import '../domain/alarm.dart';

/// Full-screen alarm ring UI. Stop ends the alarm; tapping Snooze uses the
/// alarm's own snooze length, and holding it offers 5 / 10 / 30 / custom
/// minutes. Auto-dismisses if the alarm is stopped from the notification.
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
  StreamSubscription<AlarmSet>? _ringSub;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // If the alarm stops ringing for any reason (notification Stop button,
    // another part of the app), dismiss this screen automatically.
    _ringSub = pkg.Alarm.ringing.listen((set) {
      if (!set.alarms.any((a) => a.id == widget.nativeId)) {
        _close();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ringSub?.cancel();
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
    // Capture everything needed BEFORE closing — the widget is disposed
    // right after, and the horizon top-up runs in the background.
    final scheduler = ref.read(alarmSchedulerProvider);
    final alarm = _alarm;
    await pkg.Alarm.stop(widget.nativeId);
    _close();
    if (alarm != null) {
      unawaited(scheduler.sync(alarm));
    }
  }

  Future<void> _snooze(int minutes) async {
    final alarm = _alarm;
    final when = DateTime.now().add(Duration(minutes: minutes));
    final sound = alarm?.soundAsset ?? kDefaultSoundAsset;
    await pkg.Alarm.stop(widget.nativeId);
    try {
      await pkg.Alarm.set(
        alarmSettings: pkg.AlarmSettings(
          id: widget.nativeId,
          dateTime: when,
          assetAudioPath: sound == kSystemDefaultSound ? null : sound,
          loopAudio: true,
          vibrate: alarm?.vibrate ?? true,
          androidFullScreenIntent: true,
          volumeSettings: pkg.VolumeSettings.fixed(volume: alarm?.volume ?? 0.8),
          notificationSettings: pkg.NotificationSettings(
            title: (alarm?.label.isNotEmpty ?? false)
                ? alarm!.label
                : (widget.nativeId == kTimerNativeAlarmId ? 'Timer' : 'Alarm'),
            body: 'Snoozed until ${TimeFormat.clock(when)}',
            stopButton: 'Stop',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Snooze scheduling failed: $e');
    }
    _close();
  }

  Future<void> _snoozeOptions() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Snooze for…',
                style: TextStyle(
                  color: AppColors.darkText,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final m in const [5, 10, 30])
              ListTile(
                leading: const Icon(Icons.snooze, color: AppColors.tan),
                title: Text(
                  '$m minutes',
                  style: const TextStyle(color: AppColors.darkText),
                ),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.tan),
              title: const Text(
                'Custom…',
                style: TextStyle(color: AppColors.darkText),
              ),
              onTap: () async {
                final custom = await _askCustomMinutes(ctx);
                if (ctx.mounted) Navigator.of(ctx).pop(custom);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (minutes != null && minutes > 0) {
      await _snooze(minutes);
    }
  }

  Future<int?> _askCustomMinutes(BuildContext ctx) async {
    final controller = TextEditingController();
    return showDialog<int>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Snooze minutes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 15'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dctx).pop(int.tryParse(controller.text)),
            child: const Text('Snooze'),
          ),
        ],
      ),
    );
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClosed();
    if (mounted) {
      // Navigator.pop (not maybePop): PopScope(canPop: false) exists to block
      // the user's back gesture, but it must never block our own dismissal.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarm = _alarm;
    final isTimer = widget.nativeId == kTimerNativeAlarmId;
    final label = isTimer
        ? 'Timer'
        : ((alarm?.label.isNotEmpty ?? false) ? alarm!.label : 'Alarm');
    final snoozeMinutes = alarm?.snoozeMinutes ?? 5;

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
                        onPressed: () => _snooze(snoozeMinutes),
                        onLongPress: _snoozeOptions,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.darkText,
                          side: const BorderSide(color: AppColors.darkDivider),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text('Snooze ${snoozeMinutes}m'),
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
                const SizedBox(height: 6),
                const Text(
                  'Hold Snooze for more options',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

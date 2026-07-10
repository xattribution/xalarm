import 'package:alarm/alarm.dart' as pkg;
import 'package:flutter/foundation.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../features/alarm/domain/alarm.dart';

/// Bridges the pure recurrence engine to the OS alarm layer.
///
/// The OS can only schedule concrete instants, so for each [Alarm] we
/// materialise the next [horizon] occurrences and register one native alarm
/// per occurrence. When an alarm rings we top the horizon back up.
class AlarmScheduler {
  AlarmScheduler({this.horizon = 16});

  /// How many upcoming occurrences to keep scheduled per alarm at any time.
  final int horizon;

  /// Native alarm id = [Alarm.id] * [_slots] + occurrenceIndex.
  /// Keep [_slots] >= horizon so ids never collide across alarms.
  static const int _slots = 64;

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    await pkg.Alarm.init();
    _initialised = true;
  }

  int _baseIdOf(int nativeId) => nativeId ~/ _slots;
  int _nativeId(int alarmId, int index) => alarmId * _slots + index;

  /// Cancel any native alarms belonging to [alarmId].
  Future<void> cancel(int alarmId) async {
    for (var i = 0; i < _slots; i++) {
      await pkg.Alarm.stop(_nativeId(alarmId, i));
    }
  }

  /// Cancel and re-schedule a single alarm's horizon from [now].
  Future<void> sync(Alarm alarm, {DateTime? now}) async {
    await cancel(alarm.id);
    if (!alarm.enabled) return;

    final from = now ?? DateTime.now();
    final upcoming = occurrences(
      alarm.rule,
      alarm.bounds,
      from: from,
      limit: horizon,
    ).toList();

    for (var i = 0; i < upcoming.length; i++) {
      final settings = _settingsFor(alarm, upcoming[i], _nativeId(alarm.id, i));
      try {
        await pkg.Alarm.set(alarmSettings: settings);
      } catch (e) {
        debugPrint('Failed to schedule alarm ${alarm.id} #$i: $e');
      }
    }
  }

  /// Re-schedule every alarm. Called on launch (and after boot, since the OS
  /// relaunches and the [alarm] package restores persisted alarms).
  Future<void> syncAll(List<Alarm> alarms, {DateTime? now}) async {
    for (final alarm in alarms) {
      await sync(alarm, now: now);
    }
  }

  /// Given a native id that just rang, return the owning [Alarm.id] so the
  /// caller can top up that alarm's horizon.
  int baseIdForNative(int nativeId) => _baseIdOf(nativeId);

  pkg.AlarmSettings _settingsFor(Alarm alarm, DateTime when, int nativeId) {
    return pkg.AlarmSettings(
      id: nativeId,
      dateTime: when,
      assetAudioPath: alarm.soundAsset,
      loopAudio: true,
      vibrate: alarm.vibrate,
      androidFullScreenIntent: true,
      volumeSettings: pkg.VolumeSettings.fade(
        volume: alarm.volume,
        fadeDuration: const Duration(seconds: 3),
      ),
      notificationSettings: pkg.NotificationSettings(
        title: alarm.label.isEmpty ? 'Alarm' : alarm.label,
        body: 'Tap to open',
        stopButton: 'Stop',
      ),
    );
  }
}

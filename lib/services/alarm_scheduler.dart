import 'dart:io';

import 'package:alarm/alarm.dart' as pkg;
import 'package:flutter/foundation.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

import '../core/constants.dart';
import '../features/alarm/domain/alarm.dart';
import 'ringtone_library.dart';

/// Bridges the pure recurrence engine to the OS alarm layer.
///
/// The OS can only schedule concrete instants, so for each [Alarm] we
/// materialise the next [horizon] occurrences and register one native alarm
/// per occurrence. When an alarm rings we top the horizon back up.
///
/// Native id layout:
///   alarmId * 64 + slot        upcoming occurrences of an alarm
///   kSnoozeIdBase + alarmId    that alarm's active snooze (survives re-sync)
///   kTimerNativeAlarmId (+1)   the Timer tab's ring (and its snooze)
class AlarmScheduler {
  AlarmScheduler({this.horizon = 16, RingtoneLibrary? library})
    : _library = library ?? RingtoneLibrary();

  /// How many upcoming occurrences to keep scheduled per alarm at any time.
  final int horizon;
  final RingtoneLibrary _library;

  /// Native alarm id = [Alarm.id] * [_slots] + occurrenceIndex.
  /// Keep [_slots] >= horizon so ids never collide across alarms.
  static const int _slots = 64;

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    await pkg.Alarm.init();
    _initialised = true;
  }

  int _nativeId(int alarmId, int index) => alarmId * _slots + index;
  static int snoozeIdFor(int alarmId) => kSnoozeIdBase + alarmId;

  /// The [Alarm.id] a native id belongs to (occurrence slot or snooze), or
  /// null for the Timer tab's ids.
  int? alarmIdForNative(int nativeId) {
    if (nativeId == kTimerNativeAlarmId || nativeId == kTimerSnoozeNativeId) {
      return null;
    }
    if (nativeId >= kSnoozeIdBase) return nativeId - kSnoozeIdBase;
    return nativeId ~/ _slots;
  }

  static bool isTimerNative(int nativeId) =>
      nativeId == kTimerNativeAlarmId || nativeId == kTimerSnoozeNativeId;

  /// Cancel the occurrence slots of [alarmId] (and, when [includeSnooze],
  /// its active snooze). Queries the scheduled set and stops only real ids.
  Future<void> cancel(int alarmId, {bool includeSnooze = false}) async {
    final lo = alarmId * _slots;
    final hi = lo + _slots;
    final snooze = snoozeIdFor(alarmId);
    try {
      final scheduled = await pkg.Alarm.getAlarms();
      for (final s in scheduled) {
        final inRange = s.id >= lo && s.id < hi;
        if (inRange || (includeSnooze && s.id == snooze)) {
          await pkg.Alarm.stop(s.id);
        }
      }
    } catch (_) {
      // Fallback: brute-force the slot range.
      for (var i = 0; i < _slots; i++) {
        await pkg.Alarm.stop(_nativeId(alarmId, i));
      }
      if (includeSnooze) await pkg.Alarm.stop(snooze);
    }
  }

  /// Cancel and re-schedule a single alarm's horizon from [now]. A disabled
  /// alarm has everything (snooze included) cancelled. Returns how many
  /// occurrences were scheduled.
  Future<int> sync(Alarm alarm, {DateTime? now}) async {
    if (!alarm.enabled || alarm.validate() != null) {
      await cancel(alarm.id, includeSnooze: true);
      return 0;
    }
    await cancel(alarm.id);

    final from = now ?? DateTime.now();
    final upcoming = occurrences(
      alarm.rule,
      alarm.bounds,
      from: from,
      limit: horizon,
    ).toList();

    final sound = await resolveSound(alarm.soundAsset);
    var scheduled = 0;
    for (var i = 0; i < upcoming.length; i++) {
      final settings = _settingsFor(
        alarm,
        upcoming[i],
        _nativeId(alarm.id, i),
        sound,
      );
      try {
        await pkg.Alarm.set(alarmSettings: settings);
        scheduled++;
      } catch (e) {
        debugPrint('Failed to schedule alarm ${alarm.id} #$i: $e');
      }
    }
    return scheduled;
  }

  /// Re-schedule every alarm. Called on launch (and after boot, since the OS
  /// relaunches and the [alarm] package restores persisted alarms).
  Future<void> syncAll(List<Alarm> alarms, {DateTime? now}) async {
    for (final alarm in alarms) {
      await sync(alarm, now: now);
    }
  }

  /// Ring again in [minutes]. [alarm] is null for the Timer tab.
  Future<void> snooze({
    required Alarm? alarm,
    required int minutes,
    required int ringingNativeId,
  }) async {
    final when = DateTime.now().add(Duration(minutes: minutes));
    final id = alarm == null ? kTimerSnoozeNativeId : snoozeIdFor(alarm.id);
    final sound = await resolveSound(alarm?.soundAsset ?? kDefaultSoundAsset);
    await pkg.Alarm.stop(ringingNativeId);
    await pkg.Alarm.set(
      alarmSettings: pkg.AlarmSettings(
        id: id,
        dateTime: when,
        assetAudioPath: sound,
        loopAudio: true,
        vibrate: alarm?.vibrate ?? true,
        androidFullScreenIntent: true,
        volumeSettings: pkg.VolumeSettings.fixed(volume: alarm?.volume ?? 0.8),
        notificationSettings: pkg.NotificationSettings(
          title: (alarm?.label.isNotEmpty ?? false)
              ? alarm!.label
              : (alarm == null ? 'Timer' : 'Alarm'),
          body: 'Snoozed for $minutes min',
          stopButton: 'Stop',
        ),
      ),
    );
  }

  /// Turns a stored sound value into what the alarm plugin should play:
  /// null for the device default, otherwise an asset or file path that is
  /// known to exist. Anything missing or unrecognised falls back to the
  /// bundled default so an alarm never rings silently.
  Future<String?> resolveSound(String value) async {
    if (value == kSystemDefaultSound) return null;
    if (RingtoneLibrary.isBuiltInAsset(value)) return value;
    if (await _library.isLibraryFile(value) && await File(value).exists()) {
      return value;
    }
    debugPrint('Sound "$value" unavailable — using the default tone');
    return kDefaultSoundAsset;
  }

  pkg.AlarmSettings _settingsFor(
    Alarm alarm,
    DateTime when,
    int nativeId,
    String? sound,
  ) {
    return pkg.AlarmSettings(
      id: nativeId,
      dateTime: when,
      // null plays the device's default alarm sound.
      assetAudioPath: sound,
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

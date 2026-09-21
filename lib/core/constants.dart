/// Native alarm id reserved for the countdown Timer tab. Kept far above the
/// alarm scheduler's derived id space (alarmId * 64 + slot) so it can never
/// collide with a real alarm's occurrence ids.
const int kTimerNativeAlarmId = 2000000000;

/// Native id used when the Timer's ring is snoozed.
const int kTimerSnoozeNativeId = kTimerNativeAlarmId + 1;

/// Snoozed alarms get their own native id (`kSnoozeIdBase + alarmId`) so a
/// horizon re-sync (which cancels and rebuilds an alarm's occurrence slots)
/// never silently drops an active snooze. Fits in a signed 32-bit int.
const int kSnoozeIdBase = 2100000000;

/// Default ringtone asset bundled with the app.
const String kDefaultSoundAsset = 'assets/sounds/alarm.wav';

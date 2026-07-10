/// Native alarm id reserved for the countdown Timer tab. Kept far above the
/// alarm scheduler's derived id space (alarmId * 64 + slot) so it can never
/// collide with a real alarm's occurrence ids.
const int kTimerNativeAlarmId = 2000000000;

/// Default ringtone asset bundled with the app.
const String kDefaultSoundAsset = 'assets/sounds/alarm.wav';

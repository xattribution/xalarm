import 'package:intl/intl.dart';
import 'package:recurrence_engine/recurrence_engine.dart';

/// Formatting helpers for clock/alarm displays.
class TimeFormat {
  const TimeFormat._();

  /// "7:05 AM" (12-hour). Swap to `Hm` for 24-hour if a setting is added.
  static String clock(DateTime dt) => DateFormat('h:mm a').format(dt);

  static String clockFromLocal(LocalTime t) {
    final dt = DateTime(2000, 1, 1, t.hour, t.minute);
    return DateFormat('h:mm a').format(dt);
  }

  /// A friendly description of when an alarm next fires, relative to now:
  /// "Tomorrow · 6:00 AM", "Mon · 6:00 AM", "Jul 20 · 8:00 AM".
  static String nextFire(DateTime next, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final day = DateTime(next.year, next.month, next.day);
    final diff = day.difference(today).inDays;

    final String label;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Tomorrow';
    } else if (diff > 1 && diff < 7) {
      label = DateFormat('EEE').format(next); // Mon, Tue…
    } else {
      label = DateFormat('MMM d').format(next);
    }
    return '$label · ${clock(next)}';
  }
}

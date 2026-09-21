import 'local_time.dart';

/// How an alarm repeats. A sealed hierarchy so the engine can exhaustively
/// pattern-match and the compiler enforces that every rule type is handled.
///
/// Pure Dart — no Flutter imports — so it is testable with `dart test`.
/// Constructors do not assert ranges; [validate] is the single gate, so that
/// debug and release builds treat bad input identically.
sealed class RecurrenceRule {
  const RecurrenceRule();

  Map<String, dynamic> toJson();

  /// Returns null when the rule is usable, or a human-readable reason it is
  /// not. Constructors only `assert` (stripped from release builds), so every
  /// untrusted source — JSON files, the local API — must call this before a
  /// rule reaches the engine.
  String? validate() {
    switch (this) {
      case OneTime():
        return null;
      case Weekly(:final weekdays):
        if (weekdays.isEmpty) return 'weekly rule needs at least one weekday';
        if (weekdays.any((d) => d < 1 || d > 7)) return 'weekday must be 1-7';
        return null;
      case DailyInterval(:final everyDays, :final times):
        if (everyDays < 1 || everyDays > 366) return 'everyDays must be 1-366';
        return _validTimes(times);
      case HourlyInterval(:final every):
        if (every.inMinutes < 1) return 'interval must be at least 1 minute';
        if (every > const Duration(days: 366)) return 'interval is too long';
        return null;
      case MonthlyOrdinal(:final ordinal, :final weekday, :final time):
        if (ordinal != -1 && (ordinal < 1 || ordinal > 5)) {
          return 'ordinal must be 1-5 or -1';
        }
        if (weekday < 1 || weekday > 7) return 'weekday must be 1-7';
        return time.validate();
      case ShiftCycle(:final pattern, :final times, :final perDayTimes):
        if (pattern.isEmpty || pattern.length > 366) {
          return 'pattern must be 1-366 days';
        }
        if (!pattern.contains(true)) return 'pattern needs a work day';
        final t = _validTimes(times);
        if (t != null) return t;
        for (final e in perDayTimes.entries) {
          if (e.key < 0 || e.key >= pattern.length) {
            return 'override day ${e.key} is outside the cycle';
          }
          final o = _validTimes(e.value, allowEmpty: true);
          if (o != null) return o;
        }
        return null;
    }
  }

  static String? _validTimes(List<LocalTime> times, {bool allowEmpty = false}) {
    if (times.isEmpty && !allowEmpty) return 'at least one time is required';
    if (times.length > 24) return 'too many times per day';
    for (final t in times) {
      final err = t.validate();
      if (err != null) return err;
    }
    return null;
  }

  static RecurrenceRule fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'once':
        return OneTime.fromJson(json);
      case 'weekly':
        return Weekly.fromJson(json);
      case 'dailyInterval':
        return DailyInterval.fromJson(json);
      case 'hourlyInterval':
        return HourlyInterval.fromJson(json);
      case 'monthlyOrdinal':
        return MonthlyOrdinal.fromJson(json);
      case 'shiftCycle':
        return ShiftCycle.fromJson(json);
      default:
        throw ArgumentError('Unknown RecurrenceRule type: ${json['type']}');
    }
  }
}

/// Fires exactly once, at [dateTime]. Standard non-repeating alarm.
class OneTime extends RecurrenceRule {
  final DateTime dateTime;
  const OneTime(this.dateTime);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'once',
    'dateTime': dateTime.toIso8601String(),
  };

  factory OneTime.fromJson(Map<String, dynamic> json) =>
      OneTime(DateTime.parse(json['dateTime'] as String));
}

/// Standard clock-app repeat: fires on the selected [weekdays] at [time].
class Weekly extends RecurrenceRule {
  final Set<int> weekdays; // DateTime.weekday values, 1..7
  final LocalTime time;
  const Weekly({required this.weekdays, required this.time});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'weekly',
    'weekdays': weekdays.toList()..sort(),
    'time': time.toJson(),
  };

  factory Weekly.fromJson(Map<String, dynamic> json) => Weekly(
    weekdays: (json['weekdays'] as List).map((e) => e as int).toSet(),
    time: LocalTime.fromJson(Map<String, dynamic>.from(json['time'] as Map)),
  );
}

/// Every [everyDays] days measured from [anchorDate], at each of [times].
/// e.g. "every 2 days starting Jan 1, at 07:00".
class DailyInterval extends RecurrenceRule {
  final int everyDays; // >= 1
  final DateTime anchorDate; // day-0 of the cadence (time part ignored)
  final List<LocalTime> times;
  const DailyInterval({
    required this.everyDays,
    required this.anchorDate,
    required this.times,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'dailyInterval',
    'everyDays': everyDays,
    'anchorDate': anchorDate.toIso8601String(),
    'times': times.map((t) => t.toJson()).toList(),
  };

  factory DailyInterval.fromJson(Map<String, dynamic> json) => DailyInterval(
    everyDays: json['everyDays'] as int,
    anchorDate: DateTime.parse(json['anchorDate'] as String),
    times: (json['times'] as List)
        .map((e) => LocalTime.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// A true fixed-interval alarm: every [every] duration from [anchor].
/// e.g. "every 12 hours starting Jan 1 06:00".
class HourlyInterval extends RecurrenceRule {
  final Duration every; // > 0
  final DateTime anchor; // first fire instant
  const HourlyInterval({required this.every, required this.anchor});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'hourlyInterval',
    'everyMinutes': every.inMinutes,
    'anchor': anchor.toIso8601String(),
  };

  factory HourlyInterval.fromJson(Map<String, dynamic> json) => HourlyInterval(
    every: Duration(minutes: json['everyMinutes'] as int),
    anchor: DateTime.parse(json['anchor'] as String),
  );
}

/// The nth [weekday] of each month, e.g. "the 3rd Tuesday".
/// [ordinal] is 1..5, or -1 for "the last".
class MonthlyOrdinal extends RecurrenceRule {
  final int ordinal; // 1..5 or -1 (last)
  final int weekday; // 1..7
  final LocalTime time;
  const MonthlyOrdinal({
    required this.ordinal,
    required this.weekday,
    required this.time,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'monthlyOrdinal',
    'ordinal': ordinal,
    'weekday': weekday,
    'time': time.toJson(),
  };

  factory MonthlyOrdinal.fromJson(Map<String, dynamic> json) => MonthlyOrdinal(
    ordinal: json['ordinal'] as int,
    weekday: json['weekday'] as int,
    time: LocalTime.fromJson(Map<String, dynamic>.from(json['time'] as Map)),
  );
}

/// A rotating shift schedule (Panama, 4-on/2-off, DuPont, …).
///
/// [pattern] is the full cycle expressed as one bool per day (true = work day),
/// aligned so that index 0 corresponds to [anchorDate]. On work days the alarm
/// fires at each of [times] (supports 8h vs 12h day/night shift starts).
///
/// [perDayTimes] overrides the default [times] for specific cycle days
/// (key = 0-based day index within the cycle) — e.g. a later start on the
/// first day back, or night-shift starts on the back half of a rotation.
class ShiftCycle extends RecurrenceRule {
  final DateTime anchorDate; // day-0 of the pattern (time part ignored)
  final List<bool> pattern; // length = cycle length in days
  final List<LocalTime> times;
  final Map<int, List<LocalTime>> perDayTimes;
  const ShiftCycle({
    required this.anchorDate,
    required this.pattern,
    required this.times,
    this.perDayTimes = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'shiftCycle',
    'anchorDate': anchorDate.toIso8601String(),
    'pattern': pattern,
    'times': times.map((t) => t.toJson()).toList(),
    if (perDayTimes.isNotEmpty)
      'perDayTimes': perDayTimes.map(
        (day, ts) => MapEntry('$day', ts.map((t) => t.toJson()).toList()),
      ),
  };

  factory ShiftCycle.fromJson(Map<String, dynamic> json) => ShiftCycle(
    anchorDate: DateTime.parse(json['anchorDate'] as String),
    pattern: (json['pattern'] as List).map((e) => e as bool).toList(),
    times: (json['times'] as List)
        .map((e) => LocalTime.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    perDayTimes: json['perDayTimes'] == null
        ? const {}
        : (json['perDayTimes'] as Map).map(
            (day, ts) => MapEntry(
              int.parse(day as String),
              (ts as List)
                  .map(
                    (e) =>
                        LocalTime.fromJson(Map<String, dynamic>.from(e as Map)),
                  )
                  .toList(),
            ),
          ),
  );
}

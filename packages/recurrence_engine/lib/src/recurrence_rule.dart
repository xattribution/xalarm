import 'local_time.dart';

/// How an alarm repeats. A sealed hierarchy so the engine can exhaustively
/// pattern-match and the compiler enforces that every rule type is handled.
///
/// Pure Dart — no Flutter imports — so it is testable with `dart test`.
sealed class RecurrenceRule {
  const RecurrenceRule();

  Map<String, dynamic> toJson();

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
  }) : assert(everyDays >= 1);

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
  }) : assert(ordinal == -1 || (ordinal >= 1 && ordinal <= 5)),
       assert(weekday >= 1 && weekday <= 7);

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
class ShiftCycle extends RecurrenceRule {
  final DateTime anchorDate; // day-0 of the pattern (time part ignored)
  final List<bool> pattern; // length = cycle length in days
  final List<LocalTime> times;
  const ShiftCycle({
    required this.anchorDate,
    required this.pattern,
    required this.times,
  }) : assert(pattern.length > 0);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'shiftCycle',
    'anchorDate': anchorDate.toIso8601String(),
    'pattern': pattern,
    'times': times.map((t) => t.toJson()).toList(),
  };

  factory ShiftCycle.fromJson(Map<String, dynamic> json) => ShiftCycle(
    anchorDate: DateTime.parse(json['anchorDate'] as String),
    pattern: (json['pattern'] as List).map((e) => e as bool).toList(),
    times: (json['times'] as List)
        .map((e) => LocalTime.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

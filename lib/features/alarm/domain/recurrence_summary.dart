import 'package:recurrence_engine/recurrence_engine.dart';

/// Human-readable, one-line descriptions of recurrence rules and bounds,
/// for the alarm list and edit screens.
class RecurrenceSummary {
  const RecurrenceSummary._();

  static const _weekdayShort = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  static const _weekdayLong = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  static const _ordinalWord = {
    1: '1st',
    2: '2nd',
    3: '3rd',
    4: '4th',
    5: '5th',
    -1: 'last',
  };

  static String describe(RecurrenceRule rule, RecurrenceBounds bounds) {
    final base = _describeRule(rule);
    final suffix = _describeBounds(bounds);
    return suffix.isEmpty ? base : '$base · $suffix';
  }

  static String _describeRule(RecurrenceRule rule) {
    switch (rule) {
      case OneTime():
        return 'Once';
      case Weekly(:final weekdays):
        if (weekdays.length == 7) return 'Every day';
        if (_setEquals(weekdays, {1, 2, 3, 4, 5})) return 'Weekdays';
        if (_setEquals(weekdays, {6, 7})) return 'Weekends';
        final sorted = weekdays.toList()..sort();
        return sorted.map((d) => _weekdayShort[d]).join(', ');
      case DailyInterval(:final everyDays):
        return everyDays == 1 ? 'Every day' : 'Every $everyDays days';
      case HourlyInterval(:final every):
        return 'Every ${_formatDuration(every)}';
      case MonthlyOrdinal(:final ordinal, :final weekday):
        return 'Monthly · ${_ordinalWord[ordinal]} ${_weekdayLong[weekday]}';
      case ShiftCycle(:final pattern):
        final on = pattern.where((d) => d).length;
        return 'Shift · $on of ${pattern.length} days';
    }
  }

  static String _describeBounds(RecurrenceBounds bounds) {
    final parts = <String>[];
    final end = bounds.end;
    switch (end) {
      case NeverEnds():
        break;
      case EndsOnDate(:final date):
        parts.add('until ${_shortDate(date)}');
      case EndsAfterCount(:final count):
        parts.add('$count time${count == 1 ? '' : 's'}');
    }
    return parts.join(' · ');
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '$h hour${h == 1 ? '' : 's'}';
    return '$m min';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}

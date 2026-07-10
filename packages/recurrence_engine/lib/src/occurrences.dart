import 'local_time.dart';
import 'recurrence_bounds.dart';
import 'recurrence_rule.dart';

/// Computes the next fire instants for a [RecurrenceRule] under [bounds].
///
/// Returns up to [limit] occurrences at or after [from], in ascending order.
/// Results carry the same UTC-ness as [from] (pass a UTC `from` for
/// deterministic, timezone-independent results — as the unit tests do).
///
/// This is the pure heart of the app: no Flutter, no I/O, fully deterministic.
Iterable<DateTime> occurrences(
  RecurrenceRule rule,
  RecurrenceBounds bounds, {
  required DateTime from,
  required int limit,
}) sync* {
  if (limit <= 0) return;

  final end = bounds.end;
  var emitted = 0;

  switch (end) {
    // "Fire N times then stop" must count from the true series start, so we
    // enumerate from the origin and drop anything past index N.
    case EndsAfterCount(:final count):
      final origin = _seriesOrigin(rule, bounds, from);
      var index = 0;
      for (final occ in _rawAscending(rule, kindRef: from, lowerBound: origin)) {
        if (bounds.startDate != null && occ.isBefore(bounds.startDate!)) {
          continue;
        }
        index++;
        if (index > count) return; // exhausted the allowed count
        if (occ.isBefore(from)) continue; // before the query window
        yield occ;
        if (++emitted >= limit) return;
      }

    case EndsOnDate(:final date):
      final lastInstant = _endOfDay(from, date);
      final lower = _laterOf(bounds.startDate, from);
      for (final occ in _rawAscending(rule, kindRef: from, lowerBound: lower)) {
        if (occ.isAfter(lastInstant)) return;
        if (bounds.startDate != null && occ.isBefore(bounds.startDate!)) {
          continue;
        }
        if (occ.isBefore(from)) continue;
        yield occ;
        if (++emitted >= limit) return;
      }

    case NeverEnds():
      final lower = _laterOf(bounds.startDate, from);
      for (final occ in _rawAscending(rule, kindRef: from, lowerBound: lower)) {
        if (bounds.startDate != null && occ.isBefore(bounds.startDate!)) {
          continue;
        }
        if (occ.isBefore(from)) continue;
        yield occ;
        if (++emitted >= limit) return;
      }
  }
}

/// Convenience: the single next occurrence, or null if the series is exhausted.
DateTime? nextOccurrence(
  RecurrenceRule rule,
  RecurrenceBounds bounds, {
  required DateTime from,
}) {
  final it = occurrences(rule, bounds, from: from, limit: 1).iterator;
  return it.moveNext() ? it.current : null;
}

// ---------------------------------------------------------------------------
// Raw ascending generators (unbounded; the caller applies bounds).
// ---------------------------------------------------------------------------

/// Yields every occurrence of [rule] at or after (roughly) [lowerBound], in
/// ascending order. May yield a few items slightly before [lowerBound]; the
/// caller filters precisely. Never yields out of order.
Iterable<DateTime> _rawAscending(
  RecurrenceRule rule, {
  required DateTime kindRef,
  required DateTime lowerBound,
}) sync* {
  switch (rule) {
    case OneTime(:final dateTime):
      yield _sameKind(kindRef, dateTime);

    case Weekly(:final weekdays, :final time):
      var day = _dayStart(kindRef, lowerBound);
      // Safety: bounded loop so a misconfigured empty weekday set can't spin.
      for (var i = 0; i < 3660; i++) {
        if (weekdays.contains(day.weekday)) {
          yield _at(kindRef, day, time);
        }
        day = _addDays(kindRef, day, 1);
      }

    case DailyInterval(:final everyDays, :final anchorDate, :final times):
      final sorted = _sortedTimes(times);
      final anchorDay = _dayStart(kindRef, anchorDate);
      final lowerDay = _dayStart(kindRef, lowerBound);
      final gap = _daysBetween(anchorDay, lowerDay);
      var k = gap <= 0 ? 0 : (gap + everyDays - 1) ~/ everyDays; // ceil
      for (var i = 0; i < 100000; i++) {
        final day = _addDays(kindRef, anchorDay, k * everyDays);
        for (final t in sorted) {
          yield _at(kindRef, day, t);
        }
        k++;
      }

    case HourlyInterval(:final every, :final anchor):
      final a = _sameKind(kindRef, anchor);
      final diff = lowerBound.difference(a).inMicroseconds;
      final step = every.inMicroseconds;
      var k = diff <= 0 ? 0 : (diff + step - 1) ~/ step; // ceil
      for (var i = 0; i < 1000000; i++) {
        yield a.add(Duration(microseconds: step * k));
        k++;
      }

    case MonthlyOrdinal(:final ordinal, :final weekday, :final time):
      var year = lowerBound.year;
      var month = lowerBound.month;
      for (var i = 0; i < 1200; i++) {
        final day = _ordinalWeekdayOfMonth(kindRef, year, month, ordinal, weekday);
        if (day != null) {
          yield _at(kindRef, day, time);
        }
        month++;
        if (month > 12) {
          month = 1;
          year++;
        }
      }

    case ShiftCycle(:final anchorDate, :final pattern, :final times):
      final sorted = _sortedTimes(times);
      final anchorDay = _dayStart(kindRef, anchorDate);
      var day = _dayStart(kindRef, lowerBound);
      final len = pattern.length;
      for (var i = 0; i < 100000; i++) {
        final idx = _daysBetween(anchorDay, day) % len; // Dart % is non-negative
        if (pattern[idx]) {
          for (final t in sorted) {
            yield _at(kindRef, day, t);
          }
        }
        day = _addDays(kindRef, day, 1);
      }
  }
}

/// The effective start of the series (for count-based end conditions).
DateTime _seriesOrigin(
  RecurrenceRule rule,
  RecurrenceBounds bounds,
  DateTime from,
) {
  final natural = switch (rule) {
    OneTime(:final dateTime) => dateTime,
    DailyInterval(:final anchorDate) => anchorDate,
    HourlyInterval(:final anchor) => anchor,
    ShiftCycle(:final anchorDate) => anchorDate,
    Weekly() => bounds.startDate ?? from,
    MonthlyOrdinal() => bounds.startDate ?? from,
  };
  final n = _sameKind(from, natural);
  if (bounds.startDate != null) {
    final s = _sameKind(from, bounds.startDate!);
    return s.isAfter(n) ? s : n;
  }
  return n;
}

// ---------------------------------------------------------------------------
// Date helpers. All day arithmetic goes through UTC to avoid DST hour drift,
// then rebuilds a DateTime in the reference kind.
// ---------------------------------------------------------------------------

DateTime _sameKind(DateTime ref, DateTime value) {
  if (ref.isUtc == value.isUtc) return value;
  return ref.isUtc
      ? DateTime.utc(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        )
      : DateTime(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        );
}

DateTime _dayStart(DateTime ref, DateTime d) =>
    ref.isUtc ? DateTime.utc(d.year, d.month, d.day) : DateTime(d.year, d.month, d.day);

DateTime _at(DateTime ref, DateTime day, LocalTime t) => ref.isUtc
    ? DateTime.utc(day.year, day.month, day.day, t.hour, t.minute)
    : DateTime(day.year, day.month, day.day, t.hour, t.minute);

DateTime _endOfDay(DateTime ref, DateTime d) => ref.isUtc
    ? DateTime.utc(d.year, d.month, d.day, 23, 59, 59, 999)
    : DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// Whole-day difference in days (b - a), computed in UTC to sidestep DST.
int _daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

DateTime _addDays(DateTime ref, DateTime base, int days) {
  final u = DateTime.utc(base.year, base.month, base.day).add(Duration(days: days));
  return ref.isUtc
      ? DateTime.utc(u.year, u.month, u.day)
      : DateTime(u.year, u.month, u.day);
}

DateTime _laterOf(DateTime? a, DateTime b) {
  if (a == null) return b;
  final an = _sameKind(b, a);
  return an.isAfter(b) ? an : b;
}

List<LocalTime> _sortedTimes(List<LocalTime> times) {
  final copy = List<LocalTime>.of(times.isEmpty ? const [LocalTime(0, 0)] : times);
  copy.sort();
  return copy;
}

/// The date of the [ordinal]-th [weekday] in the given month, or null if it
/// does not exist (e.g. the 5th Friday of a month that has only four).
/// [ordinal] is 1..5, or -1 for "the last".
DateTime? _ordinalWeekdayOfMonth(
  DateTime ref,
  int year,
  int month,
  int ordinal,
  int weekday,
) {
  if (ordinal == -1) {
    final lastDay = DateTime.utc(year, month + 1, 0); // day 0 = last of month
    var d = lastDay;
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return ref.isUtc
        ? DateTime.utc(d.year, d.month, d.day)
        : DateTime(d.year, d.month, d.day);
  }

  final first = DateTime.utc(year, month, 1);
  var offset = (weekday - first.weekday) % 7;
  if (offset < 0) offset += 7;
  final dayNum = 1 + offset + (ordinal - 1) * 7;
  final candidate = DateTime.utc(year, month, dayNum);
  if (candidate.month != month) return null; // overflowed into next month
  return ref.isUtc
      ? DateTime.utc(candidate.year, candidate.month, candidate.day)
      : DateTime(candidate.year, candidate.month, candidate.day);
}

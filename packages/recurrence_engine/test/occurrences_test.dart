import 'package:recurrence_engine/recurrence_engine.dart';
import 'package:test/test.dart';

/// All fixed-date tests run in UTC so results are independent of the machine
/// time zone. Jan 1 2026 is a Thursday — the anchor for most cases below.
DateTime u(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

List<DateTime> take(
  RecurrenceRule rule,
  RecurrenceBounds bounds,
  DateTime from,
  int limit,
) => occurrences(rule, bounds, from: from, limit: limit).toList();

void main() {
  const noBounds = RecurrenceBounds();

  group('OneTime', () {
    test('fires once when in the future', () {
      final rule = OneTime(u(2026, 1, 5, 7, 0));
      expect(take(rule, noBounds, u(2026, 1, 1), 5), [u(2026, 1, 5, 7, 0)]);
    });

    test('is empty once past', () {
      final rule = OneTime(u(2026, 1, 5, 7, 0));
      expect(take(rule, noBounds, u(2026, 1, 6), 5), isEmpty);
    });

    test('includes an occurrence exactly at `from`', () {
      final rule = OneTime(u(2026, 1, 5, 7, 0));
      expect(take(rule, noBounds, u(2026, 1, 5, 7, 0), 5), [
        u(2026, 1, 5, 7, 0),
      ]);
    });
  });

  group('Weekly', () {
    final mwf = Weekly(weekdays: {1, 3, 5}, time: const LocalTime(7, 0));

    test('next Mon/Wed/Fri at 07:00 from a Thursday', () {
      expect(take(mwf, noBounds, u(2026, 1, 1), 4), [
        u(2026, 1, 2, 7, 0), // Fri
        u(2026, 1, 5, 7, 0), // Mon
        u(2026, 1, 7, 7, 0), // Wed
        u(2026, 1, 9, 7, 0), // Fri
      ]);
    });

    test('same-day earlier time is skipped when from is past it', () {
      // from = Friday 08:00, so Friday 07:00 has passed.
      expect(take(mwf, noBounds, u(2026, 1, 2, 8, 0), 1), [u(2026, 1, 5, 7, 0)]);
    });
  });

  group('DailyInterval', () {
    final every3 = DailyInterval(
      everyDays: 3,
      anchorDate: u(2026, 1, 1),
      times: const [LocalTime(9, 0)],
    );

    test('every 3 days at 09:00', () {
      expect(take(every3, noBounds, u(2026, 1, 1), 4), [
        u(2026, 1, 1, 9, 0),
        u(2026, 1, 4, 9, 0),
        u(2026, 1, 7, 9, 0),
        u(2026, 1, 10, 9, 0),
      ]);
    });

    test('skips past anchor occurrences before from', () {
      expect(take(every3, noBounds, u(2026, 1, 2), 2), [
        u(2026, 1, 4, 9, 0),
        u(2026, 1, 7, 9, 0),
      ]);
    });

    test('multiple times per active day, returned sorted', () {
      final twice = DailyInterval(
        everyDays: 2,
        anchorDate: u(2026, 1, 1),
        times: const [LocalTime(18, 0), LocalTime(6, 0)],
      );
      expect(take(twice, noBounds, u(2026, 1, 1), 4), [
        u(2026, 1, 1, 6, 0),
        u(2026, 1, 1, 18, 0),
        u(2026, 1, 3, 6, 0),
        u(2026, 1, 3, 18, 0),
      ]);
    });
  });

  group('HourlyInterval', () {
    final every12 = HourlyInterval(
      every: const Duration(hours: 12),
      anchor: u(2026, 1, 1, 6, 0),
    );

    test('every 12 hours from anchor', () {
      expect(take(every12, noBounds, u(2026, 1, 1), 4), [
        u(2026, 1, 1, 6, 0),
        u(2026, 1, 1, 18, 0),
        u(2026, 1, 2, 6, 0),
        u(2026, 1, 2, 18, 0),
      ]);
    });

    test('fast-forwards to first occurrence at or after from', () {
      expect(take(every12, noBounds, u(2026, 1, 2, 0, 0), 2), [
        u(2026, 1, 2, 6, 0),
        u(2026, 1, 2, 18, 0),
      ]);
    });

    test('every 90 minutes', () {
      final every90 = HourlyInterval(
        every: const Duration(minutes: 90),
        anchor: u(2026, 1, 1, 0, 0),
      );
      expect(take(every90, noBounds, u(2026, 1, 1), 3), [
        u(2026, 1, 1, 0, 0),
        u(2026, 1, 1, 1, 30),
        u(2026, 1, 1, 3, 0),
      ]);
    });
  });

  group('MonthlyOrdinal', () {
    test('3rd Tuesday at 08:00', () {
      final rule = MonthlyOrdinal(
        ordinal: 3,
        weekday: 2,
        time: const LocalTime(8, 0),
      );
      expect(take(rule, noBounds, u(2026, 1, 1), 3), [
        u(2026, 1, 20, 8, 0),
        u(2026, 2, 17, 8, 0),
        u(2026, 3, 17, 8, 0),
      ]);
    });

    test('last Friday of the month', () {
      final rule = MonthlyOrdinal(
        ordinal: -1,
        weekday: 5,
        time: const LocalTime(8, 0),
      );
      expect(take(rule, noBounds, u(2026, 1, 1), 2), [
        u(2026, 1, 30, 8, 0),
        u(2026, 2, 27, 8, 0),
      ]);
    });

    test('5th Monday skips months that have only four', () {
      // Feb 2026 has 4 Mondays; next 5th Monday is Mar 30.
      final rule = MonthlyOrdinal(
        ordinal: 5,
        weekday: 1,
        time: const LocalTime(8, 0),
      );
      expect(take(rule, noBounds, u(2026, 2, 1), 1), [u(2026, 3, 30, 8, 0)]);
    });
  });

  group('ShiftCycle — Panama 2-2-3', () {
    // 14-day cycle: on on off off on on on | off off on on off off off
    final panama = ShiftCycle(
      anchorDate: u(2026, 1, 1),
      pattern: const [
        true, true, false, false, true, true, true, //
        false, false, true, true, false, false, false,
      ],
      times: const [LocalTime(6, 0)],
    );

    test('first work days at 06:00, including cycle wrap', () {
      expect(take(panama, noBounds, u(2026, 1, 1), 9), [
        u(2026, 1, 1, 6, 0),
        u(2026, 1, 2, 6, 0),
        u(2026, 1, 5, 6, 0),
        u(2026, 1, 6, 6, 0),
        u(2026, 1, 7, 6, 0),
        u(2026, 1, 10, 6, 0),
        u(2026, 1, 11, 6, 0),
        u(2026, 1, 15, 6, 0), // cycle wraps back to index 0
        u(2026, 1, 16, 6, 0),
      ]);
    });

    test('resumes correctly mid-cycle', () {
      expect(take(panama, noBounds, u(2026, 1, 8), 2), [
        u(2026, 1, 10, 6, 0),
        u(2026, 1, 11, 6, 0),
      ]);
    });
  });

  group('ShiftCycle — 4-on/2-off/3-on/3-off', () {
    // 12-day cycle
    final rotation = ShiftCycle(
      anchorDate: u(2026, 1, 1),
      pattern: const [
        true, true, true, true, false, false, //
        true, true, true, false, false, false,
      ],
      times: const [LocalTime(5, 30)],
    );

    test('work days across a full cycle and wrap', () {
      expect(take(rotation, noBounds, u(2026, 1, 1), 8), [
        u(2026, 1, 1, 5, 30),
        u(2026, 1, 2, 5, 30),
        u(2026, 1, 3, 5, 30),
        u(2026, 1, 4, 5, 30),
        u(2026, 1, 7, 5, 30),
        u(2026, 1, 8, 5, 30),
        u(2026, 1, 9, 5, 30),
        u(2026, 1, 13, 5, 30), // wrap to index 0
      ]);
    });

    test('day and night shift times on each work day', () {
      final twoShifts = ShiftCycle(
        anchorDate: u(2026, 1, 1),
        pattern: const [true, true, false],
        times: const [LocalTime(6, 0), LocalTime(18, 0)],
      );
      expect(take(twoShifts, noBounds, u(2026, 1, 1), 4), [
        u(2026, 1, 1, 6, 0),
        u(2026, 1, 1, 18, 0),
        u(2026, 1, 2, 6, 0),
        u(2026, 1, 2, 18, 0),
      ]);
    });
  });

  group('Bounds — startDate', () {
    test('nothing fires before the start date', () {
      final mwf = Weekly(weekdays: {1, 3, 5}, time: const LocalTime(7, 0));
      final bounds = RecurrenceBounds(startDate: u(2026, 1, 8));
      // Jan 8 is a Thursday; first M/W/F on or after is Fri Jan 9.
      expect(take(mwf, bounds, u(2026, 1, 1), 3), [
        u(2026, 1, 9, 7, 0),
        u(2026, 1, 12, 7, 0),
        u(2026, 1, 14, 7, 0),
      ]);
    });
  });

  group('Bounds — EndsOnDate', () {
    test('stops after the end date (inclusive)', () {
      final mwf = Weekly(weekdays: {1, 3, 5}, time: const LocalTime(7, 0));
      final bounds = RecurrenceBounds(end: EndsOnDate(u(2026, 1, 9)));
      expect(take(mwf, bounds, u(2026, 1, 1), 10), [
        u(2026, 1, 2, 7, 0),
        u(2026, 1, 5, 7, 0),
        u(2026, 1, 7, 7, 0),
        u(2026, 1, 9, 7, 0), // inclusive; Jan 12 is excluded
      ]);
    });
  });

  group('Bounds — EndsAfterCount ("run a week then stop")', () {
    final daily = DailyInterval(
      everyDays: 1,
      anchorDate: u(2026, 1, 1),
      times: const [LocalTime(7, 0)],
    );
    final oneWeek = RecurrenceBounds(end: const EndsAfterCount(7));

    test('yields exactly 7 occurrences then stops', () {
      final result = take(daily, oneWeek, u(2026, 1, 1), 50);
      expect(result.length, 7);
      expect(result.first, u(2026, 1, 1, 7, 0));
      expect(result.last, u(2026, 1, 7, 7, 0));
    });

    test('count is measured from the series start, not from `from`', () {
      // Querying from mid-series still respects the 7-total cap.
      final result = take(daily, oneWeek, u(2026, 1, 4), 50);
      expect(result, [
        u(2026, 1, 4, 7, 0),
        u(2026, 1, 5, 7, 0),
        u(2026, 1, 6, 7, 0),
        u(2026, 1, 7, 7, 0),
      ]);
    });

    test('count combines with a start date', () {
      // Series effectively begins Jan 3; 3 fires => Jan 3, 4, 5.
      final bounds = RecurrenceBounds(
        startDate: u(2026, 1, 3),
        end: const EndsAfterCount(3),
      );
      expect(take(daily, bounds, u(2026, 1, 1), 50), [
        u(2026, 1, 3, 7, 0),
        u(2026, 1, 4, 7, 0),
        u(2026, 1, 5, 7, 0),
      ]);
    });
  });

  group('limit', () {
    test('limit 0 returns nothing', () {
      final mwf = Weekly(weekdays: {1, 3, 5}, time: const LocalTime(7, 0));
      expect(take(mwf, noBounds, u(2026, 1, 1), 0), isEmpty);
    });

    test('respects the requested limit', () {
      final daily = DailyInterval(
        everyDays: 1,
        anchorDate: u(2026, 1, 1),
        times: const [LocalTime(7, 0)],
      );
      expect(take(daily, noBounds, u(2026, 1, 1), 3).length, 3);
    });
  });

  group('nextOccurrence', () {
    test('returns the first upcoming instant', () {
      final mwf = Weekly(weekdays: {1, 3, 5}, time: const LocalTime(7, 0));
      expect(nextOccurrence(mwf, noBounds, from: u(2026, 1, 1)),
          u(2026, 1, 2, 7, 0));
    });

    test('returns null once a bounded series is exhausted', () {
      final rule = OneTime(u(2026, 1, 5, 7, 0));
      expect(nextOccurrence(rule, noBounds, from: u(2026, 1, 6)), isNull);
    });
  });

  group('DST wall-clock stability', () {
    // Uses LOCAL DateTimes. When the suite runs under a DST zone
    // (e.g. TZ=America/New_York), day arithmetic must not drift the fire
    // time across the spring-forward boundary. 06:00 must stay 06:00.
    test('daily 06:00 stays 06:00 across ~3 weeks including a DST change', () {
      final daily = DailyInterval(
        everyDays: 1,
        anchorDate: DateTime(2026, 3, 1), // local, before US spring-forward
        times: const [LocalTime(6, 0)],
      );
      final result = occurrences(
        daily,
        const RecurrenceBounds(),
        from: DateTime(2026, 3, 1),
        limit: 20,
      ).toList();
      expect(result, hasLength(20));
      // March has 31 days, so the 20 occurrences are Mar 1..Mar 20, each at
      // 06:00 local regardless of the spring-forward transition mid-month.
      for (var i = 0; i < result.length; i++) {
        final occ = result[i];
        expect(occ.hour, 6, reason: '$occ drifted off 06:00');
        expect(occ.minute, 0);
        expect(occ.month, 3);
        expect(occ.day, i + 1, reason: 'expected consecutive calendar days');
      }
    });
  });
}

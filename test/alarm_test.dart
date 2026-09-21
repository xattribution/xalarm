import 'package:flutter_test/flutter_test.dart';
import 'package:recurrence_engine/recurrence_engine.dart';
import 'package:xalarm/features/alarm/domain/alarm.dart';

void main() {
  final weekly = Weekly(weekdays: const {1, 3}, time: const LocalTime(7, 0));

  group('Alarm.validate', () {
    test('accepts a normal alarm', () {
      expect(Alarm(id: 1, label: 'Work', rule: weekly).validate(), isNull);
    });

    test('rejects out-of-range ring options', () {
      expect(
        Alarm(id: 1, label: 'x' * 61, rule: weekly).validate(),
        contains('label'),
      );
      expect(
        Alarm(id: 1, label: '', rule: weekly, snoozeMinutes: 0).validate(),
        contains('snooze'),
      );
      expect(
        Alarm(id: 1, label: '', rule: weekly, volume: 1.5).validate(),
        contains('volume'),
      );
      expect(
        Alarm(id: 1, label: '', rule: weekly, soundAsset: '').validate(),
        contains('soundAsset'),
      );
      expect(
        Alarm(id: 1, label: 'a\nb', rule: weekly).validate(),
        contains('control'),
      );
    });

    test('propagates rule and bounds problems', () {
      final bad = RecurrenceRule.fromJson({
        'type': 'monthlyOrdinal', 'ordinal': -1, 'weekday': 0,
        'time': {'h': 8, 'm': 0},
      });
      expect(Alarm(id: 1, label: '', rule: bad).validate(), contains('weekday'));
      expect(
        Alarm(
          id: 1,
          label: '',
          rule: weekly,
          bounds: RecurrenceBounds.fromJson({
            'startDate': null,
            'end': {'type': 'afterCount', 'count': 0},
          }),
        ).validate(),
        contains('count'),
      );
    });
  });

  group('Alarm.normalized', () {
    test('pins a start date for count-limited weekly/monthly alarms', () {
      final a = Alarm(
        id: 1,
        label: '',
        rule: weekly,
        bounds: const RecurrenceBounds(end: EndsAfterCount(3)),
      ).normalized(now: DateTime(2026, 3, 4, 15, 30));
      expect(a.bounds.startDate, DateTime(2026, 3, 4));
      expect(a.bounds.end, isA<EndsAfterCount>());
    });

    test('leaves everything else alone', () {
      final a = Alarm(id: 1, label: '', rule: weekly);
      expect(identical(a.normalized(), a), isTrue);
      final daily = Alarm(
        id: 2,
        label: '',
        rule: DailyInterval(
          everyDays: 1,
          anchorDate: DateTime(2026, 1, 1),
          times: const [LocalTime(6, 0)],
        ),
        bounds: const RecurrenceBounds(end: EndsAfterCount(7)),
      );
      expect(daily.normalized().bounds.startDate, isNull);
    });
  });

  group('Alarm.nextAcross', () {
    test('picks the soonest enabled alarm', () {
      final now = DateTime(2026, 1, 1, 12); // Thursday
      final a = Alarm(id: 1, label: 'a', rule: OneTime(DateTime(2026, 1, 3)));
      final b = Alarm(id: 2, label: 'b', rule: OneTime(DateTime(2026, 1, 2)));
      final off = Alarm(
        id: 3,
        label: 'off',
        rule: OneTime(DateTime(2026, 1, 1, 13)),
        enabled: false,
      );
      final next = Alarm.nextAcross([a, b, off], from: now);
      expect(next?.alarm.id, 2);
      expect(Alarm.nextAcross([off], from: now), isNull);
    });
  });
}

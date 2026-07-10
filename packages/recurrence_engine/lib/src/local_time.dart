/// A wall-clock time of day, independent of any date or time zone.
///
/// Deliberately Flutter-free so the recurrence engine (and its tests) run
/// under a plain `dart test` with no widget binding.
class LocalTime implements Comparable<LocalTime> {
  final int hour; // 0..23
  final int minute; // 0..59

  const LocalTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  int get minutesOfDay => hour * 60 + minute;

  @override
  int compareTo(LocalTime other) => minutesOfDay - other.minutesOfDay;

  Map<String, dynamic> toJson() => {'h': hour, 'm': minute};

  factory LocalTime.fromJson(Map<String, dynamic> json) =>
      LocalTime(json['h'] as int, json['m'] as int);

  @override
  bool operator ==(Object other) =>
      other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Day of week using Dart's [DateTime.weekday] convention: Mon = 1 … Sun = 7.
enum Weekday {
  monday(1),
  tuesday(2),
  wednesday(3),
  thursday(4),
  friday(5),
  saturday(6),
  sunday(7);

  const Weekday(this.value);
  final int value;

  static Weekday fromValue(int v) =>
      Weekday.values.firstWhere((w) => w.value == v);

  String get shortLabel => switch (this) {
    Weekday.monday => 'Mon',
    Weekday.tuesday => 'Tue',
    Weekday.wednesday => 'Wed',
    Weekday.thursday => 'Thu',
    Weekday.friday => 'Fri',
    Weekday.saturday => 'Sat',
    Weekday.sunday => 'Sun',
  };
}

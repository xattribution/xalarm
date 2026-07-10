import 'package:recurrence_engine/recurrence_engine.dart';

/// A user-facing alarm: a recurrence rule plus its bounds and ring behaviour.
class Alarm {
  /// Stable positive integer id (also used to derive OS alarm ids).
  final int id;
  final String label;
  final RecurrenceRule rule;
  final RecurrenceBounds bounds;
  final bool enabled;
  final int snoozeMinutes;
  final bool vibrate;

  /// Bundled asset path for the ringtone (e.g. `assets/sounds/gentle.mp3`).
  final String soundAsset;
  final double volume; // 0..1

  const Alarm({
    required this.id,
    required this.label,
    required this.rule,
    this.bounds = const RecurrenceBounds(),
    this.enabled = true,
    this.snoozeMinutes = 9,
    this.vibrate = true,
    this.soundAsset = 'assets/sounds/alarm.wav',
    this.volume = 0.8,
  });

  Alarm copyWith({
    String? label,
    RecurrenceRule? rule,
    RecurrenceBounds? bounds,
    bool? enabled,
    int? snoozeMinutes,
    bool? vibrate,
    String? soundAsset,
    double? volume,
  }) => Alarm(
    id: id,
    label: label ?? this.label,
    rule: rule ?? this.rule,
    bounds: bounds ?? this.bounds,
    enabled: enabled ?? this.enabled,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    vibrate: vibrate ?? this.vibrate,
    soundAsset: soundAsset ?? this.soundAsset,
    volume: volume ?? this.volume,
  );

  /// The next time this alarm will ring, or null if its series is exhausted
  /// (or it is disabled).
  DateTime? nextFire({DateTime? from}) {
    if (!enabled) return null;
    return nextOccurrence(rule, bounds, from: from ?? DateTime.now());
  }

  /// A representative time-of-day for showing on the alarm card even when the
  /// alarm is disabled (and so has no next-fire instant).
  LocalTime get primaryTime {
    switch (rule) {
      case OneTime(:final dateTime):
        return LocalTime(dateTime.hour, dateTime.minute);
      case Weekly(:final time):
        return time;
      case DailyInterval(:final times):
        return _first(times);
      case HourlyInterval(:final anchor):
        return LocalTime(anchor.hour, anchor.minute);
      case MonthlyOrdinal(:final time):
        return time;
      case ShiftCycle(:final times):
        return _first(times);
    }
  }

  static LocalTime _first(List<LocalTime> times) {
    if (times.isEmpty) return const LocalTime(0, 0);
    final sorted = List<LocalTime>.of(times)..sort();
    return sorted.first;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'rule': rule.toJson(),
    'bounds': bounds.toJson(),
    'enabled': enabled,
    'snoozeMinutes': snoozeMinutes,
    'vibrate': vibrate,
    'soundAsset': soundAsset,
    'volume': volume,
  };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
    id: json['id'] as int,
    label: json['label'] as String? ?? '',
    rule: RecurrenceRule.fromJson(
      Map<String, dynamic>.from(json['rule'] as Map),
    ),
    bounds: RecurrenceBounds.fromJson(
      Map<String, dynamic>.from(json['bounds'] as Map),
    ),
    enabled: json['enabled'] as bool? ?? true,
    snoozeMinutes: json['snoozeMinutes'] as int? ?? 9,
    vibrate: json['vibrate'] as bool? ?? true,
    soundAsset: json['soundAsset'] as String? ?? 'assets/sounds/alarm.wav',
    volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
  );
}

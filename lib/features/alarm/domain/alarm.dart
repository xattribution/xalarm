import 'package:recurrence_engine/recurrence_engine.dart';

import '../../../core/constants.dart';

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

  /// Ringtone: `system`, a bundled asset path (`assets/sounds/…`), or an
  /// absolute path inside the app's ringtone library.
  final String soundAsset;
  final double volume; // 0..1

  static const int maxLabelLength = 60;
  static const int maxSnoozeMinutes = 180;

  const Alarm({
    required this.id,
    required this.label,
    required this.rule,
    this.bounds = const RecurrenceBounds(),
    this.enabled = true,
    this.snoozeMinutes = 5,
    this.vibrate = true,
    this.soundAsset = kDefaultSoundAsset,
    this.volume = 0.8,
  });

  Alarm copyWith({
    int? id,
    String? label,
    RecurrenceRule? rule,
    RecurrenceBounds? bounds,
    bool? enabled,
    int? snoozeMinutes,
    bool? vibrate,
    String? soundAsset,
    double? volume,
  }) => Alarm(
    id: id ?? this.id,
    label: label ?? this.label,
    rule: rule ?? this.rule,
    bounds: bounds ?? this.bounds,
    enabled: enabled ?? this.enabled,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    vibrate: vibrate ?? this.vibrate,
    soundAsset: soundAsset ?? this.soundAsset,
    volume: volume ?? this.volume,
  );

  /// Null when the alarm is safe to schedule; otherwise why not. This is the
  /// one gate for every untrusted source (JSON files, the local API).
  String? validate() {
    final r = rule.validate();
    if (r != null) return r;
    final b = bounds.validate();
    if (b != null) return b;
    if (label.length > maxLabelLength) {
      return 'label must be at most $maxLabelLength characters';
    }
    if (label.contains(RegExp(r'[\x00-\x1f]'))) {
      return 'label contains control characters';
    }
    if (snoozeMinutes < 1 || snoozeMinutes > maxSnoozeMinutes) {
      return 'snoozeMinutes must be 1-$maxSnoozeMinutes';
    }
    if (volume.isNaN || volume < 0 || volume > 1) {
      return 'volume must be between 0 and 1';
    }
    if (soundAsset.isEmpty || soundAsset.length > 512) {
      return 'soundAsset is invalid';
    }
    return null;
  }

  /// Pins down anything that must not drift after creation. "Stop after N
  /// times" on a weekly/monthly rule counts from the series start; without
  /// an explicit start date that start would move to "now" every time the
  /// horizon is recomputed, so the count would never run out.
  Alarm normalized({DateTime? now}) {
    final end = bounds.end;
    final needsOrigin = rule is Weekly || rule is MonthlyOrdinal;
    if (end is EndsAfterCount && bounds.startDate == null && needsOrigin) {
      final n = now ?? DateTime.now();
      return copyWith(
        bounds: RecurrenceBounds(
          startDate: DateTime(n.year, n.month, n.day),
          end: end,
        ),
      );
    }
    return this;
  }

  /// The next time this alarm will ring, or null if its series is exhausted
  /// (or it is disabled).
  DateTime? nextFire({DateTime? from}) {
    if (!enabled) return null;
    return nextOccurrence(rule, bounds, from: from ?? DateTime.now());
  }

  /// The soonest upcoming ring across [alarms], or null when nothing is due.
  static ({Alarm alarm, DateTime at})? nextAcross(
    Iterable<Alarm> alarms, {
    DateTime? from,
  }) {
    final now = from ?? DateTime.now();
    ({Alarm alarm, DateTime at})? best;
    for (final a in alarms) {
      final f = a.nextFire(from: now);
      if (f != null && (best == null || f.isBefore(best.at))) {
        best = (alarm: a, at: f);
      }
    }
    return best;
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

  /// Structural decode only — call [validate] before trusting the result.
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
    snoozeMinutes: json['snoozeMinutes'] as int? ?? 5,
    vibrate: json['vibrate'] as bool? ?? true,
    soundAsset: json['soundAsset'] as String? ?? kDefaultSoundAsset,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
  );
}

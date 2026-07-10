import 'local_time.dart';
import 'recurrence_rule.dart';

/// A named rotating-shift template expressed as one bool per cycle day
/// (true = work day). Combine with an anchor date and shift times to produce
/// a concrete [ShiftCycle] rule.
class ShiftPattern {
  final String id;
  final String name;
  final String description;

  /// One entry per day of the full cycle; true = work day.
  final List<bool> days;

  const ShiftPattern({
    required this.id,
    required this.name,
    required this.description,
    required this.days,
  });

  int get cycleLength => days.length;
  int get workDaysPerCycle => days.where((d) => d).length;

  /// Build a concrete rule from this pattern. [perDayTimes] optionally
  /// overrides the start times for specific cycle days (0-based index).
  ShiftCycle toRule({
    required DateTime anchorDate,
    required List<LocalTime> times,
    Map<int, List<LocalTime>> perDayTimes = const {},
  }) => ShiftCycle(
    anchorDate: anchorDate,
    pattern: days,
    times: times,
    perDayTimes: perDayTimes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'days': days,
  };

  factory ShiftPattern.fromJson(Map<String, dynamic> json) => ShiftPattern(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    days: (json['days'] as List).map((e) => e as bool).toList(),
  );

  /// Expand a list of on/off run-lengths into a day pattern.
  /// e.g. `[4, 2, 3, 3]` (starting on a work run) → 4 on, 2 off, 3 on, 3 off.
  static List<bool> fromRuns(List<int> runs, {bool startsOn = true}) {
    final out = <bool>[];
    var on = startsOn;
    for (final run in runs) {
      for (var i = 0; i < run; i++) {
        out.add(on);
      }
      on = !on;
    }
    return out;
  }
}

/// Common shift-rotation presets. The "Panama" (2-2-3) is the flagship case
/// the app is built around; the rest cover the widely-used industrial rotations.
class ShiftPatterns {
  ShiftPatterns._();

  /// Panama / 2-2-3 slow rotation. 14-day cycle, single crew's work days.
  /// on on off off on on on | off off on on off off off
  static const panama = ShiftPattern(
    id: 'panama',
    name: 'Panama (2-2-3)',
    description: '2 on, 2 off, 3 on, then 2 off, 2 on, 3 off — 14-day rotation',
    days: [
      true, true, false, false, true, true, true, //
      false, false, true, true, false, false, false,
    ],
  );

  /// 4 on, 2 off, 3 on, 3 off. 12-day cycle.
  static final fourTwoThreeThree = ShiftPattern(
    id: '4-2-3-3',
    name: '4-on / 2-off / 3-on / 3-off',
    description: '4 on, 2 off, 3 on, 3 off — 12-day rotation',
    days: ShiftPattern.fromRuns([4, 2, 3, 3]),
  );

  /// 4 on, 4 off. 8-day cycle — common for 12-hour crews.
  static final fourOnFourOff = ShiftPattern(
    id: '4-4',
    name: '4-on / 4-off',
    description: '4 days on, 4 days off — 8-day rotation',
    days: ShiftPattern.fromRuns([4, 4]),
  );

  /// DuPont: 4 nights, 3 off, 3 days, 1 off, 3 nights, 3 off, 4 days, 7 off.
  /// Modeled here as work/off days over the 28-day cycle.
  static final dupont = ShiftPattern(
    id: 'dupont',
    name: 'DuPont',
    description: '28-day rotation with a built-in 7-day break',
    days: ShiftPattern.fromRuns([4, 3, 3, 1, 3, 3, 4, 7]),
  );

  /// Pitman / 2-3-2. 14-day cycle: on on off off off on on | off off on on on off off
  static const pitman = ShiftPattern(
    id: 'pitman',
    name: 'Pitman (2-3-2)',
    description: 'Every other weekend off — 14-day rotation',
    days: [
      true, true, false, false, false, true, true, //
      false, false, true, true, true, false, false,
    ],
  );

  /// Southern Swing: 7 days, 2 off, 7 swings, 2 off, 7 nights, 3 off. 28-day.
  static final southernSwing = ShiftPattern(
    id: 'southern-swing',
    name: 'Southern Swing',
    description: '7 on, 2 off across day/swing/night — 28-day rotation',
    days: ShiftPattern.fromRuns([7, 2, 7, 2, 7, 3]),
  );

  /// 5 on, 4 off / 9 on ("5-4/9" compressed schedule) simplified to 5 on 2 off.
  static final fiveOnTwoOff = ShiftPattern(
    id: '5-2',
    name: '5-on / 2-off',
    description: 'Standard work week — 7-day rotation',
    days: ShiftPattern.fromRuns([5, 2]),
  );

  static final List<ShiftPattern> all = [
    panama,
    fourTwoThreeThree,
    fourOnFourOff,
    dupont,
    pitman,
    southernSwing,
    fiveOnTwoOff,
  ];

  static ShiftPattern? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

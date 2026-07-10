/// When a recurrence stops.
sealed class EndCondition {
  const EndCondition();

  Map<String, dynamic> toJson();

  static EndCondition fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'never':
        return const NeverEnds();
      case 'onDate':
        return EndsOnDate(DateTime.parse(json['date'] as String));
      case 'afterCount':
        return EndsAfterCount(json['count'] as int);
      default:
        throw ArgumentError('Unknown EndCondition: ${json['type']}');
    }
  }
}

/// Repeats forever.
class NeverEnds extends EndCondition {
  const NeverEnds();
  @override
  Map<String, dynamic> toJson() => {'type': 'never'};
}

/// Repeats up to and including [date] (whole-day inclusive).
class EndsOnDate extends EndCondition {
  final DateTime date;
  const EndsOnDate(this.date);
  @override
  Map<String, dynamic> toJson() => {
    'type': 'onDate',
    'date': date.toIso8601String(),
  };
}

/// Fires [count] times total, then stops. Covers "run for a week then stop"
/// when paired with a daily rule (count = 7).
class EndsAfterCount extends EndCondition {
  final int count; // >= 1
  const EndsAfterCount(this.count) : assert(count >= 1);
  @override
  Map<String, dynamic> toJson() => {'type': 'afterCount', 'count': count};
}

/// Bounds shared by every [RecurrenceRule]: an optional lower bound
/// ([startDate]) and an [end] condition. The series never fires before
/// [startDate], and the end condition counts from the effective series start.
class RecurrenceBounds {
  final DateTime? startDate;
  final EndCondition end;

  const RecurrenceBounds({this.startDate, this.end = const NeverEnds()});

  Map<String, dynamic> toJson() => {
    'startDate': startDate?.toIso8601String(),
    'end': end.toJson(),
  };

  factory RecurrenceBounds.fromJson(Map<String, dynamic> json) =>
      RecurrenceBounds(
        startDate: json['startDate'] == null
            ? null
            : DateTime.parse(json['startDate'] as String),
        end: EndCondition.fromJson(
          Map<String, dynamic>.from(json['end'] as Map),
        ),
      );
}

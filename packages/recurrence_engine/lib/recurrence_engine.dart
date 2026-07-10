/// A pure-Dart recurrence engine for shift-aware alarm scheduling.
///
/// No Flutter, no I/O — deterministic date math that computes the next fire
/// instants for any [RecurrenceRule] under [RecurrenceBounds]. Kept as a
/// standalone package so it is fast to test (`dart test`) and reusable by a
/// future native iOS port.
library;

export 'src/local_time.dart';
export 'src/occurrences.dart';
export 'src/recurrence_bounds.dart';
export 'src/recurrence_rule.dart';
export 'src/shift_patterns.dart';

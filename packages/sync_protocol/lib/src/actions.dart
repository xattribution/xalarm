/// Timer/stopwatch actions relayed between paired devices. All timestamps
/// are **server-clock milliseconds** — each device converts to its own clock
/// via ClockSync, which is what keeps the two displays drift-free.
sealed class SyncAction {
  const SyncAction();

  Map<String, dynamic> toJson();

  static SyncAction fromJson(Map<String, dynamic> json) {
    switch (json['kind'] as String) {
      case 'timerSet':
        return TimerSet(durationMs: json['durationMs'] as int);
      case 'timerStart':
        return TimerStart(
          endsAtServerMs: json['endsAtServerMs'] as int,
          durationMs: json['durationMs'] as int,
        );
      case 'timerPause':
        return TimerPause(
          remainingMs: json['remainingMs'] as int,
          durationMs: json['durationMs'] as int,
        );
      case 'timerReset':
        return TimerReset(durationMs: json['durationMs'] as int);
      case 'stopwatchStart':
        return StopwatchStart(
          accumulatedMs: json['accumulatedMs'] as int,
          sinceServerMs: json['sinceServerMs'] as int,
        );
      case 'stopwatchPause':
        return StopwatchPause(accumulatedMs: json['accumulatedMs'] as int);
      case 'stopwatchReset':
        return const StopwatchReset();
      case 'stopwatchLap':
        return StopwatchLap(atMs: json['atMs'] as int);
      default:
        throw FormatException('Unknown action kind: ${json['kind']}');
    }
  }
}

class TimerSet extends SyncAction {
  final int durationMs;
  const TimerSet({required this.durationMs});
  @override
  Map<String, dynamic> toJson() => {'kind': 'timerSet', 'durationMs': durationMs};
}

class TimerStart extends SyncAction {
  final int endsAtServerMs;
  final int durationMs;
  const TimerStart({required this.endsAtServerMs, required this.durationMs});
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'timerStart',
    'endsAtServerMs': endsAtServerMs,
    'durationMs': durationMs,
  };
}

class TimerPause extends SyncAction {
  final int remainingMs;
  final int durationMs;
  const TimerPause({required this.remainingMs, required this.durationMs});
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'timerPause',
    'remainingMs': remainingMs,
    'durationMs': durationMs,
  };
}

class TimerReset extends SyncAction {
  final int durationMs;
  const TimerReset({required this.durationMs});
  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'timerReset', 'durationMs': durationMs};
}

class StopwatchStart extends SyncAction {
  final int accumulatedMs;
  final int sinceServerMs;
  const StopwatchStart({
    required this.accumulatedMs,
    required this.sinceServerMs,
  });
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'stopwatchStart',
    'accumulatedMs': accumulatedMs,
    'sinceServerMs': sinceServerMs,
  };
}

class StopwatchPause extends SyncAction {
  final int accumulatedMs;
  const StopwatchPause({required this.accumulatedMs});
  @override
  Map<String, dynamic> toJson() =>
      {'kind': 'stopwatchPause', 'accumulatedMs': accumulatedMs};
}

class StopwatchReset extends SyncAction {
  const StopwatchReset();
  @override
  Map<String, dynamic> toJson() => {'kind': 'stopwatchReset'};
}

class StopwatchLap extends SyncAction {
  final int atMs; // elapsed at lap time
  const StopwatchLap({required this.atMs});
  @override
  Map<String, dynamic> toJson() => {'kind': 'stopwatchLap', 'atMs': atMs};
}
